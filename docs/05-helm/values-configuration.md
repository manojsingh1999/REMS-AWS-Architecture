# Values Configuration

**Status:** ✅ Values documented inline in every `values.yaml`. 🟡 App-specific values are placeholders (see the table at the end).

## Layering (same order as ArgoCD)

| Order | File | Owner | Contents |
|---|---|---|---|
| 1 | `helm/charts/<svc>/values.yaml` (platform repo) | Platform team | Defaults |
| 2 | `apps/<svc>/values-<env>.yaml` (**rems-microconfig** repo) | CI bot (dev), promote PRs (staging/prod) | Image tag/digest, replicas, secret keys, egress CIDRs, host |
| 3 | `env/<env>/global.yaml` (**rems-microconfig**) | Platform team | Region, VPC CIDR, data subnet CIDRs, ACM/WAF ARNs, ALB log bucket |

prod-dr uses `values-prod.yaml` + `values-prod-dr.yaml` + `env/prod-dr/global.yaml` (`terraform/cicd/argocd/apps.tf`, `local.value_files`).

The copies under `helm/charts/<svc>/values-<env>.yaml` and `helm/environments/<env>/global.yaml` in **this** repository are the seed. `terraform/cicd/github` writes them into `rems-microconfig` once (`github_repository_file.seed`). After that, the microconfig repo is authoritative.

## Top-level keys (`helm/charts/rems-api/values.yaml`)

`global`, `nameOverride`, `component`, `image`, `containerPort`, `command`, `args`, `config`, `extraEnv`, `replicaCount`, `rollout`, `serviceAccount`, `priorityClassName`, `nodePool`, `topologySpread`, `terminationGracePeriodSeconds`, `preStopSleepSeconds`, `tmpSizeLimit`, `podLabels`, `podAnnotations`, `podSecurityContext`, `securityContext`, `extraVolumes`, `extraVolumeMounts`, `probes`, `resources`, `autoscaling`, `pdb`, `service`, `ingress`, `networkPolicy`, `externalSecrets`, `otel`, `serviceMonitor`, `worker`.

## Real per-environment file (`helm/charts/rems-api/values-prod.yaml`)

```yaml
image:
  tag: sha-0000000
rollout:
  enabled: true
autoscaling:
  minReplicas: 6
  maxReplicas: 40
otel:
  samplerRatio: '0.1'
externalSecrets:
- name: rems-api-db
  remoteKey: rems/prod/aurora/rems-prod-core/rems-api
  refreshInterval: 1h
  envFrom: false
- name: rems-api-redis
  remoteKey: rems/prod/redis/rems-prod-cache
  refreshInterval: 1h
  envFrom: false
networkPolicy:
  egressCIDRs:
  - cidr: 10.30.3.0/24
    ports: [5432, 6379]
  - cidr: 10.30.4.0/24
    ports: [5432, 6379]
  - cidr: 10.30.5.0/24
    ports: [5432, 6379]
ingress:
  host: app.rems.example.com
```

`image.tag: sha-0000000` is a seed placeholder. CI writes the real date tag (`YYYY.MM.DD-<run>`) and digest into the microconfig repo.

## Placeholders to resolve before go-live

| Value | Current | Source of truth | Assumption ID (`documentation/02-assumptions.md`) |
|---|---|---|---|
| `containerPort` | 8000 (8080 frontend) | Service Dockerfile `EXPOSE` / server command | P1/P2 |
| `probes.*.path` | `/healthz`, `/readyz` | Service code | P3 |
| `serviceMonitor` path | `/metrics` | Service code | P4 |
| `config`, `extraEnv` | empty | Service settings class | P6 |
| `worker.command` | `PLACEHOLDER-worker-entrypoint` (worker disabled) | Service repo | P5 |
| `ingress.host` | `app.<env>.rems.example.com` | DNS plan | P9 |
| Path prefixes `/api`, `/chat`, `/mcp` | as set | Frontend routing / API design | not yet listed (add to the assumptions file) |
| `global.ingress.certificateArn`, `wafAclArn` | `PLACEHOLDER` | `terraform output -json edge` | – |
| `image.repository` account | `444444444444` | Shared Services account ID | P8/P9 |

Find them all:

```bash
grep -rn 'PLACEHOLDER\|example.com\|sha-0000000' helm/ | wc -l
```

## Verification

```bash
python3 scripts/helm_render_check.py                    # 28 renders + kubeconform
helm template rems-api helm/charts/rems-api -n rems \
  -f helm/charts/rems-api/values-prod.yaml -f helm/environments/prod/global.yaml | less
```

## Security considerations

* Secrets are **never** values. Only Secrets Manager key *names* (`remoteKey`) appear, and ESO fetches the content.
* `envFrom: false` mounts secret keys as files instead of environment variables.
