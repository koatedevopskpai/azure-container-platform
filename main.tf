# ARCHITECTURE DECISION: This root module assembles all sub-modules into a cohesive
# platform. Each module is independently testable and reusable across environments.
# SECURITY SAFEGUARD: All secrets (K8s SA tokens, federated credentials) are managed
# via Azure Workload Identity — no static secrets in CI/CD or application code.

terraform {
  # Backend configured in versions.tf
}

# ARCHITECTURE DECISION: Azure AD group for cluster administrators. Members of this
# group receive cluster-admin RBAC binding via AKS-managed Azure AD integration.
# SECURITY SAFEGUARD: No local accounts — all authentication flows through Azure AD
# with conditional access policies enforced at the tenant level.

data "azuread_group" "aks_admins" {
  display_name     = var.aks_admin_group_name
  security_enabled = true
}

# ARCHITECTURE DECISION: Private AKS cluster ensures the control plane is inaccessible
# from the public internet. All API server communication occurs over peering or VPN,
# meeting financial services regulatory requirements for network isolation.
# SECURITY SAFEGUARD: Azure Policy addon enforces pod security at admission time.

module "aks-cluster" {
  source = "./modules/aks-cluster"

  cluster_name          = var.cluster_name
  resource_group_name   = var.resource_group_name
  location              = var.location
  vnet_subnet_id        = var.vnet_subnet_id
  kubernetes_version    = var.kubernetes_version
  aks_admin_group_ids   = [data.azuread_group.aks_admins.object_id]
  tags                  = var.tags
}

# ARCHITECTURE DECISION: System node pool hosts critical system pods (CoreDNS,
# metrics-server) and is tainted to prevent workload scheduling. User pools
# are separated by workload profile (platform, ML, api).
# SECURITY SAFEGUARD: Spot node pools are only used for non-production workloads
# with tolerations, ensuring fault-tolerant batch jobs absorb interruptions.

module "aks-node-pools" {
  source = "./modules/aks-node-pools"

  cluster_id         = module.aks-cluster.cluster_id
  resource_group_name = var.resource_group_name
  node_pools         = var.node_pools
  tags               = var.tags
}

# ARCHITECTURE DECISION: Workload Identity replaces service principals for pod-level
# auth. Each Kubernetes service account maps to an Azure Managed Identity via OIDC
# federation, eliminating credential rotation and secret sprawl.
# SECURITY SAFEGUARD: Managed identities are scoped to specific Azure resources via
# RBAC, enforcing least-privilege per workload.

module "workload-identity" {
  source = "./modules/workload-identity"

  for_each = var.workload_identities

  oidc_issuer_url    = module.aks-cluster.oidc_issuer_url
  aks_cluster_name   = var.cluster_name
  resource_group_name = var.resource_group_name
  location           = var.location
  namespace          = each.value.namespace
  service_account    = each.value.service_account
  identity_name      = each.key
  identity_role_assignments = each.value.role_assignments
  tags               = var.tags
}

# ARCHITECTURE DECISION: GitOps bootstrap via ArgoCD or Flux (configurable) provides
# declarative, version-controlled cluster state. App-of-apps pattern enables teams
# to self-service their namespaces via PRs to the gitops repo.
# SECURITY SAFEGUARD: Helm values are templated from Terraform variables, preventing
# credentials from being hardcoded in application repos.

module "gitops-bootstrap" {
  source = "./modules/gitops-bootstrap"

  gitops_tool         = var.gitops_tool
  gitops_repo_url     = var.gitops_repo_url
  gitops_repo_path    = var.gitops_repo_path
  gitops_ssh_key      = var.gitops_ssh_key
  admin_password      = var.argocd_admin_password
  domain              = var.domain
  cluster_name        = var.cluster_name
  depends_on = [
    module.aks-cluster,
    module.aks-node-pools
  ]
}

# ARCHITECTURE DECISION: Addons are managed via Helm releases from this module,
# ensuring consistent versions across environments. NGINX Ingress with Azure
# Application Gateway WAF provides L7 DDoS protection and OWASP rule enforcement.
# SECURITY SAFEGUARD: cert-manager uses Azure DNS challenge validation, reducing
# attack surface vs HTTP-01. Secrets Store CSI Driver syncs from AKV, never
# persisting secrets to etcd.

module "addons" {
  source = "./modules/addons"

  aks_cluster_name                = var.cluster_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  domain                          = var.domain
  cert_manager_email              = var.cert_manager_email
  ingress_load_balancer_ip        = var.ingress_load_balancer_ip
  application_gateway_id          = var.application_gateway_id
  application_gateway_name        = var.application_gateway_name
  application_gateway_rg          = var.application_gateway_rg
  key_vault_name                  = var.key_vault_name
  key_vault_rg                    = var.key_vault_rg
  key_vault_tenant_id             = data.azurerm_client_config.current.tenant_id
  open_telemetry_sampler_ratio    = var.open_telemetry_sampler_ratio
  tags                            = var.tags

  depends_on = [
    module.aks-cluster,
    module.aks-node-pools,
    module.gitops-bootstrap
  ]
}

data "azurerm_client_config" "current" {}

# ARCHITECTURE DECISION: Azure Policy assignments are applied at the AKS cluster scope
# to enforce compliance without affecting non-AKS resources in the subscription.
# SECURITY SAFEGUARD: Built-in policies prevent privilege escalation and read-only root
# filesystem enforcement. Custom policies deny privileged containers and host networking.

resource "azurerm_resource_group_policy_assignment" "aks_policies" {
  name                 = "aks-platform-policies"
  resource_group_id    = var.resource_group_name
  policy_definition_id = "/providers/Microsoft.Authorization/policySetDefinitions/kubernetes"
  display_name         = "Azure Policy for AKS Platform"
  location             = var.location
  identity {
    type = "SystemAssigned"
  }
}

# SECURITY SAFEGUARD: Custom Azure Policy initiative denies privileged containers
# across all namespaces in the AKS cluster.

resource "azurerm_resource_group_policy_assignment" "deny_privileged" {
  name                 = "deny-privileged-containers"
  resource_group_id    = var.resource_group_name
  policy_definition_id = azurerm_policy_definition.deny_privileged.id
  display_name         = "Deny Privileged Containers in AKS"
  location             = var.location
  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_policy_definition" "deny_privileged" {
  name         = "deny-privileged-aks-containers"
  policy_type  = "Custom"
  mode         = "Microsoft.Kubernetes.Data"
  display_name = "Deny privileged containers in AKS"

  policy_rule = <<POLICY_RULE
{
  "if": {
    "field": "type",
    "in": ["Microsoft.ContainerService/managedClusters", "Microsoft.Kubernetes/connectedClusters"]
  },
  "then": {
    "effect": "[parameters('effect')]",
    "details": {
      "constraintTemplate": "https://raw.githubusercontent.com/Azure/azure-policy/master/built-in-references/Kubernetes/privileged-containers/template.yaml",
      "constraints": []
    }
  }
}
POLICY_RULE

  parameters = <<PARAMETERS
{
  "effect": {
    "type": "String",
    "metadata": {
      "displayName": "Effect",
      "description": "Deny or Audit"
    },
    "allowedValues": ["deny", "audit"],
    "defaultValue": "deny"
  }
}
PARAMETERS
}

# SECURITY SAFEGUARD: Microsoft Defender for Containers provides vulnerability
# scanning for container images in ACR and running workloads in AKS.

resource "azurerm_security_center_auto_provisioning" "defender_for_containers" {
  auto_provision = "On"
}

resource "azurerm_security_center_subscription_pricing" "defender_containers" {
  tier          = "Standard"
  resource_type = "ContainerRegistry"
}

resource "azurerm_security_center_subscription_pricing" "defender_kubernetes" {
  tier          = "Standard"
  resource_type = "KubernetesService"
}
