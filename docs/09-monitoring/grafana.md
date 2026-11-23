# Grafana

**Status:** ✅ Deployed as part of kube-prometheus-stack (`monitoring/kube-prometheus-stack/values.yaml`, `grafana.ini`). Dashboards as ConfigMaps (`monitoring/grafana/dashboards/dashboards.yaml`). 🟡 OIDC settings (`client_id`, `auth_url`, `token_url`, `api_url`) and `root_url` are placeholders. ⚠️ Not deployed.

## Objective

A single SSO-protected UI over Prometheus, VictoriaMetrics, Loki and Tempo for the platform team.

## Configuration

| Item | Value |
|---|---|
| URL | `https://grafana.internal.rems.example.com` (placeholder, internal only) |
| Auth | `auth.generic_oauth` (OIDC), `disable_login_form: true`. Client secret must come from a Secret, never values (🟡 not wired yet) |
| Data sources | Prometheus, VictoriaMetrics, Loki (tenant `rems-platform`), Tempo (tenant `rems-platform`) |
| Dashboards | `rems-slo-overview`, `rems-service-red`, `rems-ai-gateway` (sidecar label `grafana_dashboard`, folder annotation `grafana_folder`) |
| Replicas / persistence | 2 replicas, no persistence (dashboards are code) |

## Steps

🟡 **Pending wiring (not in the repository yet):**

* `grafana.admin.existingSecret: grafana-admin` expects an ExternalSecret reading `rems/<env>/grafana/admin`. Neither that ExternalSecret nor the Secrets Manager secret exists in the repo or in Terraform.
* `auth.generic_oauth` has no `client_secret` source configured.

To complete it:

1. Create the Secrets Manager secrets (values entered by an operator, never committed):

   ```bash
   read -rs GF_ADMIN_PW && aws secretsmanager create-secret --name rems/prod/grafana/admin      --kms-key-id <secrets-cmk-arn> --secret-string "{\"admin-user\":\"admin\",\"admin-password\":\"$GF_ADMIN_PW\"}"; unset GF_ADMIN_PW
   read -rs GF_OIDC && aws secretsmanager create-secret --name rems/prod/grafana/oidc      --kms-key-id <secrets-cmk-arn> --secret-string "{\"client_secret\":\"$GF_OIDC\"}"; unset GF_OIDC
   ```

2. Add two `ExternalSecret` objects in the `monitoring` namespace (store `aws-secrets-manager`) that produce the Secrets `grafana-admin` and `grafana-oidc`. Then reference the OIDC one in the chart values, for example with `envValueFrom` setting `GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET` from `grafana-oidc/client_secret`.
3. Fill the `PLACEHOLDER` fields in `grafana.ini` (`client_id`, `auth_url`, `token_url`, `api_url`, `root_url`) and commit. ArgoCD syncs.

Role mapping is already configured: group `rems-platform-admins` → Admin, `rems-oncall` → Editor, everyone else → Viewer (`role_attribute_path`).

## Access

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
# http://localhost:3000  (SSO)
```

## Verification

Dashboards are listed under the REMS folder. Each data source's health check is green (Connections → Data sources).

## Rollback

Dashboards are code. Revert the ConfigMap. UI edits aren't persisted (provisioned dashboards).
