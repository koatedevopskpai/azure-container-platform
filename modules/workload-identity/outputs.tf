# ARCHITECTURE DECISION: Identity outputs enable workload identity references in
# application configuration and monitoring systems.
# SECURITY SAFEGUARD: Client IDs are not sensitive but should be treated as
# internal-only identifiers.

output "identity_id" {
  description = "Resource ID of the managed identity"
  value       = azurerm_user_assigned_identity.this.id
}

output "identity_client_id" {
  description = "Client ID of the managed identity (used in K8s SA annotations)"
  value       = azurerm_user_assigned_identity.this.client_id
}

output "identity_principal_id" {
  description = "Principal ID of the managed identity (for role assignments)"
  value       = azurerm_user_assigned_identity.this.principal_id
}

output "federated_credential_subject" {
  description = "Subject identifier for the federated identity credential"
  value       = "system:serviceaccount:${var.namespace}:${var.service_account}"
}

output "namespace" {
  description = "Kubernetes namespace for the workload identity"
  value       = var.namespace
}

output "service_account" {
  description = "Kubernetes service account name"
  value       = var.service_account
}
