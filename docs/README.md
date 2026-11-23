# REMS AWS Implementation Guide

Step-by-step documentation of how the REMS platform in this repository is designed, implemented, configured, deployed, validated and maintained on AWS.

> **Read this first.** Everything described here exists as code in this repository and has been validated **offline** (static analysis, rendering, schema and policy checks). **Nothing has been deployed to AWS.** No command output in these pages comes from a real account. Every value shaped like an account ID, ARN, domain or tag (`111111111111`, `rems.example.com`, `PLACEHOLDER-…`, `sha-0000000`) is a placeholder to replace. Current status per component: [IMPLEMENTATION-STATUS.md](IMPLEMENTATION-STATUS.md).

## Status legend

| Mark | Meaning |
|---|---|
| ✅ | Implemented in this repository and validated offline |
| 🟡 | Partially implemented, or depends on placeholders / application code not in this repo |
| 📋 | Planned or designed only, no code yet |
| ⚠️ | Not yet validated against a real AWS account / cluster |

## How each implementation page is structured

Objective → prerequisites → AWS services → steps with exact commands → Terraform / Kubernetes configuration taken from the repository (with file paths) → configuration explained → verification → security considerations → troubleshooting → rollback. Pages that are reference tables (troubleshooting indexes, cost breakdowns) skip the sections that don't apply.

## Suggested reading order

1. [Architecture overview](01-architecture/overview.md) and [all diagrams](01-architecture/architecture-diagrams.md)
2. [Infrastructure deployment order](02-aws-infrastructure/infrastructure-deployment.md)
3. [Deployment runbook](14-operations/deployment-runbook.md)
4. [Implementation status](IMPLEMENTATION-STATUS.md)

## Index

### 01 · Architecture
- [Overview](01-architecture/overview.md)
- [AWS architecture](01-architecture/aws-architecture.md)
- [Network architecture](01-architecture/network-architecture.md)
- [EKS architecture](01-architecture/eks-architecture.md)
- [Application architecture](01-architecture/application-architecture.md)
- [Database architecture](01-architecture/database-architecture.md)
- [Architecture diagrams (10 Mermaid views)](01-architecture/architecture-diagrams.md)

### 02 · AWS infrastructure
- [AWS account setup (landing zone)](02-aws-infrastructure/aws-account-setup.md)
- [IAM configuration](02-aws-infrastructure/iam-configuration.md)
- [VPC setup](02-aws-infrastructure/vpc-setup.md)
- [Subnet configuration](02-aws-infrastructure/subnet-configuration.md)
- [Security groups](02-aws-infrastructure/security-groups.md)
- [VPC endpoints](02-aws-infrastructure/vpc-endpoints.md)
- [EKS setup](02-aws-infrastructure/eks-setup.md)
- [Infrastructure deployment (end-to-end order)](02-aws-infrastructure/infrastructure-deployment.md)

### 03 · Terraform
- [Installation](03-terraform/installation.md)
- [Project structure](03-terraform/project-structure.md)
- [Backend configuration](03-terraform/backend-configuration.md)
- [Modules explained](03-terraform/modules-explanation.md)
- [Environment configuration](03-terraform/environment-configuration.md)
- [Terraform deployment](03-terraform/terraform-deployment.md)
- [Troubleshooting](03-terraform/troubleshooting.md)

### 04 · Kubernetes
- [Cluster configuration](04-kubernetes/cluster-configuration.md)
- [Namespaces](04-kubernetes/namespaces.md)
- [Deployments](04-kubernetes/deployments.md)
- [Services](04-kubernetes/services.md)
- [Ingress](04-kubernetes/ingress.md)
- [Autoscaling](04-kubernetes/autoscaling.md)
- [Network policies](04-kubernetes/network-policies.md)
- [Troubleshooting](04-kubernetes/troubleshooting.md)

### 05 · Helm
- [Helm installation](05-helm/helm-installation.md)
- [Chart structure](05-helm/chart-structure.md)
- [Values configuration](05-helm/values-configuration.md)
- [Application deployment](05-helm/application-deployment.md)

### 06 · CI/CD
- [Git branching strategy](06-cicd/git-branching-strategy.md)
- [GitHub Actions](06-cicd/github-actions.md)
- [Docker build](06-cicd/docker-build.md)
- [ECR integration](06-cicd/ecr-integration.md)
- [Security scanning](06-cicd/security-scanning.md)
- [ArgoCD setup](06-cicd/argocd-setup.md)
- [Deployment workflow](06-cicd/deployment-workflow.md)
- [Rollback procedure](06-cicd/rollback-procedure.md)

### 07 · Security
- [IAM security](07-security/iam-security.md)
- [Secrets management](07-security/secrets-management.md)
- [Encryption](07-security/encryption.md)
- [Container security](07-security/container-security.md)
- [Kubernetes security](07-security/kubernetes-security.md)
- [Tenant isolation](07-security/tenant-isolation.md)
- [MCP security](07-security/mcp-security.md)

### 08 · Database
- [PostgreSQL setup](08-database/postgresql-setup.md)
- [Redis setup](08-database/redis-setup.md)
- [Backup and restore](08-database/backup-and-restore.md)
- [Connection pooling](08-database/connection-pooling.md)
- [Disaster recovery](08-database/disaster-recovery.md)

### 09 · Monitoring
- [Prometheus and VictoriaMetrics](09-monitoring/prometheus.md)
- [Grafana](09-monitoring/grafana.md)
- [Loki](09-monitoring/loki.md)
- [Tempo](09-monitoring/tempo.md)
- [OpenTelemetry](09-monitoring/opentelemetry.md)
- [Alerting](09-monitoring/alerting.md)
- [Dashboards](09-monitoring/dashboards.md)

### 10 · AI infrastructure
- [AI architecture](10-ai-infrastructure/ai-architecture.md)
- [RAG implementation](10-ai-infrastructure/rag-implementation.md)
- [pgvector](10-ai-infrastructure/pgvector.md)
- [LLM integration](10-ai-infrastructure/llm-integration.md)
- [MCP server](10-ai-infrastructure/mcp-server.md)

### 11 · High availability and disaster recovery
- [High availability](11-ha-dr/high-availability.md)
- [Disaster recovery](11-ha-dr/disaster-recovery.md)
- [Backup strategy](11-ha-dr/backup-strategy.md)
- [Recovery runbook](11-ha-dr/recovery-runbook.md)

### 12 · Testing
- [Terraform validation](12-testing/terraform-validation.md)
- [Helm validation](12-testing/helm-validation.md)
- [Application testing](12-testing/application-testing.md)
- [k6 load testing](12-testing/k6-load-testing.md)
- [Failure scenarios](12-testing/failure-scenarios.md)

### 13 · Cost optimization
- [AWS cost estimation](13-cost-optimization/aws-cost-estimation.md)
- [Cost breakdown](13-cost-optimization/cost-breakdown.md)
- [Optimization](13-cost-optimization/optimization.md)

### 14 · Operations
- [Deployment runbook](14-operations/deployment-runbook.md)
- [Maintenance](14-operations/maintenance.md)
- [Troubleshooting index](14-operations/troubleshooting.md)
- [Incident management](14-operations/incident-management.md)
- [Operational checklist](14-operations/operational-checklist.md)

### Project tracking
- [Implementation status](IMPLEMENTATION-STATUS.md)
- [Changelog](CHANGELOG.md)

## Related material elsewhere in the repository

| Folder | Content |
|---|---|
| [`architecture/`](../architecture/README.md) | Original design documents (10 files, 19 diagrams) |
| [`documentation/`](../documentation/) | Requirements checklist, assumptions (P1–P9), deployment matrix, deployment guide, capacity plan, cost model, roadmap |
| [`runbooks/`](../runbooks/README.md) | 12 operational runbooks |
| [`security/`](../security/README.md) | Threat model, audit logging, secrets rotation, policies |
