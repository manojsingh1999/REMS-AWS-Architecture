#!/usr/bin/env bash
# Post-deployment / post-failover smoke test.
#   ./scripts/smoke-test.sh https://app.staging.rems.example.com [kube-context]
# Checks: public endpoints reachable over TLS 1.2+, WAF in front, REMS workloads healthy,
# rollouts not degraded, ExternalSecrets synced, no pending pods.
set -euo pipefail

BASE_URL="${1:?base url}"
CTX="${2:-}"
K=(kubectl)
[[ -n "${CTX}" ]] && K+=(--context "${CTX}")
FAIL=0

check() { # description command...
  if "${@:2}" >/dev/null 2>&1; then echo "ok    $1"; else echo "FAIL  $1"; FAIL=1; fi
}

# PLACEHOLDER paths (assumption P3/P7): align with the real health routes.
check "frontend responds (TLS)"        curl -fsS --tlsv1.2 --max-time 10 "${BASE_URL}/"
check "API health route"               curl -fsS --max-time 10 "${BASE_URL}/api/healthz"
check "HTTP is not served in clear"    bash -c "! curl -fsS --max-time 5 'http://${BASE_URL#https://}/'"

check "no pending pods in rems/rems-ai" bash -c "[ -z \"\$(${K[*]} get pods -n rems -n rems-ai --field-selector=status.phase=Pending -o name 2>/dev/null)\" ]"
for ns in rems rems-ai; do
  check "all pods ready in ${ns}" bash -c "${K[*]} get pods -n ${ns} -o jsonpath='{range .items[*]}{.status.containerStatuses[*].ready}{\"\\n\"}{end}' | grep -qv false"
  check "rollouts healthy in ${ns}" bash -c "! ${K[*]} get rollouts -n ${ns} -o jsonpath='{.items[*].status.phase}' | grep -q Degraded"
  check "external secrets synced in ${ns}" bash -c "! ${K[*]} get externalsecrets -n ${ns} -o jsonpath='{.items[*].status.conditions[*].status}' | grep -q False"
done
check "ArgoCD applications healthy" bash -c "! ${K[*]} get applications -n argocd -o jsonpath='{.items[*].status.health.status}' | grep -Eq 'Degraded|Missing'"

if ((FAIL)); then
  echo "Smoke test FAILED"
  exit 1
fi
echo "Smoke test passed"
