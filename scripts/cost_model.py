#!/usr/bin/env python3
"""REMS monthly AWS cost model (service-wise, per environment) - generates the tables in documentation/06-cost-model.md.

Unit prices are APPROXIMATE on-demand list prices for ap-south-1 (Mumbai), USD, rounded, and must be re-checked
in the AWS Pricing Calculator before any budget decision. Every quantity is tied to an architecture decision so
the model can be re-run when sizing changes:  python3 scripts/cost_model.py > /tmp/cost.md
"""

HOURS = 730

# ------------------------------------------------------------------ unit prices (approximate, ap-south-1)
P = {
    "eks_cluster_hr": 0.10,
    "m7g.large": 0.0846, "m7g.xlarge": 0.1692, "m7g.2xlarge": 0.3384, "t4g.large": 0.0672,
    "r7g.xlarge": 0.2142, "r7g.2xlarge": 0.4284, "c7g.xlarge": 0.1445,
    "spot_discount": 0.65,                       # typical Graviton Spot saving vs on-demand
    "ebs_gp3_gb": 0.0912,
    "aurora_r7g.2xlarge_iopt": 1.60, "aurora_r7g.xlarge_iopt": 0.80, "aurora_r7g.large": 0.31,
    "aurora_acu_hr": 0.14, "aurora_storage_iopt_gb": 0.25, "aurora_storage_gb": 0.11,
    "aurora_backup_gb": 0.021, "aurora_global_write_io_m": 0.20,
    "rds_proxy_vcpu_hr": 0.015,
    "valkey_r7g.large_hr": 0.19, "valkey_t4g.small_hr": 0.030,
    "nat_hr": 0.056, "nat_gb": 0.056,
    "alb_hr": 0.0239, "alb_lcu_hr": 0.008,
    "vpce_hr": 0.011, "vpce_gb": 0.01,
    "s3_std_gb": 0.025, "s3_ia_gb": 0.0138,
    "cw_logs_gb": 0.67, "cw_metric": 0.30,
    "waf_acl": 5.0, "waf_rule": 1.0, "waf_req_m": 0.60,
    "kms_key": 1.0, "secret": 0.40,
    "data_out_gb": 0.1093, "inter_region_gb": 0.086,
    # Bedrock (per million tokens)
    "sonnet_in": 3.00, "sonnet_out": 15.00, "haiku_in": 0.25, "haiku_out": 1.25, "titan_embed": 0.02,
}


def ec2(itype, count, spot=False):
    price = P[itype] * HOURS * count
    return price * (1 - P["spot_discount"]) if spot else price


def env_costs(name):
    c = {}
    if name == "prod":
        c["EKS control plane"] = P["eks_cluster_hr"] * HOURS
        c["EC2 - system node group (3x m7g.large OD)"] = ec2("m7g.large", 3)
        c["EC2 - general pool (avg 4 OD + 3 Spot m7g.xlarge)"] = ec2("m7g.xlarge", 4) + ec2("m7g.xlarge", 3, spot=True)
        c["EC2 - ai pool (3x r7g.xlarge OD)"] = ec2("r7g.xlarge", 3)
        c["EC2 - observability pool (4x r7g.2xlarge OD)"] = ec2("r7g.2xlarge", 4)
        c["EC2 - workers pool (avg 2x c7g.xlarge Spot)"] = ec2("c7g.xlarge", 2, spot=True)
        c["EBS gp3 (~3.5 TB: VM, Loki, Tempo, Prometheus, node roots)"] = 3500 * P["ebs_gp3_gb"]
        c["Aurora rems-core (3x r7g.2xlarge I/O-Opt + 500 GB)"] = 3 * P["aurora_r7g.2xlarge_iopt"] * HOURS + 500 * P["aurora_storage_iopt_gb"]
        c["Aurora rems-rag (2x r7g.xlarge I/O-Opt + 300 GB)"] = 2 * P["aurora_r7g.xlarge_iopt"] * HOURS + 300 * P["aurora_storage_iopt_gb"]
        c["Aurora backups beyond free tier (~1.5 TB) + Global DB write I/O"] = 1500 * P["aurora_backup_gb"] + 300 * P["aurora_global_write_io_m"]
        c["RDS Proxy (2 proxies, 40 vCPU underlying)"] = 40 * P["rds_proxy_vcpu_hr"] * HOURS
        c["ElastiCache Valkey (6x cache.r7g.large)"] = 6 * P["valkey_r7g.large_hr"] * HOURS
        c["NAT gateways (3) + 2 TB processed"] = 3 * P["nat_hr"] * HOURS + 2000 * P["nat_gb"]
        c["ALB (public + internal) incl. LCUs"] = 2 * P["alb_hr"] * HOURS + 12 * P["alb_lcu_hr"] * HOURS
        c["VPC interface endpoints (16 x 3 AZ)"] = 16 * 3 * P["vpce_hr"] * HOURS + 3000 * P["vpce_gb"]
        c["S3 (documents 500 GB, telemetry ~0.6 TB, ALB logs) + requests"] = 500 * P["s3_std_gb"] + 600 * P["s3_std_gb"] + 300 * P["s3_ia_gb"] + 60
        c["CloudWatch (EKS control plane/audit logs, Container Insights, alarms)"] = 150 * P["cw_logs_gb"] + 400 * P["cw_metric"] + 80
        c["WAF (1 ACL, 10 rules, ~430 M requests)"] = P["waf_acl"] + 10 * P["waf_rule"] + 430 * P["waf_req_m"]
        c["GuardDuty (EKS runtime, audit, RDS, S3) + Inspector ECR"] = 260
        c["KMS (9 keys + DR keys) + Secrets Manager (~25 + replicas)"] = 13 * P["kms_key"] + 30 * P["secret"] + 15
        c["Data transfer out (1.5 TB) + cross-region replication (0.8 TB)"] = 1500 * P["data_out_gb"] + 800 * P["inter_region_gb"]
        c["AWS Backup (daily copies to DR vault, ~1.5 TB warm)"] = 1500 * 0.05
        # ---- AI (100 tenants) - the main VARIABLE driver
        rca_tokens_m = 48 * 30                     # 48 M tokens/day (ai-infrastructure/README capacity model)
        chat_tokens_m = (100 * 100 * 3400) / 1e6 * 30  # 100 tenants x 100 msgs/day x 3.4k tokens
        tok = rca_tokens_m + chat_tokens_m
        cached = 0.20                              # Redis exact/semantic cache hit ratio
        billable = tok * (1 - cached)
        sonnet, haiku = 0.35 * billable, 0.65 * billable  # model tiering
        c["Bedrock LLM (tiered Sonnet/Haiku, 20% cache hits)"] = (
            sonnet * (0.85 * P["sonnet_in"] + 0.15 * P["sonnet_out"]) + haiku * (0.85 * P["haiku_in"] + 0.15 * P["haiku_out"]))
        c["Bedrock embeddings (Titan v2, ~900 M tokens)"] = 900 * P["titan_embed"]
    elif name == "prod-dr":
        c["EKS control plane"] = P["eks_cluster_hr"] * HOURS
        c["EC2 - system (3x m7g.large) + standby apps (3x m7g.xlarge, 1x r7g.xlarge)"] = (
            ec2("m7g.large", 3) + ec2("m7g.xlarge", 3) + ec2("r7g.xlarge", 1))
        c["EC2 - observability (2x r7g.xlarge, reduced DR profile)"] = ec2("r7g.xlarge", 2)
        c["EBS gp3 (~0.8 TB)"] = 800 * P["ebs_gp3_gb"]
        c["Aurora Global DB secondaries (1x r7g.2xlarge + 1x r7g.xlarge, I/O-Opt)"] = (
            P["aurora_r7g.2xlarge_iopt"] * HOURS + P["aurora_r7g.xlarge_iopt"] * HOURS + 800 * P["aurora_storage_iopt_gb"])
        c["ElastiCache Valkey (6x cache.r7g.large, warm)"] = 6 * P["valkey_r7g.large_hr"] * HOURS
        c["NAT (3) + VPC endpoints (16 x 3 AZ)"] = 3 * P["nat_hr"] * HOURS + 16 * 3 * P["vpce_hr"] * HOURS
        c["ALB + WAF (idle)"] = 2 * P["alb_hr"] * HOURS + 20
        c["S3 replica (documents) + backup vault"] = 500 * P["s3_std_gb"] + 1500 * 0.05
        c["CloudWatch, KMS, Secrets replicas"] = 120
    elif name == "staging":
        c["EKS control plane"] = P["eks_cluster_hr"] * HOURS
        c["EC2 - system (3x m7g.large) + apps (avg 3x m7g.xlarge, 50% Spot)"] = ec2("m7g.large", 3) + ec2("m7g.xlarge", 1.5) + ec2("m7g.xlarge", 1.5, spot=True)
        c["EC2 - ai (2x r7g.xlarge) + observability (2x r7g.2xlarge)"] = ec2("r7g.xlarge", 2) + ec2("r7g.2xlarge", 2)
        c["EBS gp3 (~1.2 TB)"] = 1200 * P["ebs_gp3_gb"]
        c["Aurora (core 2x r7g.large, rag 2x r7g.large) + 200 GB"] = 4 * P["aurora_r7g.large"] * HOURS + 200 * P["aurora_storage_gb"] + 40
        c["ElastiCache Valkey (4x cache.r7g.large)"] = 4 * P["valkey_r7g.large_hr"] * HOURS
        c["NAT (3) + VPC endpoints (16 x 3 AZ)"] = 3 * P["nat_hr"] * HOURS + 16 * 3 * P["vpce_hr"] * HOURS + 300 * P["nat_gb"]
        c["ALB, WAF, S3, CloudWatch, KMS, Secrets, GuardDuty"] = 2 * P["alb_hr"] * HOURS + 30 + 40 + 180 + 15 + 60
        c["Bedrock (tests + load tests)"] = 400
    elif name == "dev":
        c["EKS control plane"] = P["eks_cluster_hr"] * HOURS
        c["EC2 - system (2x t4g.large) + apps (avg 3x m7g.xlarge Spot)"] = ec2("t4g.large", 2) + ec2("m7g.xlarge", 3, spot=True)
        c["EC2 - ai + observability (2x r7g.xlarge, 60% Spot)"] = ec2("r7g.xlarge", 0.8) + ec2("r7g.xlarge", 1.2, spot=True)
        c["EBS gp3 (~0.5 TB)"] = 500 * P["ebs_gp3_gb"]
        c["Aurora Serverless v2 (2 clusters, avg 2 ACU)"] = 2 * 2 * P["aurora_acu_hr"] * HOURS + 50 * P["aurora_storage_gb"]
        c["ElastiCache Valkey (2x cache.t4g.small)"] = 2 * P["valkey_t4g.small_hr"] * HOURS
        c["NAT (1) + VPC endpoints (16 x 3 AZ)"] = P["nat_hr"] * HOURS + 16 * 3 * P["vpce_hr"] * HOURS + 100 * P["nat_gb"]
        c["ALB, WAF, S3, CloudWatch, KMS, Secrets, GuardDuty"] = 2 * P["alb_hr"] * HOURS + 20 + 15 + 80 + 15 + 30
        c["Bedrock (development)"] = 250
    elif name == "shared+security":
        c["ECR (7 repos, ~150 GB, replication)"] = 150 * 0.10 + 20
        c["Org CloudTrail (mgmt free, data events, CW copy) + Log Archive S3"] = 120 + 2000 * P["s3_ia_gb"]
        c["Security Hub + Config (org-wide)"] = 220
        c["Terraform state, GitHub OIDC, SonarQube (self-hosted t4g.large + RDS small)"] = 120
    return c


ENVS = ["prod", "prod-dr", "staging", "dev", "shared+security"]

# Optimisation levers -> (applies to label substring, saving fraction)
OPT = [
    ("EC2 - system", 0.27, "Compute Savings Plan 1y no-upfront"),
    ("EC2 - ai", 0.27, "Compute Savings Plan 1y"),
    ("EC2 - observability", 0.27, "Compute Savings Plan 1y"),
    ("EC2 - general", 0.15, "Savings Plan on the OD floor"),
    ("Aurora rems-core", 0.30, "Aurora RI 1y (r7g)"),
    ("Aurora rems-rag", 0.30, "Aurora RI 1y"),
    ("Aurora Global DB secondaries", 0.30, "Aurora RI 1y"),
    ("ElastiCache Valkey (6x", 0.30, "ElastiCache reserved nodes 1y"),
    ("Bedrock LLM", 0.25, "more Haiku routing + semantic cache + prompt trimming"),
    ("VPC interface endpoints", 0.40, "drop unused endpoints (ssm/ec2messages) in prod"),
    ("NAT (1) + VPC endpoints", 0.35, "dev: 5 essential endpoints only"),
]


def main():
    print("| Environment | Service | Monthly USD |")
    print("|---|---|---:|")
    totals = {}
    optimized = {}
    for env in ENVS:
        c = env_costs(env)
        totals[env] = sum(c.values())
        opt_total = 0.0
        for k, v in c.items():
            print(f"| {env} | {k} | {v:,.0f} |")
            saving = 0.0
            for sub, frac, _ in OPT:
                if sub in k:
                    saving = frac
            opt_total += v * (1 - saving)
        if env in ("dev", "staging"):
            # scheduled scale-down of dev/staging compute outside 08:00-20:00 IST weekdays (~60% fewer hours)
            compute = sum(v for k, v in c.items() if k.startswith("EC2"))
            opt_total -= compute * (0.60 if env == "dev" else 0.40)
        optimized[env] = opt_total
        print(f"| **{env} total** | | **{totals[env]:,.0f}** |")
    grand = sum(totals.values())
    grand_opt = sum(optimized.values())
    print()
    print("| Environment | On-demand / month | Optimized / month | Saving |")
    print("|---|---:|---:|---:|")
    for env in ENVS:
        print(f"| {env} | {totals[env]:,.0f} | {optimized[env]:,.0f} | {1 - optimized[env] / totals[env]:.0%} |")
    print(f"| **All environments** | **{grand:,.0f}** | **{grand_opt:,.0f}** | **{1 - grand_opt / grand:.0%}** |")
    print()
    prod = env_costs("prod")
    ai = sum(v for k, v in prod.items() if "Bedrock" in k)
    print(f"Prod infrastructure excluding AI: {totals['prod'] - ai:,.0f} USD/month; AI (Bedrock): {ai:,.0f} USD/month "
          f"({ai / totals['prod']:.0%} of prod) -> ~{(totals['prod'] - ai) / 100:,.0f} USD infra + {ai / 100:,.0f} USD AI per tenant at 100 tenants.")


if __name__ == "__main__":
    main()
