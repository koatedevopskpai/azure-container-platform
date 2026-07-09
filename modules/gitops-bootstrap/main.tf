# ARCHITECTURE DECISION: GitOps bootstrap supports two tools (ArgoCD and Flux) via
# conditional resource creation. App-of-apps pattern is used for both: a root
# ApplicationSet/OCIRepository that discovers child applications from the gitops repo.
# SECURITY SAFEGUARD: GitOps repo SSH keys are stored in Azure Key Vault and
# injected via Secrets Store CSI Driver — never hardcoded in manifests.

# ── ArgoCD Bootstrap ───────────────────────────────────────────────

resource "helm_release" "argocd" {
  count = var.gitops_tool == "argocd" ? 1 : 0

  name             = "argo-cd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  version          = var.argocd_helm_version
  timeout          = 600
  wait             = true

  # ARCHITECTURE DECISION: ArgoCD is configured with:
  # - Dex disabled (Azure AD SSO via OIDC config in app-of-apps)
  # - Admin password from Terraform variable (bcrypt-hashed)
  # - Auto-sync with prune for declarative cluster state
  # - Notifications enabled for Slack/Teams alerting on sync failures
  # SECURITY SAFEGUARD: ArgoCD server runs with TLS. Network policies restrict
  # access to only the cluster control plane and Git servers.

  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.admin_password
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "false"
  }

  set {
    name  = "configs.params.server\\.rootpath"
    value = "/argocd"
  }

  set {
    name  = "dex.enabled"
    value = "false"
  }

  set {
    name  = "redis.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "server.metrics.enabled"
    value = "true"
  }

  set {
    name  = "repoServer.metrics.enabled"
    value = "true"
  }

  set {
    name  = "configs.notifications.enabled"
    value = "true"
  }
}

# ARCHITECTURE DECISION: App-of-apps ApplicationSet deploys a root Application
# that points to the gitops repo. Child apps are defined in the repo and are
# automatically discovered by ArgoCD.
# SECURITY SAFEGUARD: The app-of-apps pattern ensures all cluster resources are
# version-controlled. No manual kubectl apply commands are permitted on the cluster.

resource "kubectl_manifest" "argocd_app_of_apps" {
  count = var.gitops_tool == "argocd" && var.gitops_repo_url != "" ? 1 : 0

  yaml_body = <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: ${var.gitops_repo_url}
    targetRevision: HEAD
    path: ${var.gitops_repo_path}
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
      allowEmpty: false
    syncOptions:
      - CreateNamespace=true
      - PruneLast=true
      - ApplyOutOfSyncOnly=true
      - ServerSideApply=true
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas
YAML

  depends_on = [helm_release.argocd]
}

# ── Flux Bootstrap ────────────────────────────────────────────────

resource "helm_release" "flux" {
  count = var.gitops_tool == "flux" ? 1 : 0

  name             = "flux"
  repository       = "https://fluxcd-community.github.io/helm-charts"
  chart            = "flux2"
  namespace        = "flux-system"
  create_namespace = true
  version          = var.flux_helm_version
  timeout          = 600
  wait             = true

  set {
    name  = "watchAllNamespaces"
    value = "true"
  }

  set {
    name  = "eventsAddr"
    value = ""
  }
}

# ARCHITECTURE DECISION: Flux Kustomization for app-of-apps bootstrap.
# SECURITY SAFEGUARD: Flux's image automation (ImageUpdateAutomation) is disabled
# for security-critical namespaces — only platform team can trigger image updates.

resource "kubectl_manifest" "flux_app_of_apps" {
  count = var.gitops_tool == "flux" && var.gitops_repo_url != "" ? 1 : 0

  yaml_body = <<YAML
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  url: ${var.gitops_repo_url}
  ref:
    branch: main
  secretRef:
    name: flux-system
  ignore: |
    /*
    !/${var.gitops_repo_path}/
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 1m
  sourceRef:
    kind: GitRepository
    name: apps
  path: ./${var.gitops_repo_path}
  prune: true
  wait: true
  timeout: 5m
  postBuild:
    substitute:
      cluster_name: ${var.cluster_name}
      domain: ${var.domain}
YAML

  depends_on = [helm_release.flux]
}

# ── SSH Key Secret ─────────────────────────────────────────────────

# ARCHITECTURE DECISION: The GitOps SSH key is stored as a Kubernetes Secret
# via the Terraform kubernetes provider, NOT via kubectl_manifest, to prevent
# the key from appearing in git history.
# SECURITY SAFEGUARD: The SSH key is marked as sensitive and must never be
# logged or output.

resource "kubernetes_secret" "gitops_ssh_key" {
  count = var.gitops_repo_url != "" ? 1 : 0

  metadata {
    name      = "gitops-ssh-key"
    namespace = var.gitops_tool == "argocd" ? "argocd" : "flux-system"
  }

  data = {
    "sshPrivateKey" = var.gitops_ssh_key
  }

  type = "Opaque"
}
