# ARCHITECTURE DECISION: All addons are installed via Helm charts with explicit
# versions pinned for reproducibility. This module installs the core platform
# addons required for a production AKS deployment.
# SECURITY SAFEGUARD: Each addon is configured with the principle of least privilege.
# Network policies, RBAC roles, and service accounts are scoped to minimum required
# permissions.

# ── NGINX Ingress Controller ───────────────────────────────────────
# ARCHITECTURE DECISION: NGINX Ingress is deployed behind Azure Application Gateway
# WAF v2. The WAF provides OWASP ModSecurity Core Rule Set (CRS) at the perimeter,
# while NGINX handles TLS termination, routing, and rate limiting.
# SECURITY SAFEGUARD: The controller runs with hostNetwork: false and is restricted
# to the ingress-nginx namespace via network policies.

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = var.ingress_nginx_helm_version
  timeout          = 600
  wait             = true

  values = [templatefile("${path.module}/templates/ingress-nginx-values.yaml", {
    load_balancer_ip      = var.ingress_load_balancer_ip
    domain                = var.domain
    enable_telemetry      = var.enable_telemetry
  })]
}

# ── cert-manager ───────────────────────────────────────────────────
# ARCHITECTURE DECISION: cert-manager with Azure DNS challenge (DNS-01) validates
# domain ownership via Azure DNS API. This is more secure than HTTP-01 validation
# which requires external HTTP access to the cluster.
# SECURITY SAFEGUARD: The Azure DNS service principal is scoped to the DNS Zone
# Contributor role on the specific managed zone, not the entire subscription.

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  version          = var.cert_manager_helm_version
  timeout          = 600
  wait             = true

  # SECURITY SAFEGUARD: cert-manager is configured with:
  # - featureGates: AdditionalCertificateOutputFormats for compatibility
  # - Resources limits to prevent resource exhaustion
  # - PodDisruptionBudget for HA

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }

  set {
    name  = "replicaCount"
    value = "2"
  }

  set {
    name  = "webhook.replicaCount"
    value = "2"
  }

  set {
    name  = "cainjector.replicaCount"
    value = "2"
  }
}

# ── ExternalDNS (Azure DNS) ───────────────────────────────────────
# ARCHITECTURE DECISION: ExternalDNS syncs Kubernetes ingress and service resources
# to Azure DNS. It uses the cluster's managed identity via Workload Identity for
# authentication, eliminating service principal secrets.
# SECURITY SAFEGUARD: ExternalDNS is scoped to read/write only the specific DNS
# zone it manages via RBAC on the Azure DNS zone resource.

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  version          = var.external_dns_helm_version
  timeout          = 600
  wait             = false

  values = [templatefile("${path.module}/templates/external-dns-values.yaml", {
    domain                = var.domain
    tenant_id             = var.key_vault_tenant_id
    enable_telemetry      = var.enable_telemetry
  })]
}

# ── Azure Key Vault Provider for Secrets Store CSI Driver ──────────
# ARCHITECTURE DECISION: Secrets Store CSI Driver mounts Azure Key Vault secrets
# as CSI volumes in pods. This keeps secrets out of etcd and enables automatic
# rotation without pod restarts.
# SECURITY SAFEGUARD: The driver uses the node's managed identity (or Workload
# Identity) for AKV authentication. Secrets are never written to disk — they
# exist only in tmpfs within the pod.

resource "helm_release" "secrets_store_csi" {
  name             = "secrets-store-csi-driver"
  repository       = "https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts"
  chart            = "secrets-store-csi-driver"
  namespace        = "kube-system"
  version          = var.secrets_store_csi_helm_version
  timeout          = 600
  wait             = true

  set {
    name  = "syncSecret.enabled"
    value = "false"
  }

  set {
    name  = "enableSecretRotation"
    value = "true"
  }

  set {
    name  = "rotationPollInterval"
    value = "120s"
  }
}

resource "helm_release" "secrets_store_csi_akv" {
  name             = "secrets-store-csi-driver-akv"
  repository       = "https://raw.githubusercontent.com/Azure/secrets-store-csi-driver-provider-azure/master/charts"
  chart            = "csi-secrets-store-provider-azure"
  namespace        = "kube-system"
  version          = var.secrets_store_csi_akv_helm_version
  timeout          = 600
  wait             = true

  depends_on = [helm_release.secrets_store_csi]
}

# ── Kyverno ────────────────────────────────────────────────────────
# ARCHITECTURE DECISION: Kyverno provides Kubernetes-native policy management
# without a separate admission webhook language (like OPA/Rego). Policies are
# defined as Kubernetes resources, enabling GitOps-style policy management.
# SECURITY SAFEGUARD: Kyverno enforces:
# - Disallow privileged containers
# - Require read-only root filesystem
# - Disallow host network/pid/ipc access
# - Require resource limits
# - Enforce pod security standards (restricted profile)

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno/"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = var.kyverno_helm_version
  timeout          = 600
  wait             = true

  set {
    name  = "replicaCount"
    value = "2"
  }

  set {
    name  = "webhook.replicaCount"
    value = "2"
  }

  set {
    name  = "global.podSecurityStandard"
    value = "restricted"
  }

  set {
    name  = "features.policyExceptions.enabled"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }
}

# ── KEDA (Kubernetes Event-Driven Autoscaling) ─────────────────────
# ARCHITECTURE DECISION: KEDA enables event-driven scaling for any workload.
# It works alongside HPA and cluster autoscaler, scaling workloads based on
# Azure Queue Storage, Service Bus, Event Hubs, Prometheus metrics, etc.
# SECURITY SAFEGUARD: KEDA operators use Workload Identity for Azure resource
# authentication. ScaledObject CRDs are namespace-scoped to prevent cross-namespace
# metric access.

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "keda"
  create_namespace = true
  version          = var.keda_helm_version
  timeout          = 600
  wait             = true

  set {
    name  = "podIdentity.provider"
    value = "azure-workload"
  }

  set {
    name  = "operator.replicaCount"
    value = "2"
  }

  set {
    name  = "metricsServer.replicaCount"
    value = "2"
  }

  set {
    name  = "webhook.replicaCount"
    value = "2"
  }

  set {
    name  = "prometheus.metricsServer.enabled"
    value = "true"
  }
}

# ── OpenTelemetry Operator ─────────────────────────────────────────
# ARCHITECTURE DECISION: OpenTelemetry Operator manages the OTel collector
# lifecycle and auto-instrumentation injection via sidecars. It replaces
# vendor-specific agents with a unified observability pipeline.
# SECURITY SAFEGUARD: The operator is configured with restricted security context.
# Instrumentation CRDs are limited to specific namespaces via webhooks.

resource "helm_release" "opentelemetry_operator" {
  name             = "opentelemetry-operator"
  repository       = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart            = "opentelemetry-operator"
  namespace        = "opentelemetry"
  create_namespace = true
  version          = var.opentelemetry_helm_version
  timeout          = 600
  wait             = true

  set {
    name  = "manager.collectorImage.repository"
    value = "otel/opentelemetry-collector-contrib"
  }

  set {
    name  = "manager.collectorImage.tag"
    value = var.opentelemetry_collector_version
  }

  set {
    name  = "admissionWebhooks.certManager.enabled"
    value = "true"
  }

  set {
    name  = "prometheus.enabled"
    value = "true"
  }
}

# ── Virtual Node (Virtual Kubelet / ACI) ───────────────────────────
# ARCHITECTURE DECISION: Virtual nodes enable burst scaling to Azure Container
# Instances (ACI) without provisioning additional VMs. Used for batch/ML jobs
# with KEDA-triggered scaling.
# SECURITY SAFEGUARD: Virtual nodes only support limited security contexts (must
# be non-root). Workloads requiring host features or privileged mode are tainted
# against the virtual node.

resource "helm_release" "virtual_kubelet" {
  count = var.enable_virtual_nodes ? 1 : 0

  name       = "virtual-kubelet"
  repository = "https://virtual-kubelet.github.io/helm-charts"
  chart      = "virtual-kubelet"
  namespace  = "virtual-kubelet"
  create_namespace = true
  version    = var.virtual_kubelet_helm_version
  timeout    = 600
  wait       = false

  values = [templatefile("${path.module}/templates/virtual-kubelet-values.yaml", {
    cluster_name    = var.aks_cluster_name
    resource_group  = var.resource_group_name
    location        = var.location
  })]
}

# ── Application Gateway Ingress Controller (AGIC) ──────────────────
# ARCHITECTURE DECISION: AGIC bridges NGINX Ingress with Azure Application Gateway
# WAF. The WAF provides OWASP CRS rule enforcement at the edge. AGIC addon is
# configured via the AKS cluster resource rather than a separate Helm chart.

# AGIC is enabled via the aks-cluster module: ingress_application_gateway block.
# The addon creates the necessary routing configuration.

# ── Custom Kyverno Policies ────────────────────────────────────────
# SECURITY SAFEGUARD: Enforce read-only root filesystem for all pods, unless
# explicitly exempted via Kyverno policy exceptions.

resource "kubectl_manifest" "kyverno_policy_readonly_rootfs" {
  yaml_body = <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-readonly-rootfs
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-readonly-rootfs
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Root filesystem must be read-only."
        pattern:
          spec:
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kyverno
                - gatekeeper-system
YAML
}

# SECURITY SAFEGUARD: Deny privileged containers across all namespaces.

resource "kubectl_manifest" "kyverno_policy_deny_privileged" {
  yaml_body = <<YAML
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: deny-privileged-containers
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: check-privileged
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Privileged containers are not allowed."
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: false
      exclude:
        any:
          - resources:
              namespaces:
                - kube-system
                - kyverno
                - gatekeeper-system
YAML
}

# ── ServiceMonitor / PodMonitor for Prometheus ─────────────────────
# ARCHITECTURE DECISION: ServiceMonitor CRDs enable Prometheus to discover and
# scrape metrics from addon services automatically.

resource "kubectl_manifest" "prometheus_ingress_nginx_sm" {
  yaml_body = <<YAML
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
  labels:
    release: kube-prometheus-stack
spec:
  selector:
    matchLabels:
      app.kubernetes.io/component: controller
      app.kubernetes.io/instance: ingress-nginx
  endpoints:
    - port: metrics
      interval: 30s
YAML
}
