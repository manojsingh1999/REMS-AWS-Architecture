#!/usr/bin/env bash
# Point-in-time restore of an Aurora cluster into a NEW cluster (never in place).
# Used for: logical corruption / bad migration (restore to just before), monthly restore drills.
#
#   ./restore-pitr.sh <source-cluster-id> <restore-time-ISO8601|latest> [target-suffix]
#   ./restore-pitr.sh rems-prod-core 2026-11-21T09:45:00Z
#
# After validation, either repoint the RDS Proxy target to the restored cluster (full restore) or copy the
# affected rows back (partial restore). Both paths are described in runbooks/postgres-restore.md.
set -euo pipefail

SOURCE="${1:?source cluster id}"
WHEN="${2:?restore time (ISO8601) or 'latest'}"
SUFFIX="${3:-restore-$(date -u +%Y%m%d%H%M)}"
REGION="${AWS_REGION:-ap-south-1}"
TARGET="${SOURCE}-${SUFFIX}"

desc() { aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${SOURCE}" --query "DBClusters[0].$1" --output text; }

SUBNET_GROUP="$(desc DBSubnetGroup)"
SG_IDS="$(desc 'VpcSecurityGroups[].VpcSecurityGroupId')"
PARAM_GROUP="$(desc DBClusterParameterGroup)"
KMS_KEY="$(desc KmsKeyId)"
INSTANCE_CLASS="$(aws rds describe-db-instances --region "${REGION}" \
  --filters "Name=db-cluster-id,Values=${SOURCE}" --query 'DBInstances[0].DBInstanceClass' --output text)"

echo "Restoring ${SOURCE} @ ${WHEN} -> ${TARGET} (${INSTANCE_CLASS})"

time_args=(--use-latest-restorable-time)
if [[ "${WHEN}" != "latest" ]]; then
  time_args=(--restore-to-time "${WHEN}")
fi

# shellcheck disable=SC2086 # SG_IDS is a whitespace-separated list by design
aws rds restore-db-cluster-to-point-in-time --region "${REGION}" \
  --source-db-cluster-identifier "${SOURCE}" \
  --db-cluster-identifier "${TARGET}" \
  "${time_args[@]}" \
  --db-subnet-group-name "${SUBNET_GROUP}" \
  --vpc-security-group-ids ${SG_IDS} \
  --db-cluster-parameter-group-name "${PARAM_GROUP}" \
  --kms-key-id "${KMS_KEY}" \
  --enable-iam-database-authentication \
  --deletion-protection \
  --tags Key=Purpose,Value=pitr-restore Key=Source,Value="${SOURCE}"

aws rds create-db-instance --region "${REGION}" \
  --db-instance-identifier "${TARGET}-writer" \
  --db-cluster-identifier "${TARGET}" \
  --engine aurora-postgresql \
  --db-instance-class "${INSTANCE_CLASS}" \
  --no-publicly-accessible

echo "Waiting for ${TARGET}-writer to become available (typically 10-25 min)..."
aws rds wait db-instance-available --region "${REGION}" --db-instance-identifier "${TARGET}-writer"

ENDPOINT="$(aws rds describe-db-clusters --region "${REGION}" --db-cluster-identifier "${TARGET}" --query 'DBClusters[0].Endpoint' --output text)"
echo "Restored cluster ready: ${ENDPOINT}"
echo "Next: run validation queries (row counts / checksums per tenant) - see runbooks/postgres-restore.md"
