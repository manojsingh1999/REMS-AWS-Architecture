terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

data "aws_region" "current" {}

locals {
  az_count = length(var.azs)
  az_index = { for idx, az in var.azs : az => idx }

  # Deterministic subnet plan for a /16 (see architecture/03-network.md)
  #   public       /24  -> x.x.0.0  .. x.x.2.0
  #   private-data /24  -> x.x.3.0  .. x.x.5.0
  #   intra        /26  -> x.x.6.0  .. x.x.6.128
  #   private-app  /19  -> x.x.32.0 .. x.x.96.0
  public_cidrs = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 8, i) }
  data_cidrs   = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 8, 3 + i) }
  intra_cidrs  = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 10, 24 + i) }
  app_cidrs    = { for az, i in local.az_index : az => cidrsubnet(var.cidr_block, 3, 1 + i) }

  nat_azs = var.single_nat_gateway ? [var.azs[0]] : var.azs
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = var.name })
}

# Lock down the default SG (CIS 5.4).
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-default-deny" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-igw" })
}

# ---------------------------------------------------------------- subnets
resource "aws_subnet" "public" {
  for_each                = local.public_cidrs
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false
  tags = merge(var.tags, {
    Name                     = "${var.name}-public-${each.key}"
    Tier                     = "public"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "app" {
  for_each          = local.app_cidrs
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
  tags = merge(var.tags, {
    Name                              = "${var.name}-app-${each.key}"
    Tier                              = "private-app"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  })
}

resource "aws_subnet" "data" {
  for_each          = local.data_cidrs
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
  tags              = merge(var.tags, { Name = "${var.name}-data-${each.key}", Tier = "private-data" })
}

resource "aws_subnet" "intra" {
  for_each          = local.intra_cidrs
  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key
  tags              = merge(var.tags, { Name = "${var.name}-intra-${each.key}", Tier = "intra" })
}

# ---------------------------------------------------------------- NAT
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.nat_azs)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
  depends_on    = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------- routing
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# One route table per AZ for app subnets -> NAT in the same AZ (static stability).
resource "aws_route_table" "app" {
  for_each = toset(var.azs)
  vpc_id   = aws_vpc.this.id
  tags     = merge(var.tags, { Name = "${var.name}-app-${each.key}" })
}

resource "aws_route" "app_nat" {
  for_each               = toset(var.azs)
  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[var.azs[0]].id : aws_nat_gateway.this[each.key].id
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Data and intra subnets have NO default route (no internet path at all).
resource "aws_route_table" "isolated" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name}-isolated" })
}

resource "aws_route_table_association" "data" {
  for_each       = aws_subnet.data
  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}

resource "aws_route_table_association" "intra" {
  for_each       = aws_subnet.intra
  subnet_id      = each.value.id
  route_table_id = aws_route_table.isolated.id
}

# Optional Transit Gateway attachment (network account shares the TGW via RAM).
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count              = var.transit_gateway_id == null ? 0 : 1
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = aws_vpc.this.id
  subnet_ids         = [for s in aws_subnet.intra : s.id]
  dns_support        = "enable"
  tags               = merge(var.tags, { Name = "${var.name}-tgw" })
}

resource "aws_route" "app_to_tgw" {
  for_each = {
    for pair in (var.transit_gateway_id == null ? [] : setproduct(var.azs, var.transit_gateway_routes)) :
    "${pair[0]}-${pair[1]}" => { az = pair[0], cidr = pair[1] }
  }
  route_table_id         = aws_route_table.app[each.value.az].id
  destination_cidr_block = each.value.cidr
  transit_gateway_id     = var.transit_gateway_id
  depends_on             = [aws_ec2_transit_gateway_vpc_attachment.this]
}

# ---------------------------------------------------------------- endpoints
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat([for rt in aws_route_table.app : rt.id], [aws_route_table.isolated.id])
  tags              = merge(var.tags, { Name = "${var.name}-s3" })
}

resource "aws_security_group" "endpoints" {
  name        = "${var.name}-vpc-endpoints"
  description = "HTTPS from inside the VPC to interface endpoints"
  vpc_id      = aws_vpc.this.id
  tags        = merge(var.tags, { Name = "${var.name}-vpc-endpoints" })
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  security_group_id = aws_security_group.endpoints.id
  description       = "HTTPS from VPC"
  cidr_ipv4         = var.cidr_block
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = toset(var.interface_endpoints)
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = [for s in aws_subnet.app : s.id]
  security_group_ids  = [aws_security_group.endpoints.id]
  tags                = merge(var.tags, { Name = "${var.name}-${each.value}" })
}

# ---------------------------------------------------------------- flow logs
resource "aws_cloudwatch_log_group" "flow_logs" {
  count             = var.flow_logs_destination_arn == null ? 1 : 0
  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.logs_kms_key_arn
  tags              = var.tags
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  count              = var.flow_logs_destination_arn == null ? 1 : 0
  name               = "${var.name}-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogGroups", "logs:DescribeLogStreams"]
    resources = var.flow_logs_destination_arn == null ? ["${aws_cloudwatch_log_group.flow_logs[0].arn}:*"] : ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  count  = var.flow_logs_destination_arn == null ? 1 : 0
  name   = "flow-logs"
  role   = aws_iam_role.flow_logs[0].id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "this" {
  vpc_id                   = aws_vpc.this.id
  traffic_type             = "ALL"
  max_aggregation_interval = 60
  log_destination_type     = var.flow_logs_destination_arn == null ? "cloud-watch-logs" : "s3"
  log_destination          = var.flow_logs_destination_arn == null ? aws_cloudwatch_log_group.flow_logs[0].arn : var.flow_logs_destination_arn
  iam_role_arn             = var.flow_logs_destination_arn == null ? aws_iam_role.flow_logs[0].arn : null

  dynamic "destination_options" {
    for_each = var.flow_logs_destination_arn == null ? [] : [1]
    content {
      file_format                = "parquet"
      per_hour_partition         = true
      hive_compatible_partitions = true
    }
  }
  tags = var.tags
}
