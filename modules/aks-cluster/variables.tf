# ARCHITECTURE DECISION: Module variables expose only the configuration parameters
# that meaningfully vary between environments. Cluster-wide settings are hardcoded
# within the module to enforce consistency.
# SECURITY SAFEGUARD: All identity-related variables are scoped to specific Azure
# resources to enforce least-privilege access.

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for AKS and related resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the cluster"
  type        = string
}

variable "vnet_subnet_id" {
  description = "Subnet ID for the AKS node pool"
  type        = string
}

variable "private_dns_zone_id" {
  description = "Private DNS zone ID for AKS private endpoint (empty for auto-creation)"
  type        = string
  default     = ""
}

variable "aks_admin_group_ids" {
  description = "Azure AD group IDs for cluster admin RBAC"
  type        = list(string)
  default     = []
}

variable "pod_cidr" {
  description = "CIDR range for pods (Azure CNI Cilium)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR range for services"
  type        = string
  default     = "10.245.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address for CoreDNS within service CIDR"
  type        = string
  default     = "10.245.0.10"
}

variable "zones" {
  description = "Availability zones for the default node pool"
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_node_pool_vm_size" {
  description = "VM size for the default system node pool"
  type        = string
  default     = "Standard_D4s_v5"
}

variable "system_node_pool_min_count" {
  description = "Minimum node count for system pool autoscaling"
  type        = number
  default     = 1
}

variable "system_node_pool_max_count" {
  description = "Maximum node count for system pool autoscaling"
  type        = number
  default     = 5
}

variable "system_node_pool_node_count" {
  description = "Initial node count for system pool"
  type        = number
  default     = 3
}

variable "system_node_pool_os_disk_size_gb" {
  description = "OS disk size in GB for system nodes"
  type        = number
  default     = 128
}

variable "max_pods_per_node" {
  description = "Maximum number of pods per node"
  type        = number
  default     = 50
}

variable "acr_ids" {
  description = "Map of ACR names to resource IDs for AcrPull role assignment"
  type        = map(string)
  default     = {}
}

variable "defender_workspace_id" {
  description = "Log Analytics workspace ID for Microsoft Defender for Containers"
  type        = string
  default     = ""
}

variable "kms_key_vault_key_id" {
  description = "Key Vault key ID for KMS etcd encryption (optional)"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
