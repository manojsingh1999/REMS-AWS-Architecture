# Operational Checklist

Use these before declaring an environment production-ready. Unchecked items are the current state of this repository. Nothing is deployed yet.

## Before the first apply

- [ ] All `PLACEHOLDER`, `example.com`, `your-github-org` and placeholder account IDs replaced (`grep -rn PLACEHOLDER .`)
- [ ] `platform_repo` set to the real repository name in `terraform/global/bootstrap` and `terraform/cicd/argocd`, and the ArgoCD repo URLs in `cicd/argocd/**` updated
- [ ] Identity Center permission sets created, ARNs in tfvars
- [ ] Bedrock model access and quotas confirmed in ap-south-1 and ap-southeast-1
- [ ] EC2 vCPU / EIP / VPC endpoint quotas checked for 3 NATs + Karpenter peak
- [ ] `./scripts/validate.sh` clean with real `terraform`, `helm` and `kyverno` binaries
- [ ] Budget owner approved the [cost estimate](../13-cost-optimization/aws-cost-estimation.md)

## Platform readiness

- [ ] `terraform plan` shows no drift in every environment
- [ ] ArgoCD: all applications Synced/Healthy. SSO login works (admin disabled)
- [ ] Kyverno policies Enforce with no unexpected PolicyReport failures
- [ ] ExternalSecrets all `Ready`
- [ ] Alertmanager → SNS verified with a test alert. E-mail subscriptions confirmed
- [ ] CloudWatch out-of-band alarms in `OK`
- [ ] Grafana dashboards show data for all 7 services
- [ ] Service placeholders resolved (ports, probes, metrics path, env vars: P1–P6)

## Resilience evidence

- [ ] k6 normal / 5× / 10× results stored in `load-testing/results/`
- [ ] AZ failure drill passed in staging
- [ ] Aurora failover drill passed
- [ ] Redis failover drill passed
- [ ] AI provider outage drill passed
- [ ] PITR restore drill completed, with time recorded
- [ ] DR switchover drill completed, with RTO/RPO measured
- [ ] Route 53 failover records implemented (currently 📋)

## Security evidence

- [ ] Security Hub critical/high findings triaged
- [ ] RLS cross-tenant test passing in CI of the service repos
- [ ] OPA tests passing (`opa test security/opa`)
- [ ] Gitleaks / Trivy nightly clean
- [ ] Access review done

## Operations

- [ ] On-call rota and paging configured
- [ ] Runbooks walked through once by the on-call team
- [ ] Status page and comms templates ready
