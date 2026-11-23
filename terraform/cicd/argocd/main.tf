locals {
  repos = {
    platform = { name = var.platform_repo, url = "git@github.com:${var.github_org}/${var.platform_repo}.git" }
    config   = { name = var.config_repo, url = "git@github.com:${var.github_org}/${var.config_repo}.git" }
  }
}

# ------------------------------------------------------------------ namespace (PSA baseline; ArgoCD repo-server needs it)
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "rems.io/tier"                       = "platform"
      "pod-security.kubernetes.io/enforce" = "baseline"
    }
  }
}

# ------------------------------------------------------------------ read-only deploy keys (one pair per cluster and repo)
resource "tls_private_key" "repo" {
  for_each  = local.repos
  algorithm = "ED25519"
}

resource "github_repository_deploy_key" "argocd" {
  for_each   = local.repos
  title      = "argocd-${var.cluster_name}"
  repository = each.value.name
  key        = tls_private_key.repo[each.key].public_key_openssh
  read_only  = true # ArgoCD never writes to Git
}

resource "kubernetes_secret_v1" "repo" {
  for_each = local.repos

  metadata {
    name      = "repo-${each.key}"
    namespace = kubernetes_namespace_v1.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    name          = each.value.name
    url           = each.value.url
    sshPrivateKey = tls_private_key.repo[each.key].private_key_openssh
  }

  depends_on = [github_repository_deploy_key.argocd]
}

# ------------------------------------------------------------------ ArgoCD (HA)
resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name

  values = [file("${path.module}/../../../cicd/argocd/install/values.yaml")]

  set {
    name  = "server.ingress.hostname"
    value = var.argocd_hostname
  }

  set {
    name  = "global.domain"
    value = var.argocd_hostname
  }

  wait    = true
  timeout = 900

  depends_on = [kubernetes_secret_v1.repo]
}
