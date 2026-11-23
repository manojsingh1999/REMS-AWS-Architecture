#!/usr/bin/env bash
# Aurora failover operations.
#
#   ./aurora-failover.sh az-test     <cluster-id>                 # in-region writer failover (AZ drill)
#   ./aurora-failover.sh switchover  <global-id> <secondary-arn>  # planned regional switchover (RPO 0)
#   ./aurora-failover.sh failover    <global-id> <secondary-arn>  # unplanned regional failover (data loss = lag)
#
# Unplanned failover is the DR path for a primary-region outage (runbooks/dr-regional-failover.md).
set -euo pipefail

ACTION="${1:?az-test|switchover|failover}"
REGION="${AWS_REGION:-ap-south-1}"

case "${ACTION}" in
  az-test)
    CLUSTER="${2:?cluster id}"
    before="$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER}" \
      --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' --output text)"
    echo "Current writer: ${before}. Forcing failover..."
    start=$(date +%s)
    aws rds failover-db-cluster --region "${REGION}" --db-cluster-identifier "${CLUSTER}"
    while true; do
      after="$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${CLUSTER}" \
        --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' --output text)"
      [[ "${after}" != "${before}" && -n "${after}" ]] && break
      sleep 2
    done
    echo "New writer: ${after} after $(( $(date +%s) - start ))s (target < 60s; RDS Proxy masks most of it)"
    ;;
  switchover|failover)
    GLOBAL="${2:?global cluster id}"
    TARGET_ARN="${3:?secondary cluster ARN}"
    lag="$(aws cloudwatch get-metric-statistics --region "${REGION}" --namespace AWS/RDS \
      --metric-name AuroraGlobalDBReplicationLag --dimensions Name=DBClusterIdentifier,Value="${GLOBAL%-global}" \
      --start-time "$(date -u -d '-5 min' +%FT%TZ)" --end-time "$(date -u +%FT%TZ)" --period 60 \
      --statistics Maximum --query 'max(Datapoints[].Maximum)' --output text 2>/dev/null || echo unknown)"
    echo "Current global replication lag (ms): ${lag}"
    if [[ "${ACTION}" == "switchover" ]]; then
      aws rds switchover-global-cluster --region "${REGION}" \
        --global-cluster-identifier "${GLOBAL}" --target-db-cluster-identifier "${TARGET_ARN}"
    else
      read -r -p "Unplanned failover may lose up to ${lag} ms of writes. Type FAILOVER to continue: " confirm
      [[ "${confirm}" == "FAILOVER" ]] || { echo "aborted"; exit 1; }
      aws rds failover-global-cluster --region "${REGION}" \
        --global-cluster-identifier "${GLOBAL}" --target-db-cluster-identifier "${TARGET_ARN}" --allow-data-loss
    fi
    echo "Requested. Track with: aws rds describe-global-clusters --global-cluster-identifier ${GLOBAL}"
    ;;
  *)
    echo "unknown action ${ACTION}" >&2
    exit 2
    ;;
esac
