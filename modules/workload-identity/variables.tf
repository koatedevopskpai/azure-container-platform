# ARCHITECTURE DECISION: Each workload identity maps to exactly one K8s service account
# and one Azure Managed Identity. This 1:1 mapping ensures clear audit trails.
# SECURITY SAFEGUARD: The namespace and service account variables are required — no
# defaults are provided to prevent accidental cross-namespace identity binding.

variable "oidc_issuer_url" {
  description = "OIDC issuer URL from the AKS cluster"
  type        = string
}

variable "aks_cluster_name" {
  description = "Name of the AKS cluster (used in identity naming)"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for managed identity resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "identity_name" {
  description = "Name for the user-assigned managed identity"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace for the service account"
  type        = string
}

variable "service_account" {
  description = "Name of the Kubernetes service account"
  type        = string
}

variable "identity_role_assignments" {
  description = "Map of Azure resource scope to role definition name for the managed identity"
  type        = map(string)
  default     = {}
}

variable "aks_kubelet_identity_object_id" {
  description = "Object ID of the AKS kubelet identity (for Managed Identity Operator role)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
