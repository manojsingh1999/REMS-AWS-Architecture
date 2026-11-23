# Deployments (Workloads)

**Status:** ✅ All 7 REMS services render as Argo Rollouts (staging/prod/prod-dr) or Deployments (dev, where `rollout.enabled` is false by default) from `helm/charts/rems-common/templates/_workload.tpl`. 🟡 Container ports (8000 / 8080), health paths (`/healthz`, `/readyz`), `/metrics` and image tags are **placeholders** until the service repositories confirm them.

## Objective

Zero-downtime, hardened pods: non-root, read-only root filesystem, spread across AZs, graceful shutdown, secrets mounted as files.

## Real rendered example (rems-api, prod; image tag is the render placeholder)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: rems-api
  namespace: rems
spec:
  revisionHistoryLimit: 5
  template:
    spec:
      serviceAccountName: rems-api
      priorityClassName: rems-critical
      terminationGracePeriodSeconds: 45
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        seccompProfile:
          type: RuntimeDefault
      nodeSelector:
        rems.io/node-pool: general
      tolerations:
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 60
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: rems-api
      containers:
        - name: rems-api
          image: 444444444444.dkr.ecr.ap-south-1.amazonaws.com/rems/rems-api:sha-0000000
          ports:
            - name: http
              containerPort: 8000          # PLACEHOLDER (assumption P1/P2)
          readinessProbe:
            httpGet: { path: /readyz, port: http }   # PLACEHOLDER (P3)
          lifecycle:
            preStop:
              sleep: { seconds: 15 }
          resources:
            requests: { cpu: 500m, memory: 1Gi }
            limits: { cpu: "2", memory: 1Gi }
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: { drop: [ALL] }
          volumeMounts:
            - name: secret-rems-api-db
              mountPath: /var/run/secrets/rems/rems-api-db
              readOnly: true
  strategy:
    canary:
      canaryService: rems-api-canary
      stableService: rems-api
      maxUnavailable: 0
      trafficRouting:
        alb: { ingress: rems-api, servicePort: 80 }
      steps:
        - setWeight: 10
        - pause: { duration: 2m }
        - setWeight: 25
        - pause: { duration: 3m }
        - setWeight: 50
        - pause: { duration: 5m }
        - setWeight: 100
```

Abbreviated from the output of `python3 scripts/helm_render_check.py --out /tmp/rendered` (file `/tmp/rendered/prod/rems-api.yaml`).

## Design choices

| Concern | Implementation |
|---|---|
| Secrets | Mounted as files under `/var/run/secrets/rems/<secret>/<key>`. **No environment variable names are invented.** The app must read these paths, or the chart's `extraEnv` must map them once the real names are known |
| Telemetry | `OTEL_*` env vars only (standard OpenTelemetry SDK names) pointing to `otel-collector.observability.svc:4318` |
| Graceful shutdown | `preStop` sleep 15 s + ALB deregistration delay 30 s + grace period 45 s |
| AZ failure | Tolerations of 60 s, zone spread with `ScheduleAnyway`, PDB `maxUnavailable: 1` with `unhealthyPodEvictionPolicy: AlwaysAllow` |
| Config changes | `checksum/config` annotation rolls pods when the ConfigMap changes |

## Steps

```bash
# Normal: change the image tag in rems-microconfig (CI does this) -> ArgoCD syncs.
# Inspect:
kubectl argo rollouts list rollouts -n rems
kubectl argo rollouts get rollout rems-api -n rems --watch
```

## Verification

```bash
kubectl get rollouts,deploy -n rems -n rems-ai
kubectl get pods -n rems -o wide -L topology.kubernetes.io/zone
kubectl get pdb -n rems
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `CrashLoopBackOff` with a read-only FS error | The app writes outside `/tmp`. Add an `emptyDir` mount via values (`extraVolumes` if available) or fix the app |
| Probe failures right after deploy | Health paths are placeholders. Set `probes.*.path` in the chart values |
| Rollout `Degraded`, analysis failed | See [rollback procedure](../06-cicd/rollback-procedure.md) |
| Pods `Pending` | Quota exhausted (`kubectl describe quota -n rems`) or Karpenter can't launch (`kubectl get nodeclaims`, controller logs) |

## Rollback

```bash
kubectl argo rollouts abort rems-api -n rems        # immediate traffic back to stable
# Permanent: revert the tag in rems-microconfig (rollback.yml workflow)
```
