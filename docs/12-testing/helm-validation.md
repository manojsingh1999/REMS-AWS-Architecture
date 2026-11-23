# Helm and Kubernetes Validation

**Status:** ✅ All charts and manifests validated offline. ⚠️ The Kyverno CLI against the rendered output and `helm lint` with the real Helm binary run in CI (`k8s-validate.yml`) but weren't run in the build environment.

| Check | Command | Last result |
|---|---|---|
| Render 7 charts × 4 envs + kubeconform strict (k8s 1.31 + CRD catalog) | `python3 scripts/helm_render_check.py` | ✅ 28/28 |
| helm lint --strict (7 × 3 envs) | `./scripts/validate.sh helm` (with Helm installed) | CI only |
| Kustomize overlays + kubeconform | `kustomize build kubernetes/overlays/<env> \| kubeconform -strict ...` | ✅ 4 overlays, 172 objects |
| ArgoCD / Rollouts / Kyverno / rules / k6-operator manifests | `kubeconform` (see `validate.sh k8s`) | ✅ |
| yamllint | `yamllint -c .yamllint.yaml .` | ✅ |
| Checkov on rendered manifests | `checkov -d /tmp/rendered --framework kubernetes` | ✅ 771 passed, 0 failed |
| OPA unit tests | `opa test security/opa -v` | ✅ 12/12 |
| Prometheus rules | `promtool check rules` (spec extracted) | ✅ 114 rules |
| Kyverno policies vs rendered charts | `kyverno apply security/kyverno/policies.yaml --resource <rendered>` | CI only |

## Run

```bash
./scripts/validate.sh helm
./scripts/validate.sh k8s
./scripts/validate.sh policy
python3 scripts/helm_render_check.py --out /tmp/rendered    # keep the rendered YAML for inspection
```

## How the offline renderer works

`scripts/helm-render-check/main.go` renders charts with Go `text/template` + Sprig (the same engine Helm uses), merging `values.yaml`, `values-<env>.yaml` and `helm/environments/<env>/global.yaml` in ArgoCD's order. It exists because the Helm binary couldn't be downloaded in the build environment. With Helm available, prefer `helm template` (same output for these charts, but Helm is the reference).
