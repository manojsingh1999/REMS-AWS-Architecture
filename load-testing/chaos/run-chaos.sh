#!/usr/bin/env bash
# Orchestrates a resilience drill: starts the matching k6 scenario, injects the fault, waits, and
# collects the k6 summary. Staging by default; prod requires ALLOW_PROD=yes (game days only).
#
#   ./run-chaos.sh az <az-name>          e.g. az ap-south-1b     (FIS AZ power interruption + k6 az-failure)
#   ./run-chaos.sh aurora                (FIS Aurora failover + k6 db-bottleneck background load)
#   ./run-chaos.sh redis                 (ElastiCache test-failover per shard + k6 redis-failure)
#   ./run-chaos.sh ai-provider           (Bedrock endpoint policy deny, then gateway down + k6 ai-provider-failure)
#
# Env: ENV (staging), AWS_REGION, ACCOUNT_ID, BASE_URL, ACCESS_TOKEN (synthetic tenant), KUBE_CONTEXT
set -euo pipefail

MODE="${1:?az|aurora|redis|ai-provider}"
ENV_NAME="${ENV:-staging}"
REGION="${AWS_REGION:-ap-south-1}"
ACCOUNT_ID="${ACCOUNT_ID:?set ACCOUNT_ID}"
HERE="$(cd "$(dirname "$0")" && pwd)"
K6_DIR="${HERE}/../k6/scenarios"
OUT="${HERE}/../results/$(date -u +%Y%m%dT%H%M%SZ)-${MODE}"
mkdir -p "${OUT}"

if [[ "${ENV_NAME}" == "prod" && "${ALLOW_PROD:-no}" != "yes" ]]; then
  echo "Refusing to run chaos in prod without ALLOW_PROD=yes (game day approval)." >&2
  exit 1
fi

render() { # template -> rendered json
  sed -e "s/ACCOUNT_ID/${ACCOUNT_ID}/g" -e "s/REGION/${REGION}/g" -e "s/ENV/${ENV_NAME}/g" -e "s/AZ_NAME/${AZ_NAME:-}/g" "$1" > "$2"
}

start_k6() { # scenario
  k6 run --quiet --summary-export "${OUT}/summary.json" -e BASE_URL="${BASE_URL:?}" -e ACCESS_TOKEN="${ACCESS_TOKEN:-}" \
    "${K6_DIR}/$1.js" > "${OUT}/k6.log" 2>&1 &
  K6_PID=$!
  echo "k6 ($1) started, pid ${K6_PID}; warming up 5 minutes"
  sleep 300
}

run_fis() { # template
  render "${HERE}/$1" "${OUT}/template.json"
  tid="$(aws fis create-experiment-template --region "${REGION}" --cli-input-json "file://${OUT}/template.json" \
    --query 'experimentTemplate.id' --output text)"
  eid="$(aws fis start-experiment --region "${REGION}" --experiment-template-id "${tid}" --query 'experiment.id' --output text)"
  echo "FIS experiment ${eid} started (template ${tid})"
  echo "${eid}" > "${OUT}/experiment-id"
}

case "${MODE}" in
  az)
    AZ_NAME="${2:?az name, e.g. ap-south-1b}"
    start_k6 az-failure
    run_fis fis-az-power-interruption.json
    ;;
  aurora)
    start_k6 db-bottleneck
    run_fis fis-aurora-failover.json
    ;;
  redis)
    start_k6 redis-failure
    rg="rems-${ENV_NAME}-cache"
    for ng in $(aws elasticache describe-replication-groups --region "${REGION}" --replication-group-id "${rg}" \
        --query 'ReplicationGroups[0].NodeGroups[].NodeGroupId' --output text); do
      echo "test-failover ${rg}/${ng}"
      aws elasticache test-failover --region "${REGION}" --replication-group-id "${rg}" --node-group-id "${ng}" >/dev/null
      sleep 240 # one shard at a time (API allows a limited number of test failovers per day)
    done
    ;;
  ai-provider)
    start_k6 ai-provider-failure
    vpce="$(aws ec2 describe-vpc-endpoints --region "${REGION}" \
      --filters "Name=service-name,Values=com.amazonaws.${REGION}.bedrock-runtime" "Name=tag:Environment,Values=${ENV_NAME}" \
      --query 'VpcEndpoints[0].VpcEndpointId' --output text)"
    restore() {
      aws ec2 modify-vpc-endpoint --region "${REGION}" --vpc-endpoint-id "${vpce}" --reset-policy >/dev/null || true
      argocd app set "rems-${ENV_NAME}-llm-gateway" --sync-policy automated --self-heal >/dev/null || true
      argocd app sync "rems-${ENV_NAME}-llm-gateway" >/dev/null || true
    }
    trap restore EXIT
    echo "Phase 1 (10 min): Bedrock unavailable (VPC endpoint policy denies bedrock:*) -> expect fallback provider"
    aws ec2 modify-vpc-endpoint --region "${REGION}" --vpc-endpoint-id "${vpce}" \
      --policy-document "file://${HERE}/bedrock-endpoint-deny-policy.json" >/dev/null
    sleep 600
    echo "Phase 2 (10 min): all AI providers unavailable (gateway scaled to 0, ArgoCD auto-sync paused) -> expect degraded answers"
    argocd app set "rems-${ENV_NAME}-llm-gateway" --sync-policy none >/dev/null
    kubectl ${KUBE_CONTEXT:+--context "${KUBE_CONTEXT}"} -n rems-ai scale deployment llm-gateway --replicas=0
    sleep 600
    restore
    trap - EXIT
    ;;
  *)
    echo "unknown mode ${MODE}" >&2
    exit 2
    ;;
esac

echo "Fault injected; waiting for k6 to finish..."
wait "${K6_PID}" && status=PASS || status=FAIL
echo "${status}" > "${OUT}/result"
echo "Drill ${MODE}: ${status}. Results in ${OUT} (attach to the game-day report)."
