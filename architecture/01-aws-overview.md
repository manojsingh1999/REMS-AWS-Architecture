# 01 – Complete AWS Architecture (Production)

```mermaid
flowchart TB
  subgraph Users["Tenants & Operators"]
    U1[Browser - REMS UI]
    U2[AI agents / IDEs - MCP clients]
    U3[Customer telemetry agents - OTLP]
  end

  subgraph Edge["Edge (prod account, ap-south-1)"]
    R53[Route 53 - failover records + health checks]
    WAF[AWS WAF - managed rules, rate limits, geo]
    ALBPUB[Public ALB - ACM TLS 1.3]
    NLBINT[Internal ALB - MCP + admin]
  end

  subgraph VPC["Prod VPC 10.30.0.0/16 - 3 AZ"]
    subgraph EKS["EKS 1.31 - private endpoint"]
      FE[rems-frontend]
      API[rems-api + workers]
      AUTHZ[authorization-service + OPA]
      GOV[data-governance]
      RCA[metadata-rca / Savvy]
      CHAT[chat-engine]
      MCP[mcp-server]
      LLMGW[LLM gateway - LiteLLM]
      OTEL[OTel Collector gateway]
      OBS[(VictoriaMetrics / Loki / Tempo)]
      PLAT[ArgoCD, Karpenter, ESO, ALB ctrl, Kyverno]
    end
    RDSP[RDS Proxy]
    AUR[(Aurora PG 16 core - writer + 2 readers)]
    AURV[(Aurora PG 16 rag - pgvector)]
    REDIS[(ElastiCache Valkey - cluster mode, Multi-AZ)]
    VPCE[VPC endpoints: ECR, S3, STS, KMS, SM, Logs, Bedrock]
  end

  subgraph Regional["Regional services"]
    S3D[(S3 rag-documents)]
    S3T[(S3 telemetry - Loki/Tempo/VM backups)]
    SM[Secrets Manager]
    KMS[KMS CMKs - multi-Region]
    BR[Amazon Bedrock + Guardrails]
    COG[Cognito - federated to tenant IdPs]
    CW[CloudWatch + SNS]
  end

  EXT[External LLM providers - fallback]
  NFW[Network Firewall - egress FQDN allowlist]
  DR[(DR region ap-southeast-1 - warm standby)]

  U1 --> R53 --> WAF --> ALBPUB
  U3 --> R53
  ALBPUB --> FE & API & CHAT & OTEL
  U2 -->|PrivateLink / VPN| NLBINT --> MCP
  FE -.-> API
  API --> AUTHZ
  CHAT --> AUTHZ
  MCP --> AUTHZ
  MCP --> API
  API & GOV & AUTHZ --> RDSP --> AUR
  RCA --> RDSP
  RCA --> AURV
  API & CHAT & AUTHZ & LLMGW --> REDIS
  RCA & CHAT --> LLMGW --> VPCE --> BR
  LLMGW --> NFW --> EXT
  API --> OBS
  OTEL --> OBS --> S3T
  RCA --> S3D
  PLAT --> SM
  COG -. JWT .-> AUTHZ
  AUR -. Aurora Global DB .-> DR
  S3D -. CRR + RTC .-> DR
  CW -. alarms .-> U1
```

## Component placement summary

| Layer | Service | Placement | Why |
|---|---|---|---|
| Edge | Route 53, WAF, ALB (via AWS Load Balancer Controller) | Public subnets, 3 AZ | Managed L7, WAF integration, TLS offload |
| Compute | EKS managed control plane + Karpenter-provisioned nodes | private-app subnets, 3 AZ | Independent per-service scaling, bin-packing, Spot |
| Data | Aurora PostgreSQL (core + rag), ElastiCache Valkey, RDS Proxy | private-data subnets, no route to the internet | Isolation, managed HA |
| Storage | S3 (documents, telemetry, artifacts, logs) | Regional, reached via gateway endpoint | 11 nines durability, lifecycle tiering |
| AI | Bedrock (interface endpoint), LLM gateway in EKS, external providers via Network Firewall | private | Quota control, data protection, failover |
| Security | GuardDuty, Security Hub, CloudTrail (org), Config, Inspector, Access Analyzer | Security + Log Archive accounts | Central, tamper-resistant |
| Observability | OTel Collector, kube-prometheus-stack, Loki, Tempo, Grafana, CloudWatch | EKS `observability` node pool + CloudWatch | Self-monitoring with an out-of-band path |

See the other documents in this folder for each layer in detail.
