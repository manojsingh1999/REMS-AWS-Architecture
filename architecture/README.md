# REMS Architecture

| # | Document | Covers |
|---|---|---|
| 01 | [AWS overview](01-aws-overview.md) | End-to-end diagram, placement of every component |
| 02 | [Multi-account landing zone](02-multi-account-landing-zone.md) | OUs, accounts, SCPs, access model |
| 03 | [Network](03-network.md) | Multi-AZ VPC, CIDRs, endpoints, egress |
| 04 | [EKS platform](04-eks-platform.md) | Compute, scheduling, autoscaling, ingress, zero downtime |
| 05 | [Traffic flow](05-traffic-flow.md) | UI/API, telemetry ingestion, AI/chat, east-west allow-list |
| 06 | [Data architecture](06-data-architecture.md) | Aurora, RDS Proxy, Redis, S3, observability stores |
| 07 | [Security](07-security.md) | Identity, tenant isolation, encryption, supply chain, MCP |
| 08 | [AI / RAG / MCP](08-ai-rag-mcp.md) | Gateway, quotas, failover, data protection, cost |
| 09 | [HA / DR](09-ha-dr.md) | Availability budget, AZ failure, regional DR, validation |
| 10 | [CI/CD](10-cicd.md) | Pipeline stages, gates, GitOps, rollback |

Key design principles:

1. **Managed over self-managed** for stateful tiers (Aurora, ElastiCache, S3). Self-managed only where the product requires it (VictoriaMetrics, Loki, Tempo).
2. **Static stability**: survive an AZ loss without any control-plane action.
3. **Tenant isolation in depth**: token → policy → database → telemetry → objects.
4. **Everything as code**: Terraform for AWS, Helm and GitOps for Kubernetes, policies as code (SCP, OPA, Kyverno).
5. **Cost awareness**: Graviton, Spot for stateless and batch, S3 tiering, per-tenant telemetry and LLM budgets.
