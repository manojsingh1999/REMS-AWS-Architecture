# AppProjects, the platform root Application and the REMS services ApplicationSet,
# delivered through the argo/argocd-apps chart (no CRD-dependent kubernetes_manifest at plan time).
#
# Charts come from the platform repo, values from the microconfig repo (ArgoCD multi-source with $values),
# so a CI tag bump in rems-microconfig is the only change needed to deploy a new image.

locals {
  platform_url = local.repos.platform.url
  config_url   = local.repos.config.url

  # prod-dr reuses prod values plus its own overrides; every other env has exactly one values file.
  value_files = var.environment == "prod-dr" ? [
    "$values/apps/{{.service}}/values-prod.yaml",
    "$values/apps/{{.service}}/values-prod-dr.yaml",
    "$values/env/prod-dr/global.yaml",
    ] : [
    "$values/apps/{{.service}}/values-${var.environment}.yaml",
    "$values/env/${var.environment}/global.yaml",
  ]

  # Same object shape in both cases (a conditional between differently-shaped objects is a type error).
  sync_policy = {
    automated   = var.auto_sync ? { prune = true, selfHeal = true } : null
    syncOptions = ["ServerSideApply=true", "PruneLast=true"]
    retry       = { limit = 3, backoff = { duration = "20s", factor = 2, maxDuration = "5m" } }
  }

  argocd_apps_values = {
    projects = {
      rems = {
        namespace   = "argocd"
        description = "REMS application services (rems, rems-ai namespaces only)"
        sourceRepos = [local.platform_url, local.config_url]
        destinations = [
          { server = "https://kubernetes.default.svc", namespace = "rems" },
          { server = "https://kubernetes.default.svc", namespace = "rems-ai" },
        ]
        clusterResourceWhitelist = []
        namespaceResourceBlacklist = [
          { group = "", kind = "ResourceQuota" },
          { group = "", kind = "LimitRange" },
        ]
        syncWindows = startswith(var.environment, "prod") ? [
          { kind = "allow", schedule = "30 4 * * 1-4", duration = "8h", applications = ["rems-${var.environment}-*"], manualSync = true },
          { kind = "deny", schedule = "30 12 * * *", duration = "16h", applications = ["rems-${var.environment}-*"], manualSync = true },
        ] : []
      }
      platform = {
        namespace                = "argocd"
        description              = "Cluster add-ons, policies and observability backends"
        sourceRepos              = ["*"]
        destinations             = [{ server = "https://kubernetes.default.svc", namespace = "*" }]
        clusterResourceWhitelist = [{ group = "*", kind = "*" }]
      }
    }

    applications = {
      "platform-${var.environment}" = {
        namespace = "argocd"
        project   = "platform"
        source = {
          repoURL        = local.platform_url
          targetRevision = var.target_revision
          path           = "cicd/argocd/apps/${var.environment}"
          # Only the add-ons ApplicationSet + cluster base; services come from the microconfig ApplicationSet below.
          directory = { include = "platform-addons.yaml" }
        }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy  = { automated = { prune = true, selfHeal = true } }
      }
    }

    applicationsets = {
      "rems-services-${var.environment}" = {
        namespace         = "argocd"
        goTemplate        = true
        goTemplateOptions = ["missingkey=error"]
        generators = [{
          list = {
            elements = [for svc, cfg in var.services : { service = svc, namespace = cfg.namespace, wave = tostring(cfg.wave) }]
          }
        }]
        template = {
          metadata = {
            name = "rems-${var.environment}-{{.service}}"
            annotations = {
              "argocd.argoproj.io/sync-wave"                             = "{{.wave}}"
              "notifications.argoproj.io/subscribe.on-sync-failed.slack" = "rems-deployments"
            }
            labels = { "rems.io/layer" = "application", "rems.io/service" = "{{.service}}" }
          }
          spec = {
            project = "rems"
            sources = [
              {
                repoURL        = local.platform_url
                targetRevision = var.target_revision
                path           = "helm/charts/{{.service}}"
                helm = {
                  releaseName             = "{{.service}}"
                  ignoreMissingValueFiles = var.environment == "prod-dr"
                  valueFiles              = local.value_files
                }
              },
              {
                repoURL        = local.config_url
                targetRevision = var.target_revision
                ref            = "values"
              },
            ]
            destination          = { server = "https://kubernetes.default.svc", namespace = "{{.namespace}}" }
            revisionHistoryLimit = 20
            syncPolicy           = local.sync_policy
            ignoreDifferences = [
              { group = "argoproj.io", kind = "Rollout", jsonPointers = ["/spec/replicas"] },
              { group = "apps", kind = "Deployment", jsonPointers = ["/spec/replicas"] },
            ]
          }
        }
      }
    }
  }
}

resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [yamlencode(local.argocd_apps_values)]

  depends_on = [helm_release.argocd]
}
