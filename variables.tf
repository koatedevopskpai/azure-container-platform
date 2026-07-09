# ARCHITECTURE DECISION: Variables are grouped by concern — cluster, networking,
# identity, GitOps, addons, and observability — to simplify per-environment
# configuration via terraform.tfvars or CI/CD variable groups.
# SECURITY SAFEGUARD: Sensitive variables (ssh_key, passwords) are marked as
# sensitive to prevent exposure in logs and plan output.

# ── Cluster Configuration ──────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.cluster_name))
    error_message = "Cluster name must be 1-63 characters, lowercase alphanumeric with hyphens."
  }
}

variable "resource_group_name" {
  description = "Name of the Azure Resource Group for AKS resources"
  type        = string
}

variable "location" {
  description = "Azure region for all resources (e.g., uksouth, westeurope)"
  type        = string
  default     = "uksouth"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster (e.g., 1.30)"
  type        = string
  default     = "1.30"
}

variable "tags" {
  description = "Resource tags applied to all created resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Platform    = "aks-container-platform"
    SecondWave  = "insurer-migration"
  }
}

variable "aks_admin_group_name" {
  description = "Azure AD group name for AKS cluster administrators"
  type        = string
  default     = "AKS Cluster Admins"
}

# ── Networking ─────────────────────────────────────────────────────

variable "vnet_subnet_id" {
  description = "Resource ID of the subnet for AKS node pool (must have /21 or larger)"
  type        = string
}

variable "network_plugin_mode" {
  description = "Network plugin mode: 'overlay' or 'cilium'"
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["overlay", "cilium"], var.network_plugin_mode)
    error_message = "Network plugin mode must be 'overlay' or 'cilium'."
  }
}

variable "pod_cidr" {
  description = "CIDR range for pods (Azure CNI Cilium)"
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "CIDR range for Kubernetes services"
  type        = string
  default     = "10.245.0.0/16"
}

variable "dns_service_ip" {
  description = "IP address within service_cidr for CoreDNS"
  type        = string
  default     = "10.245.0.10"
}

# ── Identity & Workload Identity ───────────────────────────────────

variable "workload_identities" {
  description = "Map of workload identity configurations for pod-level Azure auth"
  type = map(object({
    namespace        = string
    service_account  = string
    role_assignments = map(string) # scope -> role_definition_name
  }))
  default = {}
}

# ── Node Pools ─────────────────────────────────────────────────────

variable "node_pools" {
  description = "Configuration for AKS node pools (system + user)"
  type = map(object({
    vm_size                  = optional(string, "Standard_D4s_v5")
    node_count               = optional(number, 3)
    min_count                = optional(number, 1)
    max_count                = optional(number, 10)
    os_disk_size_gb          = optional(number, 128)
    os_disk_type             = optional(string, "Ephemeral")
    os_sku                   = optional(string, "AzureLinux")
    priority                 = optional(string, "Regular") # Regular or Spot
    eviction_policy          = optional(string, "Delete")
    spot_max_price           = optional(number, -1)
    node_taints              = optional(list(string), [])
    labels                   = optional(map(string), {})
    enable_auto_scaling      = optional(bool, true)
    enable_node_public_ip    = optional(bool, false)
    enable_host_encryption   = optional(bool, true)
    zones                    = optional(list(string), ["1", "2", "3"])
    max_pods                 = optional(number, 50)
    upgrade_settings         = optional(map(string), {})
  }))
  default = {
    system = {
      vm_size        = "Standard_D4s_v5"
      node_count     = 3
      min_count      = 1
      max_count      = 5
      node_taints    = ["CriticalAddonsOnly=true:NoSchedule"]
      labels         = { pool = "system" }
      max_pods       = 50
    }
    user = {
      vm_size        = "Standard_D8s_v5"
      node_count     = 3
      min_count      = 1
      max_count      = 10
      node_taints    = []
      labels         = { pool = "user" }
      max_pods       = 50
    }
  }
}

# ── GitOps Configuration ───────────────────────────────────────────

variable "gitops_tool" {
  description = "GitOps tool to bootstrap: 'argocd' or 'flux'"
  type        = string
  default     = "argocd"

  validation {
    condition     = contains(["argocd", "flux"], var.gitops_tool)
    error_message = "GitOps tool must be 'argocd' or 'flux'."
  }
}

variable "gitops_repo_url" {
  description = "URL of the GitOps repository (git@github.com:org/repo.git or https://...)"
  type        = string
  default     = ""
}

variable "gitops_repo_path" {
  description = "Path within the GitOps repo for app-of-apps manifests"
  type        = string
  default     = "clusters/production"
}

variable "gitops_ssh_key" {
  description = "SSH private key for GitOps repo authentication"
  type        = string
  sensitive   = true
  default     = ""
}

variable "argocd_admin_password" {
  description = "ArgoCD admin password (bcrypt hashed). Generate with: argocd admin bcrypt"
  type        = string
  sensitive   = true
  default     = ""
}

# ── Addons Configuration ───────────────────────────────────────────

variable "domain" {
  description = "Root domain for ingress (e.g., secondwave-insurance.com)"
  type        = string
  default     = "example.com"
}

variable "cert_manager_email" {
  description = "Email address for Let's Encrypt / ACME certificate notifications"
  type        = string
  default     = "admin@example.com"
}

variable "ingress_load_balancer_ip" {
  description = "Static public IP for NGINX Ingress Controller"
  type        = string
  default     = ""
}

variable "application_gateway_id" {
  description = "Resource ID of Azure Application Gateway (WAF) for AGIC ingress"
  type        = string
  default     = ""
}

variable "application_gateway_name" {
  description = "Name of Azure Application Gateway (WAF)"
  type        = string
  default     = ""
}

variable "application_gateway_rg" {
  description = "Resource group of Azure Application Gateway"
  type        = string
  default     = ""
}

variable "key_vault_name" {
  description = "Name of Azure Key Vault for Secrets Store CSI Driver"
  type        = string
  default     = ""
}

variable "key_vault_rg" {
  description = "Resource group of Azure Key Vault"
  type        = string
  default     = ""
}

# ── Observability ──────────────────────────────────────────────────

variable "open_telemetry_sampler_ratio" {
  description = "Sampling ratio for OpenTelemetry traces (0.0-1.0)"
  type        = number
  default     = 0.1

  validation {
    condition     = var.open_telemetry_sampler_ratio >= 0 && var.open_telemetry_sampler_ratio <= 1
    error_message = "Sampler ratio must be between 0 and 1."
  }
}

# ── Defender ───────────────────────────────────────────────────────

variable "enable_defender_for_containers" {
  description = "Enable Microsoft Defender for Containers (vulnerability scanning)"
  type        = bool
  default     = true
}

variable "defender_workspace_id" {
  description = "Log Analytics workspace ID for Defender alerts"
  type        = string
  default     = ""
}
