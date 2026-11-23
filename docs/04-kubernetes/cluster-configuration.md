# Cluster Configuration

**Status:** ✅ Kustomize base + 4 overlays (`kubernetes/`), platform add-on values (`kubernetes/platform-addons/`). Kustomize builds validated with kubeconform (172 objects across the overlays). ⚠️ Not applied to a cluster.

## Objective

Everything that makes an empty EKS cluster ready for REMS, managed declaratively and synced by ArgoCD.

## Prerequisites

EKS cluster from [EKS setup](../02-aws-infrastructure/eks-setup.md), kubectl access as PlatformAdmin, kustomize ≥ 5.

## Layout

```text
kubernetes/
├── base/                      # applied to every cluster (ArgoCD app "cluster-base", sync wave -40)
│   ├── namespaces.yaml        # rems, rems-ai (PSS restricted), observability, monitoring, argocd, ...
│   ├── priority-classes.yaml  # rems-critical 1000000, rems-high 100000, rems-batch 1000, rems-overprovision -10
│   ├── resource-governance.yaml   # ResourceQuota + LimitRange for rems / rems-ai
│   ├── network-policies.yaml  # default-deny, allow-dns, allow-telemetry
│   ├── rbac.yaml              # rems-k8s-observer (read-only for rems-api/mcp-server), rems-oncall
│   ├── storage-and-capacity.yaml  # gp3 StorageClass (KMS), overprovisioning pause pods
│   ├── karpenter.yaml         # EC2NodeClass default + NodePools general / ai / observability / workers
│   └── external-secrets.yaml  # ClusterSecretStore aws-secrets-manager
├── overlays/{dev,staging,prod,prod-dr}/kustomization.yaml   # cluster name, role, zones, AMI, replica counts, secret keys
└── platform-addons/<addon>/values[-<env>].yaml             # Helm values for each add-on
```

Platform add-ons (installed by ArgoCD from `cicd/argocd/apps/<env>/platform-addons.yaml`): karpenter, aws-load-balancer-controller, external-dns, external-secrets, metrics-server, keda, argo-rollouts, kyverno. Observability charts come from `monitoring/`.

## Steps

```bash
# Render and inspect what ArgoCD will apply
kustomize build kubernetes/overlays/prod | less
kustomize build kubernetes/overlays/prod | kubeconform -strict -summary -kubernetes-version 1.31.0 \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Normal path: ArgoCD applies it (see ../06-cicd/argocd-setup.md).
# Manual break-glass apply (only if ArgoCD is down; CRDs from the add-ons must exist):
kubectl apply --server-side -k kubernetes/overlays/prod
```

## Overlay example (`kubernetes/overlays/prod/kustomization.yaml`, excerpt)

```yaml
resources:
  - ../../base
components:
  - ../../../ai-infrastructure/llm-gateway/k8s
patches:
  - target:
      kind: EC2NodeClass
      name: default
    patch: |-
      - op: replace
        path: /spec/role
        value: rems-prod-karpenter-node
      - op: replace
        path: /spec/subnetSelectorTerms/0/tags/karpenter.sh~1discovery
        value: rems-prod
```

## Verification

```bash
kubectl get ns -L pod-security.kubernetes.io/enforce
kubectl get priorityclass | grep rems
kubectl get resourcequota,limitrange -n rems
kubectl get nodepools,ec2nodeclasses
kubectl get clustersecretstore aws-secrets-manager -o jsonpath='{.status.conditions[0].reason}'   # Valid
```

## Security considerations

* `rems` and `rems-ai` enforce the **restricted** Pod Security Standard. Kyverno adds the REMS-specific rules.
* Quotas set `services.loadbalancers: "0"` and `services.nodeports: "0"`: exposure only through Ingress/ALB.

## Troubleshooting

See [Kubernetes troubleshooting](troubleshooting.md).

## Rollback

Revert the commit. ArgoCD syncs the previous state. In prod, platform add-on applications use `prune: false` (`cicd/argocd/apps/prod/platform-addons.yaml`), so removing a manifest from Git doesn't delete it from the cluster. Delete it explicitly with `argocd app sync <app> --prune` after review.
