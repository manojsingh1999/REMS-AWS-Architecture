# Ingress (AWS Load Balancer Controller)

**Status:** ✅ `rems-common.ingress` template, controller values in `kubernetes/platform-addons/aws-load-balancer-controller/`. 🟡 Hostname `app.rems.example.com` (assumption P9) and the path prefixes are placeholders. The certificate and WAF ARNs in `helm/environments/<env>/global.yaml` are placeholders until Terraform runs.

## Objective

One shared internet-facing ALB (`rems-public` group) for frontend, API and chat, plus one internal ALB (`rems-internal`) for MCP. TLS 1.3/1.2, WAF, access logs and weighted target groups for canaries.

## Prerequisites

* AWS Load Balancer Controller running (ArgoCD wave -20) with its Pod Identity role (`module "irsa_alb_controller"`).
* `vpcId` set in `kubernetes/platform-addons/aws-load-balancer-controller/values-<env>.yaml`.
* ACM certificate + WAF ACL from Terraform (`terraform output -json edge`).

## Real rendered Ingress (rems-api, prod)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rems-api
  namespace: rems
  annotations:
    alb.ingress.kubernetes.io/group.name: rems-public
    alb.ingress.kubernetes.io/group.order: "10"
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS13-1-2-2021-06
    alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:ap-south-1:333333333333:certificate/PLACEHOLDER"
    alb.ingress.kubernetes.io/healthcheck-path: /readyz
    alb.ingress.kubernetes.io/target-group-attributes: deregistration_delay.timeout_seconds=30,load_balancing.algorithm.type=least_outstanding_requests
    alb.ingress.kubernetes.io/load-balancer-attributes: idle_timeout.timeout_seconds=60,routing.http.drop_invalid_header_fields.enabled=true,access_logs.s3.enabled=true,access_logs.s3.bucket=rems-prod-alb-logs-333333333333,access_logs.s3.prefix=alb,deletion_protection.enabled=true
    alb.ingress.kubernetes.io/wafv2-acl-arn: "arn:aws:wafv2:ap-south-1:333333333333:regional/webacl/rems-prod/PLACEHOLDER"
spec:
  ingressClassName: alb
  rules:
    - host: "app.rems.example.com"
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: rems-api
                port:
                  name: use-annotation     # Argo Rollouts manages the weighted action
```

## Routing table

| Path | Service | ALB group | Idle timeout |
|---|---|---|---|
| `/` | rems-frontend | rems-public | 60 s |
| `/api` | rems-api | rems-public | 60 s |
| `/chat` | chat-engine | rems-public | 300 s (streaming) |
| `/mcp` | mcp-server | rems-internal | 60 s |

## Steps

1. Fill `helm/environments/<env>/global.yaml` from `terraform output -json edge` and `terraform output -json buckets`.
2. Set the real host in each exposed chart's `values-<env>.yaml` (`ingress.host`. For example, `helm/charts/rems-api/values-prod.yaml` currently has `app.rems.example.com`).
3. Commit. ArgoCD syncs, and the controller creates or updates the ALB.
4. DNS: external-dns (`kubernetes/platform-addons/external-dns/values-<env>.yaml`) creates the Route 53 record for the host.

## Verification

```bash
kubectl get ingress -A
kubectl describe ingress rems-api -n rems | tail -20      # events: SuccessfullyReconciled
aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,'rems')].[LoadBalancerName,Scheme,State.Code]"
aws wafv2 get-web-acl-for-resource --resource-arn <alb-arn>
curl -sI https://<host>/ | head -1
```

## Security considerations

* HTTPS only (no :80 listener). TLS policy `ELBSecurityPolicy-TLS13-1-2-2021-06`. Invalid headers dropped.
* WAF on the public group. The MCP endpoint is internal only (VPN/TGW).
* ALB access logs go to the `rems-<env>-alb-logs-<acct>` bucket.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FailedDeployModel ... certificate not found` | Certificate ARN placeholder not replaced, or a region mismatch |
| Two ALBs instead of one | `group.name` differs between Ingresses |
| 502 during deploys | Readiness gate label missing on the namespace, or `preStop` removed |
| 504 on `/chat` | Streaming exceeds the idle timeout. Raise `ingress.idleTimeoutSeconds` |

## Rollback

Revert values in Git. Deleting an Ingress deletes its rules. Deleting the last Ingress in a group deletes the ALB (prod has `deletion_protection.enabled=true`, so the controller reports an error instead).
