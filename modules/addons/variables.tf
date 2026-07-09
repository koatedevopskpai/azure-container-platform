# ARCHITECTURE DECISION: Helm chart versions are pinned to specific releases to
# ensure reproducibility across environments. Version bumps are made intentionally
# after testing in non-production.
# SECURITY SAFEGUARD: All Helm repositories use HTTPS URLs. No unencrypted HTTP
# chart sources are permitted.

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
}

variable "resource_group_name" {
  description = "Resource group for AKS resources"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "domain" {
  description = "Root domain for ingress"
  type        = string
}

variable "cert_manager_email" {
  description = "Email for Let's Encrypt notifications"
  type        = string
}

variable "ingress_load_balancer_ip" {
  description = "Static public IP for NGINX Ingress"
  type        = string
  default     = ""
}

variable "enable_virtual_nodes" {
  description = "Enable virtual nodes (ACI) for burst scaling"
  type        = bool
  default     = true
}

variable "enable_telemetry" {
  description = "Enable telemetry and metrics for addons"
  type        = bool
  default     = true
}

variable "key_vault_name" {
  description = "Name of Azure Key Vault for Secrets Store CSI"
  type        = string
  default     = ""
}

variable "key_vault_rg" {
  description = "Resource group of Azure Key Vault"
  type        = string
  default     = ""
}

variable "key_vault_tenant_id" {
  description = "Tenant ID for Key Vault authentication"
  type        = string
}

variable "application_gateway_id" {
  description = "Resource ID of Application Gateway WAF"
  type        = string
  default     = ""
}

variable "application_gateway_name" {
  description = "Name of Application Gateway"
  type        = string
  default     = ""
}

variable "application_gateway_rg" {
  description = "Resource group of Application Gateway"
  type        = string
  default     = ""
}

variable "open_telemetry_sampler_ratio" {
  description = "OpenTelemetry trace sampling ratio"
  type        = number
  default     = 0.1
}

variable "ingress_nginx_helm_version" {
  type    = string
  default = "4.11.3"
}

variable "cert_manager_helm_version" {
  type    = string
  default = "1.16.2"
}

variable "external_dns_helm_version" {
  type    = string
  default = "1.15.1"
}

variable "secrets_store_csi_helm_version" {
  type    = string
  default = "2.6.4"
}

variable "secrets_store_csi_akv_helm_version" {
  type    = string
  default = "1.5.2"
}

variable "kyverno_helm_version" {
  type    = string
  default = "3.3.3"
}

variable "keda_helm_version" {
  type    = string
  default = "2.16.0"
}

variable "opentelemetry_helm_version" {
  type    = string
  default = "0.108.1"
}

variable "opentelemetry_collector_version" {
  type    = string
  default = "0.116.0"
}

variable "virtual_kubelet_helm_version" {
  type    = string
  default = "1.7.1"
}

variable "tags" {
  description = "Resource tags"
  type        = map(string)
  default     = {}
}
