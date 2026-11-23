# Security Scanning (DevSecOps gates)

**Status:** ✅ Implemented in the workflows listed below. ⚠️ Not executed on GitHub yet.

| Stage | Tool | Where | Gate |
|---|---|---|---|
| Code quality / SAST | SonarQube | `app-build.yml` job `quality` (PR) | Quality gate must pass (`SONAR_TOKEN`, `SONAR_HOST_URL`) |
| Dependencies, secrets, IaC in source | Trivy fs | `app-build.yml` job `scan-source` | `HIGH,CRITICAL`, `ignore-unfixed`, exit 1 |
| Dockerfile lint | hadolint | `app-build.yml` job `lint` | Fails on errors |
| Image vulnerabilities | Trivy image | `app-build.yml` job `build` **before push** | `HIGH,CRITICAL`, `ignore-unfixed`, exit 1 |
| SBOM | anchore/sbom-action (SPDX JSON) | `build` | Attached to the release and the cosign attestation |
| Image signing | cosign keyless | `build` | Kyverno verifies at admission |
| Registry scanning | ECR enhanced scanning (Inspector) | AWS | Findings → Security Hub |
| Terraform | tflint, Checkov | `terraform.yml` | Fail on findings (skips justified in `.checkov.yaml`) |
| Kubernetes | kubeconform, Kyverno CLI, Checkov, OPA tests | `k8s-validate.yml` | Fail |
| Secrets in Git | Gitleaks | `security-scan.yml` (nightly) | Alert |
| Running images | Trivy against current prod digests | `security-scan.yml` | Alert on new CVEs |
| Runtime | GuardDuty EKS Runtime Monitoring | AWS | Security Hub → SNS |

## The seven DevSecOps pillars mapped to this repository

| Pillar | Implementation |
|---|---|
| 1. Plan / threat modelling | `security/threat-model.md` |
| 2. Code (SAST, secrets) | SonarQube, Gitleaks, Trivy fs |
| 3. Build (SCA, SBOM, signing) | Trivy image, SBOM, cosign |
| 4. Test (IaC / policy) | Checkov, tflint, Kyverno CLI, OPA, kubeconform |
| 5. Release / deploy (admission control) | Kyverno verifyImages, PSS restricted, ArgoCD projects, approvals |
| 6. Operate (runtime) | GuardDuty, Inspector, Security Hub, audit logs (`security/audit-logging.md`) |
| 7. Monitor / respond | CloudWatch + Prometheus alerts, runbooks (`runbooks/compromised-mcp-tool.md`, `runbooks/cross-tenant-access-attempt.md`) |

## Run locally

```bash
trivy fs --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln,secret,misconfig .
checkov -d terraform --config-file .checkov.yaml --framework terraform --quiet --compact
opa test security/opa -v
gitleaks detect --source . --no-banner
```

Last offline results in this repository: Checkov Terraform 1 428 passed / 0 failed. Checkov on rendered Kubernetes: 771 passed / 0 failed. OPA 12/12 passed. Gitleaks and Trivy weren't run in the build sandbox (not installed).

## Exceptions

* Checkov skips: `.checkov.yaml` and inline `#checkov:skip=<id>:<reason>` comments (for example in `terraform/cicd/github/main.tf`).
* Trivy: add `.trivyignore` entries with an expiry date and a ticket reference. Never use `exit-code: 0`.

## Rollback

A bad gate (false positive blocking all builds): fix the rule or add a time-boxed ignore through a reviewed PR. Don't bypass branch protection.
