# Architecture Diagrams

All diagrams are Mermaid, so they render on GitHub. They describe what the Terraform, Kubernetes and Helm code in this repository **would** create. ⚠️ Nothing has been deployed. Editable Excalidraw versions (AWS architecture, CI/CD flow, DevSecOps pillars) were produced separately and aren't stored in this repository.

Contents: [1 Complete AWS](#1-complete-aws-architecture) · [2 Multi-account](#2-multi-account-landing-zone) · [3 VPC](#3-vpc-and-subnets) · [4 EKS](#4-eks-deployment) · [5 App communication](#5-application-communication) · [6 CI/CD](#6-cicd-and-gitops) · [7 Database](#7-database) · [8 Observability](#8-observability) · [9 AI / RAG / MCP](#9-ai-rag-and-mcp) · [10 HA / DR](#10-high-availability-and-disaster-recovery)

## 1. Complete AWS architecture

```mermaid
flowchart TB
  subgraph Internet
    USR[Tenant users]
    AGT[Customer OTel agents]
    GH[GitHub Actions]
  end
  subgraph Shared["Shared Services account"]
    ECR[(ECR rems/*)]
  end
  subgraph Prod["Prod account - ap-south-1"]
    R53[Route 53] --> WAF[WAF] --> ALB[Public ALB]
    subgraph VPC["VPC 10.30.0.0/16 - 3 AZ"]
      NAT[NAT x3]
      subgraph EKS["EKS rems-prod"]
        SVC[7 REMS services]
        GW[LLM gateway]
        OBS[Observability stack]
        ARGO[ArgoCD]
      end
      PROXY[RDS Proxy x2]
      AUR[(Aurora core + rag)]
      VK[(Valkey)]
      EP[VPC endpoints]
    end
    S3[(S3 documents, telemetry, ALB logs)]
    KMS[KMS + Secrets Manager]
    COG[Cognito]
    BR[Bedrock + Guardrails]
    CW[CloudWatch + SNS]
  end
  subgraph DR["Prod account - ap-southeast-1"]
    DRS[(Aurora Global secondary, S3 replica, backup vault)]
  end
  USR --> R53
  AGT --> R53
  ALB --> SVC & OBS
  SVC --> PROXY --> AUR
  SVC --> VK
  GW --> EP --> BR
  OBS --> S3
  SVC --> KMS
  USR -.login.-> COG
  GH -->|OIDC| ECR
  ECR -->|pull via endpoint| EKS
  AUR -.storage replication.-> DRS
  S3 -.CRR + RTC.-> DRS
  EKS --> CW
```

## 2. Multi-account landing zone

```mermaid
flowchart TB
  MGMT[Management account<br/>Organizations, SCPs, org CloudTrail]
  subgraph SEC["OU Security"]
    SA[Security / Audit account<br/>GuardDuty, Security Hub, Inspector, Config aggregator]
    LA[Log Archive account<br/>S3 Object Lock]
  end
  subgraph INF["OU Infrastructure"]
    NET[Network account<br/>TGW, Network Firewall - planned]
    SH[Shared Services account<br/>ECR, CI roles]
  end
  subgraph WL["OU Workloads"]
    subgraph NP["OU NonProd"]
      DEV[dev 111111111111]
      STG[staging 222222222222]
    end
    subgraph PR["OU Prod"]
      PROD[prod + DR 333333333333]
    end
  end
  MGMT --> SEC & INF & WL
  DEV & STG & PROD -.logs.-> LA
  DEV & STG & PROD -.findings.-> SA
  SH -.images.-> DEV & STG & PROD
```

## 3. VPC and subnets

```mermaid
flowchart TB
  IGW[Internet Gateway]
  subgraph VPC["VPC 10.30.0.0/16"]
    subgraph A["ap-south-1a"]
      PA[public 10.30.0.0/24<br/>ALB, NAT-a]
      AA[private-app 10.30.32.0/19<br/>nodes + pods]
      DA[private-data 10.30.3.0/24<br/>Aurora, Valkey]
      IA[intra 10.30.6.0/26]
    end
    subgraph B["ap-south-1b"]
      PB[public 10.30.1.0/24]
      AB[private-app 10.30.64.0/19]
      DB[private-data 10.30.4.0/24]
      IB[intra 10.30.6.64/26]
    end
    subgraph C["ap-south-1c"]
      PC[public 10.30.2.0/24]
      AC[private-app 10.30.96.0/19]
      DC[private-data 10.30.5.0/24]
      IC[intra 10.30.6.128/26]
    end
    S3GW[S3 gateway endpoint]
    IEP[16 interface endpoints]
  end
  TGW[Transit Gateway - optional]
  IGW --- PA & PB & PC
  AA --> PA
  AB --> PB
  AC --> PC
  AA & AB & AC --> IEP
  AA & AB & AC --> S3GW
  IA & IB & IC -.-> TGW
```

## 4. EKS deployment

```mermaid
flowchart LR
  subgraph Cluster["EKS rems-ENV"]
    subgraph nsArgo["argocd"]
      AC[ArgoCD HA]
    end
    subgraph nsKube["kube-system"]
      KP[Karpenter] & LBC[AWS LB Controller] & MS[metrics-server]
    end
    subgraph nsRems["rems"]
      FE[rems-frontend] & API[rems-api] & AZ[authorization-service] & DG[data-governance]
    end
    subgraph nsAI["rems-ai"]
      RCA[metadata-rca] & CE[chat-engine] & MCP[mcp-server] & LLM[llm-gateway]
    end
    subgraph nsObs["observability / monitoring"]
      OT[OTel] & VM[VictoriaMetrics] & LK[Loki] & TP[Tempo] & KPS[kube-prometheus-stack]
    end
    subgraph nsPol["kyverno / keda / argo-rollouts / external-secrets"]
      KY[Kyverno] & KE[KEDA] & RO[Argo Rollouts] & ES[ESO]
    end
  end
  AC -->|sync waves -40 to 4| nsKube & nsPol & nsObs & nsRems & nsAI
  KP -->|EC2 nodes| nsRems & nsAI & nsObs
  ES -->|Secrets Manager| nsRems & nsAI
```

## 5. Application communication

```mermaid
flowchart LR
  B[Browser] -->|HTTPS /| FE[rems-frontend]
  B -->|HTTPS /api| API[rems-api]
  B -->|HTTPS /chat| CE[chat-engine]
  M[MCP client via VPN] -->|internal ALB /mcp| MCP[mcp-server]
  API --> AZ[authorization-service]
  CE --> AZ
  MCP --> AZ
  DG[data-governance] --> AZ
  RCA[metadata-rca] --> AZ
  CE --> API
  CE --> MCP
  CE --> RCA
  CE --> LLM[llm-gateway :4000]
  RCA --> LLM
  MCP --> API
  MCP --> OBS[VictoriaMetrics / Loki / Tempo read]
  API --> OBS
  API --> PG[(Aurora core via RDS Proxy)]
  AZ --> PG
  DG --> PG
  RCA --> PGR[(Aurora rag)]
  RCA --> S3[(S3 documents)]
  API & AZ & CE & RCA & LLM --> VK[(Valkey)]
  DG -->|TGW| CDB[(Customer databases)]
```

## 6. CI/CD and GitOps

```mermaid
flowchart LR
  PR[PR merged to main] --> TAG[Date tag YYYY.MM.DD-run]
  TAG --> LINT[Lint + unit tests]
  LINT --> BUILD[docker buildx]
  BUILD --> TRIVY[Trivy image scan<br/>gate: CRITICAL/HIGH]
  TRIVY --> PUSH[Push to ECR + cosign sign]
  PUSH --> CFG[PR to rems-microconfig<br/>apps/SERVICE/values-dev.yaml tag]
  CFG --> AM[Auto-merge dev]
  AM --> ARGO[ArgoCD ApplicationSet]
  ARGO --> EKS[EKS rollout]
  EKS --> AN[Argo Rollouts canary analysis]
  AN -->|fail| RB[Automatic abort]
  CFG -.->|promote workflow: staging, prod with approvals| ARGO
```

## 7. Database

```mermaid
flowchart TB
  subgraph Primary["ap-south-1"]
    PX[RDS Proxy core RW + RO] --> CW[(core writer)]
    PX --> CR1[(core reader a)]
    PX --> CR2[(core reader b)]
    PXR[RDS Proxy rag] --> RW[(rag writer pgvector)]
    PXR --> RR[(rag reader)]
    VK[(Valkey 3 shards x 1 replica)]
    BK[AWS Backup vault - Vault Lock]
  end
  subgraph DRr["ap-southeast-1"]
    CS[(core secondary)]
    RS[(rag secondary)]
    BKD[DR backup vault]
  end
  CW -.Global DB less than 1s lag.-> CS
  RW -.Global DB.-> RS
  BK -.daily copy.-> BKD
```

## 8. Observability

```mermaid
flowchart LR
  APPS[REMS pods] -->|OTLP| OTC[OTel Collector gateway]
  AGENTS[Customer agents] -->|OTLP via ALB| OTC
  OTC -->|metrics remote write| VM[VictoriaMetrics]
  OTC -->|logs| LK[Loki]
  OTC -->|traces| TP[Tempo]
  LK --> S3[(S3 telemetry bucket)]
  TP --> S3
  PROM[Prometheus kube-prometheus-stack] -->|platform metrics| AM[Alertmanager]
  PROM --> GF[Grafana]
  VM --> GF
  LK --> GF
  TP --> GF
  AM -->|SNS / pager| ONC[On-call]
  CW[CloudWatch alarms - out of band] --> SNS[SNS] --> ONC
```

## 9. AI, RAG and MCP

```mermaid
flowchart LR
  CE[chat-engine] --> GW[llm-gateway LiteLLM]
  RCA[metadata-rca] --> GW
  GW -->|budget + rate limit per tenant| VK[(Valkey)]
  GW -->|primary, private endpoint| BR[Bedrock + Guardrails]
  GW -.fallback, circuit breaker.-> EXT[External LLM providers]
  RCA -->|ingest| S3[(S3 documents)]
  RCA -->|embed| GW
  RCA -->|vectors with tenant_id + RLS| PG[(Aurora rag pgvector HNSW)]
  CE -->|tool calls| MCP[mcp-server read-only]
  MCP -->|OPA policy mcp_tools.rego| AZ[authorization-service]
  MCP --> OBS[Metrics, logs, traces read APIs]
```

## 10. High availability and disaster recovery

```mermaid
flowchart TB
  R53[Route 53 health checks - planned]
  subgraph P["ap-south-1 (active)"]
    EKS1[EKS 3 AZ]
    AUR1[(Aurora writer + readers)]
    S31[(S3)]
  end
  subgraph D["ap-southeast-1 (pilot light)"]
    EKS2[EKS rems-prod-dr minimal nodes]
    AUR2[(Aurora secondary)]
    S32[(S3 replica)]
  end
  R53 --> EKS1
  R53 -.failover.-> EKS2
  AUR1 -.Global DB.-> AUR2
  S31 -.CRR RTC 15 min.-> S32
  OPS[Operator runs runbooks/dr-regional-failover.md] -->|switchover / failover-global-cluster| AUR2
  OPS -->|dr_promoted = true, scale nodes| EKS2
```

## Hand-drawn views (Excalidraw)

![AWS architecture](../diagrams/aws-architecture.png)
![CI/CD flow](../diagrams/cicd-flow.png)
![Seven DevSecOps pillars](../diagrams/devsecops-pillars.png)
