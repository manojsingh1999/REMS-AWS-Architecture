# Helm Installation

**Status:** ✅ Charts target Helm 3 (`apiVersion: v2`). The ArgoCD bootstrap pins chart `argo/argo-cd` **7.7.10** (`scripts/bootstrap-cluster.sh`). ⚠️ The validation in this repository used an offline Go renderer (`scripts/helm-render-check/main.go`), because the Helm binary couldn't be downloaded in the build sandbox. Run `helm lint` yourself (step 3).

## Objective

Install Helm 3.16 locally, so you can lint and render the charts the same way ArgoCD does.

## Steps

1. Install Helm:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o get-helm-3.sh
   less get-helm-3.sh                               # review before running
   DESIRED_VERSION=v3.16.3 bash get-helm-3.sh
   helm version
   ```

2. Add the add-on repositories used by `cicd/argocd/apps/<env>/platform-addons.yaml`:

   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm repo update
   ```

   For the other repositories (Karpenter OCI, eks-charts, external-secrets, kedacore, kyverno, prometheus-community, grafana, victoria-metrics, open-telemetry), use the `repoURL` and `targetRevision` values from `platform-addons.yaml`, so your local versions match the cluster.

3. Build the library dependency and lint a chart:

   ```bash
   cd helm/charts/rems-api
   helm dependency build                         # vendors rems-common from file://../rems-common
   helm lint --strict . -f values-prod.yaml -f ../../environments/prod/global.yaml
   ```

## Verification

```bash
./scripts/validate.sh helm      # uses helm when installed, otherwise the bundled renderer + kubeconform
```

Expected: `PASS helm lint <chart>/<env>` for 7 charts × 3 environments, and `PASS render 7 charts x 4 envs + kubeconform`.

## Security considerations

Pin chart versions (never `latest`). Verify the provenance of third-party charts when available (`helm verify` / OCI signatures).

## Troubleshooting

| Symptom | Fix |
|---|---|
| `found in Chart.yaml, but missing in charts/ directory: rems-common` | Run `helm dependency build` |
| `chart requires kubeVersion: >=1.29.0-0` | Pass `--kube-version 1.31.0` to `helm template` |

## Rollback

Helm on laptops is used for rendering only. Releases in clusters are owned by ArgoCD (except the one-time ArgoCD bootstrap install).
