# ARCHITECTURE DECISION: GitOps bootstrap variables separate tool choice from
# environment configuration. The same module supports both ArgoCD and Flux.
# SECURITY SAFEGUARD: SSH key and admin password are sensitive — they must never
# appear in Terraform logs, plan output, or state file outputs.

variable "gitops_tool" {
  description = "GitOps tool to bootstrap: 'argocd' or 'flux'"
  type        = string
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository"
  type        = string
  default     = ""
}

variable "gitops_repo_path" {
  description = "Path in the GitOps repo for environment manifests"
  type        = string
  default     = "clusters/production"
}

variable "gitops_ssh_key" {
  description = "SSH private key for GitOps repo authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "admin_password" {
  description = "ArgoCD admin password (bcrypt hashed)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "domain" {
  description = "Root domain for cluster ingress"
  type        = string
  default     = "example.com"
}

variable "cluster_name" {
  description = "Name of the AKS cluster (for Flux substitutions)"
  type        = string
}

variable "argocd_helm_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.7.3"
}

variable "flux_helm_version" {
  description = "Flux2 Helm chart version"
  type        = string
  default     = "2.14.1"
}
