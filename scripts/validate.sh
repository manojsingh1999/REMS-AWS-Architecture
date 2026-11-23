#!/usr/bin/env bash
# Runs every offline validation in the repository. Uses the real tools when present
# (terraform, helm, tflint, kyverno) and the bundled fallbacks otherwise.
#   ./scripts/validate.sh            # all
#   ./scripts/validate.sh terraform  # one area: terraform|helm|k8s|policy|cicd|loadtest|sql|docs|scripts
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}" || exit 1
AREA="${1:-all}"
FAILED=()
CRD='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

have() { command -v "$1" >/dev/null 2>&1; }
step() { printf '\n\033[1m== %s\033[0m\n' "$1"; }
run() { # name cmd...
  local name="$1"; shift
  if "$@"; then echo "PASS  ${name}"; else echo "FAIL  ${name}"; FAILED+=("${name}"); fi
}
want() { [[ "${AREA}" == "all" || "${AREA}" == "$1" ]]; }

if want terraform; then
  step "Terraform"
  if have terraform; then
    run "terraform fmt" terraform fmt -check -recursive terraform
    for d in $(find terraform -name '*.tf' -not -path '*/.terraform/*' -exec dirname {} \; | sort -u); do
      run "terraform validate ${d}" bash -c "terraform -chdir='${d}' init -backend=false -input=false >/dev/null && terraform -chdir='${d}' validate -no-color >/dev/null"
    done
  else
    echo "terraform not installed - using offline checker"
  fi
  run "tf_static_check (HCL parse + module wiring)" python3 scripts/tf_static_check.py terraform
  have tflint && run "tflint" tflint --recursive --config "${ROOT}/.tflint.hcl" --chdir terraform
  have checkov && run "checkov terraform" checkov -d terraform --config-file .checkov.yaml --framework terraform --quiet --compact
fi

if want helm; then
  step "Helm charts"
  if have helm; then
    for c in helm/charts/*/; do
      n="$(basename "$c")"; [[ "$n" == "rems-common" ]] && continue
      helm dependency build "$c" >/dev/null
      for e in dev staging prod; do
        run "helm lint ${n}/${e}" helm lint --strict "$c" -f "$c/values-${e}.yaml" -f "helm/environments/${e}/global.yaml"
      done
    done
  fi
  have go && run "render 7 charts x 4 envs + kubeconform" python3 scripts/helm_render_check.py
fi

if want k8s; then
  step "Kubernetes manifests"
  for o in kubernetes/overlays/*/; do
    if have kustomize; then
      run "kustomize ${o}" bash -c "kustomize build '${o}' | kubeconform -strict -summary -kubernetes-version 1.31.0 -schema-location default -schema-location '${CRD}'"
    fi
  done
  run "kubeconform cicd/security/monitoring" kubeconform -strict -summary -kubernetes-version 1.31.0 -schema-location default -schema-location "${CRD}" \
    cicd/argocd/projects cicd/argocd/bootstrap cicd/argocd/apps cicd/argo-rollouts security/kyverno monitoring/rules monitoring/grafana load-testing/k6-operator load-testing/chaos/fis-k8s-rbac.yaml
  run "yamllint" yamllint -c .yamllint.yaml .
fi

if want policy; then
  step "Policies and rules"
  have opa && run "opa test" opa test security/opa
  if have promtool; then
    tmp="$(mktemp -d)"
    for f in monitoring/rules/*.yaml; do python3 -c "import yaml,sys; yaml.safe_dump(yaml.safe_load(open('$f'))['spec'], open('${tmp}/$(basename "$f")','w'))"; done
    run "promtool check rules" promtool check rules "${tmp}"/*.yaml
  fi
  for f in security/iam/*.json security/iam/scp/*.json load-testing/chaos/*.json; do
    run "json ${f}" python3 -c "import json; json.load(open('${f}'))"
  done
fi

if want cicd; then
  step "GitHub Actions"
  have actionlint && run "actionlint" actionlint .github/workflows/*.yml cicd/microconfig-repo-template/.github/workflows/*.yml
fi

if want loadtest; then
  step "k6"
  if have k6; then
    for s in load-testing/k6/scenarios/*.js; do run "k6 inspect ${s}" bash -c "k6 inspect '${s}' >/dev/null"; done
  fi
fi

if want sql; then
  step "SQL"
  python3 -c "import pglast" 2>/dev/null && run "pglast parse database/sql" python3 -c "
import glob, pglast
for f in sorted(glob.glob('database/sql/*.sql')):
    pglast.parse_sql(open(f).read())"
fi

if want docs; then
  step "Mermaid diagrams"
  if have node && have npm; then
    (cd scripts/mermaid-check && npm install --silent --no-audit --no-fund >/dev/null 2>&1)
    run "mermaid parse (all diagrams)" node scripts/mermaid-check/check.mjs "${ROOT}"
  fi
fi

if want scripts; then
  step "Shell scripts"
  have shellcheck && run "shellcheck" shellcheck -S warning scripts/*.sh database/scripts/*.sh load-testing/chaos/*.sh
fi

echo
if ((${#FAILED[@]})); then
  echo "FAILED: ${FAILED[*]}"
  exit 1
fi
echo "All selected validations passed."
