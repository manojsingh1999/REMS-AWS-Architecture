# Network Policies

**Status:** ✅ Baseline (`kubernetes/base/network-policies.yaml`) + per-chart policies (`rems-common.networkPolicy`). Enforced by the VPC CNI network policy agent (`enableNetworkPolicy = "true"` in `terraform/modules/eks/main.tf`). ⚠️ Not tested on a live cluster.

## Objective

Default-deny for `rems` and `rems-ai`, then explicit allow-lists per service. A compromised pod can only reach what its service legitimately needs.

## Baseline

| Policy | Namespaces | Effect |
|---|---|---|
| `default-deny-all` | rems, rems-ai | Deny all ingress and egress |
| `allow-dns` | rems, rems-ai | Egress UDP/TCP 53 to `kube-dns` in kube-system |
| `allow-telemetry` | rems, rems-ai | Egress to the OTel collector, ingress from Prometheus scraping |

## Per-service policy (real rendered excerpt, rems-api prod)

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: rems-api
  namespace: rems
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: rems-api
  policyTypes: [Ingress, Egress]
  ingress:
    - from:
        - ipBlock:
            cidr: 10.30.0.0/16          # ALB target-type ip
      ports:
        - { protocol: TCP, port: 8000 }
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: rems-ai
          podSelector:
            matchLabels:
              app.kubernetes.io/name: chat-engine
      ports:
        - { protocol: TCP, port: 8000 }
  egress:
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: rems
          podSelector:
            matchLabels:
              app.kubernetes.io/name: authorization-service
      ports:
        - { protocol: TCP, port: 8000 }
    - to:
        - ipBlock:
            cidr: 10.30.3.0/24          # private-data subnet, AZ a (also .4 and .5)
      ports:
        - { protocol: TCP, port: 5432 }
        - { protocol: TCP, port: 6379 }
```

The values that drive it, in each chart's `values.yaml`:

```yaml
networkPolicy:
  enabled: true
  ingressFrom: [...]   # namespace + app name pairs
  egressTo: [...]      # namespace + app name + ports
  egressCIDRs: [...]   # data subnets come from global.dataSubnetCIDRs
```

## Steps to allow a new path

1. Add the peer to `networkPolicy.egressTo` of the caller **and** to `networkPolicy.ingressFrom` of the callee.
2. Render and validate: `python3 scripts/helm_render_check.py`.
3. Merge. ArgoCD applies.

## Verification

```bash
kubectl get networkpolicy -n rems
# Negative test: a random pod must not reach rems-api
kubectl run np-test -n rems --rm -it --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- \
  wget -qO- -T 3 http://rems-api.rems.svc/readyz ; echo "exit=$?"
```

Expected: timeout or non-zero exit.

## Troubleshooting

| Symptom | Fix |
|---|---|
| Service can't reach Aurora | `global.dataSubnetCIDRs` doesn't match the real data subnets |
| Calls to AWS APIs time out | Egress 443 to the VPC CIDR (interface endpoints) is missing |
| Policies seem ignored | The network policy agent isn't running: `kubectl -n kube-system get ds aws-node -o yaml \| grep -i network-policy` |
| Webhooks fail after enabling policies | Admission controllers in other namespaces aren't covered. Only `rems` and `rems-ai` are default-deny |

## Rollback

Fast unblock in an incident (temporary, recorded in the incident log):

```bash
kubectl apply -n rems -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: incident-allow-all-egress-temp }
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress: [{}]
EOF
```

Remove it as soon as the real rule is merged. ArgoCD reports it as an out-of-band resource.
