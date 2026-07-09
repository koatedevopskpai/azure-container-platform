# ARCHITECTURE DECISION: Workload Identity replaces Azure AD Pod Identity (deprecated)
# and service principal-based auth. Each Kubernetes service account is bound to an
# Azure Managed Identity via OIDC federation. This enables:
# - Keyless authentication to Azure resources (no secrets to rotate)
# - Managed identity credential lifecycle managed by Azure
# - Fine-grained RBAC per workload via role assignments
# SECURITY SAFEGUARD: Federated credentials are scoped to a specific namespace and
# service account, preventing identity theft across workloads. The managed identity
# itself has no permissions until explicitly assigned via Azure RBAC.

# ARCHITECTURE DECISION: User-assigned managed identity per workload ensures
# isolation. A single identity per service account prevents privilege escalation
# if one workload is compromised.

resource "azurerm_user_assigned_identity" "this" {
  name                = var.identity_name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# ARCHITECTURE DECISION: Federated identity credential links the K8s service account
# to the Azure managed identity using the cluster's OIDC issuer. The subject
# identifier format is: system:serviceaccount:<namespace>:<service_account>
# SECURITY SAFEGUARD: The credential is scoped to a single namespace and service
# account. Wildcards are not used in the subject to maintain strict isolation.

resource "azurerm_federated_identity_credential" "this" {
  name                = "${var.identity_name}-federated"
  resource_group_name = var.resource_group_name
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.oidc_issuer_url
  subject             = "system:serviceaccount:${var.namespace}:${var.service_account}"
  parent_id           = azurerm_user_assigned_identity.this.id
}

# ARCHITECTURE DECISION: Role assignments grant the managed identity access to
# specific Azure resources (Key Vault, Storage, Service Bus, etc.). Each assignment
# is scoped to the minimum required resource.
# SECURITY SAFEGUARD: Role assignments use the least-privilege principle. Only
# specific roles needed by the workload are assigned. Owner/Contributor are never
# granted to workload identities.

resource "azurerm_role_assignment" "workload" {
  for_each = var.identity_role_assignments

  principal_id         = azurerm_user_assigned_identity.this.principal_id
  role_definition_name = each.value
  scope                = each.key
}

# ARCHITECTURE DECISION: The Kubernetes service account must be annotated with
# the managed identity client ID for the Azure Identity SDK to discover it.
# This annotation is applied via the GitOps bootstrap process, not here —
# Terraform manages cloud resources, GitOps manages cluster resources.

resource "azurerm_role_assignment" "federated_identity_operator" {
  principal_id         = var.aks_kubelet_identity_object_id
  role_definition_name = "Managed Identity Operator"
  scope                = azurerm_user_assigned_identity.this.id
}
