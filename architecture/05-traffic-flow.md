# 05 – Application Traffic Flow

## User request (UI → API → data)

```mermaid
sequenceDiagram
  autonumber
  participant B as Browser
  participant R as Route 53
  participant W as WAF
  participant A as ALB (rems-public)
  participant F as rems-frontend
  participant C as Cognito / tenant IdP
  participant API as rems-api
  participant Z as authorization-service (OPA)
  participant RD as Redis
  participant P as RDS Proxy
  participant DB as Aurora PG (RLS)
  B->>R: app.rems.example.com
  R-->>B: ALB alias (failover record)
  B->>W: HTTPS GET /
  W->>A: allowed (managed rules, rate based rule)
  A->>F: static SPA (cache-control immutable assets)
  B->>C: OIDC Authorization Code + PKCE
  C-->>B: JWT (sub, tenant_id, roles)
  B->>A: /api/... Bearer JWT
  A->>API: target-type ip
  API->>API: verify JWT signature (JWKS cached)
  API->>Z: check(subject, tenant, action, resource)
  Z->>RD: decision cache lookup
  Z-->>API: allow / deny (+ audit event)
  API->>P: BEGIN, set_config('app.tenant_id', tenant, true), SELECT ...
  P->>DB: pooled connection
  DB-->>API: rows filtered by RLS policy
  API-->>B: 200 JSON + traceparent
```

## Telemetry ingestion (50 M events/day)

```mermaid
flowchart LR
  AG[Customer OTel agents / exporters] -->|OTLP/HTTP + tenant API key| ALB[ALB /otlp]
  ALB --> GW[OTel Collector gateway<br/>HPA 3-30, memory_limiter, batch]
  GW -->|X-Scope-OrgID = tenant| LOKI[Loki distributor]
  GW -->|X-Scope-OrgID = tenant| TEMPO[Tempo distributor]
  GW -->|/insert/accountID/| VM[vminsert]
  GW -->|events| API[rems-api ingest] --> Q[(Redis streams)] --> WRK[rems-api-worker]
  LOKI & TEMPO --> S3[(S3 telemetry bucket)]
  VM --> EBS[(vmstorage gp3)]
```

## AI / chat flow

```mermaid
sequenceDiagram
  participant U as User
  participant CH as chat-engine
  participant Z as authz
  participant M as mcp-server
  participant GW as LLM gateway
  participant BR as Bedrock (VPC endpoint)
  participant EX as External LLM (fallback)
  U->>CH: "why is checkout latency high?" (JWT)
  CH->>Z: may tenant T use chat?
  CH->>M: tool call: query_traces(service=checkout) (user token, on behalf of)
  M->>Z: authorize tool + tenant scope
  M-->>CH: trace summary (tenant T data only)
  CH->>GW: completion request (tenant budget header)
  GW->>BR: InvokeModel (guardrail id)
  alt Bedrock throttled / unavailable
    GW->>EX: fallback model (egress allowlist)
  end
  GW-->>CH: streamed answer
  CH-->>U: SSE stream
```

## East-west allow-list (enforced by NetworkPolicies)

| From → To | Port | Why |
|---|---|---|
| ingress (ALB IPs) → frontend, rems-api, chat-engine, otel-gateway | app ports | Public entry |
| internal ALB → mcp-server | app port | MCP clients |
| frontend → none | – | SPA only |
| rems-api → authz, Redis, RDS Proxy, VictoriaMetrics, Loki, Tempo, kube-apiserver | various | PDF integrations |
| chat-engine → authz, mcp-server, llm-gateway, Redis, rems-api | | |
| metadata-rca → authz, llm-gateway, RDS Proxy (rag), S3 (endpoint) | | |
| mcp-server → authz, rems-api, VictoriaMetrics, Loki, Tempo (read paths only) | | |
| data-governance → authz, RDS Proxy, customer DB CIDRs (TGW) | 5432/3306 | DB scanning |
| llm-gateway → Bedrock endpoint, Network Firewall egress | 443 | LLMs |
| all → kube-dns 53, otel-collector 4317/4318 | | DNS, telemetry |
