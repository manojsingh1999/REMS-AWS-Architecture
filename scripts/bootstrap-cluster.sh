#!/usr/bin/env bash
# One-time GitOps bootstrap of an EKS cluster created by terraform/environments/<env>.
# After this, ArgoCD manages everything (add-ons, policies, REMS services) from Git.
#
#   ./scripts/bootstrap-cluster.sh <env>          # dev | staging | prod | prod-dr
#
# Prerequisites: terraform apply done, kubectl access through an EKS access entry (PlatformAdmin),
# helm 3.16+, AWS CLI v2. Run from a host that can reach the private API endpoint (VPN / bastion).
set -euo pipefail

ENV_NAME="${1:?usage: $0 <dev|staging|prod|prod-dr>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TF_DIR="${ROOT}/terraform/environments/${ENV_NAME}"
REGION="ap-south-1"
[[ "${ENV_NAME}" == "prod-dr" ]] && REGION="ap-southeast-1"

CLUSTER="$(terraform -chdir="${TF_DIR}" output -raw cluster_name)"
echo "Bootstrapping ${CLUSTER} (${REGION})"

aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}" --alias "${CLUSTER}"
kubectl config use-context "${CLUSTER}"

# Fail fast if the values files still contain placeholders that must come from terraform outputs.
if grep -rn "PLACEHOLDER-${ENV_NAME}-vpc-id\|PLACEHOLDER-cluster-name" "${ROOT}/kubernetes/platform-addons"/*/"values-${ENV_NAME}.yaml" 2>/dev/null; then
  echo "Replace the placeholders above with values from: terraform -chdir=${TF_DIR} output" >&2
  exit 1
fi

# 1. Namespace + ArgoCD (HA) - the only Helm release installed by hand.
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null
helm upgrade --install argocd argo/argo-cd --namespace argocd --version 7.7.10 \
  -f "${ROOT}/cicd/argocd/install/values.yaml" --wait --timeout 10m

# 2. Projects + root application (app-of-apps). From here on, Git is the source of truth.
kubectl apply -n argocd -f "${ROOT}/cicd/argocd/projects/projects.yaml"
kubectl apply -n argocd -f "${ROOT}/cicd/argocd/bootstrap/root-${ENV_NAME}.yaml"

echo "Waiting for ArgoCD to sync the platform layer (sync waves -40 .. 0)..."
for _ in $(seq 1 60); do
  healthy="$(kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.status.health.status}{"\n"}{end}' | grep -c Healthy || true)"
  total="$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)"
  echo "  ${healthy}/${total} applications healthy"
  [[ "${total}" -gt 0 && "${healthy}" -eq "${total}" ]] && break
  sleep 30
done

kubectl get applications -n argocd
echo "Next: database/scripts/bootstrap-roles.sh ${ENV_NAME%-dr} core|rag (primary site only), then scripts/smoke-test.sh"
