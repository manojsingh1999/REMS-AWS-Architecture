# Container Security

**Status:** ✅ Pod hardening in `rems-common`, Kyverno policies (`security/kyverno/policies.yaml`, all `Enforce`), supply-chain controls in CI. ⚠️ The Kyverno CLI run against rendered charts is wired into `k8s-validate.yml`, but couldn't be executed in the build sandbox.

## Kyverno policies

| ClusterPolicy | Enforces |
|---|---|
| `rems-verify-image-signatures` | cosign signature from the CI identity on `rems/*` images |
| `rems-restrict-registries` | Images only from the approved ECR registry |
| `rems-workload-hardening` | Non-root, no privilege escalation, drop ALL capabilities, read-only root FS, resources set, no host namespaces |
| `rems-deny-exec-into-ai-pods` | No `kubectl exec` / attach into `rems-ai` pods (break-glass excepted) |
| `rems-mcp-readonly-guard` | mcp-server can't gain write RBAC or mutate resources |
| `rems-require-service-account` | No `default` service account |

## Pod-level defaults (rendered from `rems-common`)

```yaml
securityContext:            # pod
  runAsNonRoot: true
  runAsUser: 10001
  runAsGroup: 10001
  fsGroup: 10001
  seccompProfile:
    type: RuntimeDefault
containers:
  - securityContext:
      allowPrivilegeEscalation: false
      privileged: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: [ALL]
enableServiceLinks: false
```

## Steps: test a policy locally

```bash
python3 scripts/helm_render_check.py --out /tmp/rendered
kyverno apply security/kyverno/policies.yaml --resource /tmp/rendered/prod/rems-api.yaml
```

The signature policy needs network access to the registry. Offline, run the other policies by excluding it.

## Verification in a cluster

```bash
kubectl get clusterpolicies
kubectl get policyreports -A
# Negative test: must be denied
kubectl run bad -n rems --image=docker.io/library/nginx:latest --dry-run=server
```

## Security considerations

* Runtime threat detection: GuardDuty EKS Runtime Monitoring (`security-baseline`).
* Image CVEs after release: nightly `security-scan.yml` plus ECR enhanced scanning.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Kyverno webhook timeouts block all deploys | Kyverno pods unhealthy. Scale or fix them. `failurePolicy` decides fail-open vs fail-closed. Check the policy before an incident |
| Signature verification fails for a valid image | The cosign identity / issuer in the policy doesn't match the workflow ref (repo rename!) |

## Rollback

Set a single policy to `Audit` through a reviewed PR (`validationFailureAction: Audit`). Never delete Kyverno during an incident without a security sign-off.
