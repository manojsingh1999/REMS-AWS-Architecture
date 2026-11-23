# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Dates are UTC.

## [1.1.0] · 2026-11-23

### Added

- `docs/06-cicd/git-branching-strategy.md`: trunk-based branching, naming, PR and merge rules, required checks, branch protection commands, hotfix flow, versioning.
- Links to it from `README.md`, `docs/README.md` and the deployment workflow page.

## [1.0.0] · 2026-11-23

### Added: infrastructure implementation

- `terraform/`: landing zone, account bootstrap, shared services (ECR), 17 modules, 4 environments (dev, staging, prod, prod-dr), CI/CD stacks (`terraform/cicd/github`, `terraform/cicd/argocd`).
- `kubernetes/`: base manifests, 4 overlays, platform add-on values.
- `helm/`: `rems-common` library chart and 7 service charts with per-environment values.
- `cicd/`: ArgoCD install/projects/bootstrap/apps, Argo Rollouts analysis templates, `rems-microconfig` repository template.
- `.github/`: workflows `app-build`, `terraform`, `k8s-validate`, `security-scan`, `load-test`. CODEOWNERS, Dependabot.
- `security/`: SCPs, permission boundaries, Kyverno policies, OPA policies + tests, threat model, audit logging, secrets rotation.
- `monitoring/`: kube-prometheus-stack, Loki, Tempo, OTel Collector, VictoriaMetrics values. Rules, dashboards, SLOs.
- `database/`: SQL (roles, grants, RLS, pgvector) and operational scripts. Redis design.
- `ai-infrastructure/`: LLM gateway, RAG and MCP design and configuration.
- `load-testing/`: k6 scenarios, k6-operator TestRun, AWS FIS templates, chaos driver.
- `scripts/`: validation, bootstrap, smoke test, cost model, offline Terraform/Helm/Mermaid checkers.
- `architecture/`, `documentation/`, `runbooks/`: design documents, requirements traceability, assumptions, deployment guide, capacity and cost models, roadmap, 12 runbooks.
- Lint/scan configuration: `.checkov.yaml`, `.tflint.hcl`, `.yamllint.yaml`, `.gitignore`.

### Added: documentation

- `docs/`: step-by-step implementation guide (14 sections, 82 topic pages + index, status and changelog (85 files)), including 10 architecture views as Mermaid diagrams.
- `docs/IMPLEMENTATION-STATUS.md`: completed / in progress / pending / blocked / not-yet-validated items with repository paths.
- `docs/CHANGELOG.md`: this file.

### Known gaps

See [IMPLEMENTATION-STATUS.md → Pending](IMPLEMENTATION-STATUS.md#-pending-gaps-and-follow-ups-found-while-documenting).
