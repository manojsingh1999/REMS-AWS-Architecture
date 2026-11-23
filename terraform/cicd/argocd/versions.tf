# ArgoCD bootstrap for one EKS cluster (run once per environment, after terraform/environments/<env>):
#   * HA ArgoCD via Helm (values: cicd/argocd/install/values.yaml)
#   * read-only SSH deploy keys for the platform repo (charts) and the microconfig repo (values)
#   * AppProjects + ApplicationSet that syncs the 7 REMS services from the microconfig repo
#   * root Application for platform add-ons (cicd/argocd/apps/<env>/platform-addons.yaml)
#
#   terraform init -backend-config=backends/<env>.hcl
#   terraform apply -var-file=envs/<env>.tfvars
# Needs network access to the private EKS endpoint (VPN / runner in the VPC) and GITHUB_TOKEN.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.4"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.33"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_id]
}

provider "github" {
  owner = var.github_org
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

# Short-lived tokens via the AWS CLI (no long-lived kubeconfig credentials in state).
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}
