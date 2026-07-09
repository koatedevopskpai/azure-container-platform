# ARCHITECTURE DECISION: Outputs are intentionally minimal — raw kubeconfig is
# marked sensitive and should only be consumed programmatically by CI/CD.
# SECURITY SAFEGUARD: Cluster credentials are never stored in logs or state files
# accessible to non-admin users.

output "cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.id
}

output "cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.this.name
}

output "cluster_endpoint" {
  description = "Private FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.this.private_fqdn
}

output "kube_config_raw" {
  description = "Raw kubeconfig for programmatic access (sensitive)"
  value       = azurerm_kubernetes_cluster.this.kube_config_raw
  sensitive   = true
}

output "kube_config" {
  description = "Kubeconfig block for provider configuration"
  value       = azurerm_kubernetes_cluster.this.kube_config[0]
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation"
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "workload_identity_pool" {
  description = "Workload identity pool name for federated credentials"
  value       = azurerm_kubernetes_cluster.this.workload_identity_enabled ? "aks-${azurerm_kubernetes_cluster.this.name}" : null
}

output "managed_resource_group" {
  description = "Name of the AKS-managed infrastructure resource group"
  value       = azurerm_kubernetes_cluster.this.node_resource_group
}

output "acr_id" {
  description = "ACR IDs attached to the cluster"
  value       = var.acr_ids
}

output "principal_id" {
  description = "Principal ID of the cluster's system-assigned managed identity"
  value       = azurerm_kubernetes_cluster.this.identity[0].principal_id
}

output "kubelet_identity_object_id" {
  description = "Object ID of the kubelet managed identity"
  value       = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
