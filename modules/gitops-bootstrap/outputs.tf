# ARCHITECTURE DECISION: GitOps outputs expose key identifiers and secrets
# for integration with monitoring and authentication systems.
# SECURITY SAFEGUARD: The admin password secret reference is sensitive —
# use Azure Key Vault for consumption, not Terraform outputs.

output "argocd_namespace" {
  description = "Namespace where ArgoCD is deployed"
  value       = var.gitops_tool == "argocd" ? "argocd" : null
}

output "flux_namespace" {
  description = "Namespace where Flux is deployed"
  value       = var.gitops_tool == "flux" ? "flux-system" : null
}

output "admin_password_secret" {
  description = "Reference to the admin password (for Key Vault or env injection)"
  value       = var.admin_password
  sensitive   = true
}

output "app_of_apps_path" {
  description = "GitOps repo path for app-of-apps manifests"
  value       = var.gitops_repo_path
}

output "gitops_tool" {
  description = "Selected GitOps tool"
  value       = var.gitops_tool
}
