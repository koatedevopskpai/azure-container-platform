# ARCHITECTURE DECISION: Outputs expose minimal connection information to avoid
# leaking sensitive data. Secrets are accessed via Azure Key Vault references
# or Workload Identity, never via Terraform outputs.
# SECURITY SAFEGUARD: Sensitive outputs (kube_config, passwords) are marked as
# sensitive to prevent display in CLI and CI/CD logs.

output "cluster_id" {
  description = "Resource ID of the AKS cluster"
  value       = module.aks-cluster.cluster_id
}

output "cluster_endpoint" {
  description = "Private endpoint for the AKS API server (accessible only from peered networks)"
  value       = module.aks-cluster.cluster_endpoint
  sensitive   = true
}

output "oidc_issuer_url" {
  description = "OIDC issuer URL for Workload Identity federation"
  value       = module.aks-cluster.oidc_issuer_url
}

output "workload_identity_pool" {
  description = "Name of the workload identity pool associated with the cluster"
  value       = module.aks-cluster.workload_identity_pool
}

output "aks_managed_rg" {
  description = "Name of the AKS-managed resource group (MC_*)"
  value       = module.aks-cluster.managed_resource_group
}

output "kube_config_raw" {
  description = "Raw kubeconfig for connecting to the cluster (sensitive)"
  value       = module.aks-cluster.kube_config_raw
  sensitive   = true
}

output "argocd_admin_password_secret" {
  description = "Reference to the ArgoCD admin password in Azure Key Vault"
  value       = var.gitops_tool == "argocd" ? module.gitops-bootstrap.admin_password_secret : null
  sensitive   = true
}

output "acr_id" {
  description = "ID of the Azure Container Registry attached to the cluster"
  value       = module.aks-cluster.acr_id
}

output "defender_for_containers_enabled" {
  description = "Whether Microsoft Defender for Containers is enabled"
  value       = var.enable_defender_for_containers
}

output "workload_identity_identities" {
  description = "Map of workload identity names to their managed identity IDs"
  value = {
    for k, v in module.workload-identity : k => v.identity_id
  }
}
