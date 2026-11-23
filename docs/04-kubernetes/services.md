# Services

**Status:** ✅ `rems-common.service` template (`helm/charts/rems-common/templates/_networking.tpl`).

## Objective

Stable in-cluster names for each REMS component, plus a separate canary Service that Argo Rollouts uses for weighted ALB routing.

## What each chart renders

| Object | Name | Port | Purpose |
|---|---|---|---|
| Service | `<chart>` | 80 → named port `http` | Stable traffic |
| Service | `<chart>-canary` | 80 → `http` | Canary traffic (only when `rollout.enabled`) |

Real rendered example (rems-api, prod):

```yaml
apiVersion: v1
kind: Service
metadata:
  name: rems-api
  namespace: rems
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: rems-api
    app.kubernetes.io/instance: rems-api
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
```

## DNS names used across the platform

| Service | DNS |
|---|---|
| authorization-service | `authorization-service.rems.svc.cluster.local` |
| rems-api | `rems-api.rems.svc.cluster.local` |
| metadata-rca | `metadata-rca.rems-ai.svc.cluster.local` |
| mcp-server | `mcp-server.rems-ai.svc.cluster.local` |
| llm-gateway | `llm-gateway.rems-ai.svc.cluster.local:4000` (LiteLLM default port, from `ai-infrastructure/llm-gateway/values.yaml`) |
| OTel Collector | `otel-collector.observability.svc:4318` |
| Prometheus | `kube-prometheus-stack-prometheus.monitoring.svc:9090` |

🟡 How each REMS service discovers the others (config keys) is application-specific and not documented in the source. The charts only guarantee the names above.

## Verification

```bash
kubectl get svc,endpointslices -n rems
kubectl run -it --rm curl -n rems --image=public.ecr.aws/docker/library/busybox:1.36 --restart=Never -- \
  wget -qO- -T 3 http://rems-api/readyz
```

The second command will be **blocked by NetworkPolicy** unless the test pod is allowed. That's expected. Use `kubectl port-forward svc/rems-api 8080:80 -n rems` instead.

## Security considerations

No `LoadBalancer` or `NodePort` Services are allowed (quota = 0). External exposure goes through Ingress only.

## Rollback

Services are stateless. They follow the chart revision.
