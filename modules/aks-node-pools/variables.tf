# ARCHITECTURE DECISION: Node pool definitions are passed as a map of objects to
# support multiple pools per environment with different sizing and priority levels.
# SECURITY SAFEGUARD: All pools enforce host encryption and disable public IPs by
# default. Overrides require explicit intent.

variable "cluster_id" {
  description = "Resource ID of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for AKS resources"
  type        = string
}

variable "vnet_subnet_id" {
  description = "Subnet ID for node pool VMs"
  type        = string
  default     = null
}

variable "node_pools" {
  description = "Map of node pool configurations"
  type = map(object({
    vm_size                  = optional(string, "Standard_D4s_v5")
    node_count               = optional(number, 1)
    min_count                = optional(number, 1)
    max_count                = optional(number, 10)
    os_disk_size_gb          = optional(number, 128)
    os_disk_type             = optional(string, "Ephemeral")
    os_sku                   = optional(string, "AzureLinux")
    priority                 = optional(string, "Regular")
    eviction_policy          = optional(string, "Delete")
    spot_max_price           = optional(number, -1)
    node_taints              = optional(list(string), [])
    labels                   = optional(map(string), {})
    enable_auto_scaling      = optional(bool, true)
    enable_node_public_ip    = optional(bool, false)
    enable_host_encryption   = optional(bool, true)
    zones                    = optional(list(string), ["1", "2", "3"])
    max_pods                 = optional(number, 50)
  }))
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
