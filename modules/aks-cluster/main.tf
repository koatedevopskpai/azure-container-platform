# ARCHITECTURE DECISION: Azure CNI Powered by Cilium is chosen over Azure CNI Overlay
# for three reasons: (1) eBPF-based networking provides superior observability via
# Hubble, (2) network policies can be enforced at L3-L7 without sidecar proxies,
# and (3) CiliumClusterWideNetworkPolicy enables policy enforcement across namespaces
# — critical for multi-tenant financial services workloads.
#
# ARCHITECTURE DECISION: Private cluster with private_endpoint_enabled blocks all
# public access to the control plane. This is required for UK financial services
# compliance (FCA/PRA) where the API server must not be internet-reachable.
# Access is via Azure Bastion, VPN, or ExpressRoute only.
#
# ARCHITECTURE DECISION: Workload Identity (OIDC issuer + federated credentials)
# replaces service principals for pod authentication. This eliminates credential
# rotation, secret storage in clusters, and enables keyless access to Azure resources
# from any Kubernetes pod.
#
# SECURITY SAFEGUARD: local_account_disabled = true forces all authentication through
# Azure AD. No Kubernetes Secrets of type "kubernetes.io/service-account-token" are
# auto-generated, preventing token theft via etcd compromise.

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # SECURITY SAFEGUARD: No local admin accounts — all auth via Azure AD.
  local_account_disabled = true

  # ARCHITECTURE DECISION: Azure RBAC is the recommended authorization mode for
  # production clusters. It allows binding Azure AD users/groups to Kubernetes
  # RBAC roles using native Azure RBAC, which can be managed through Azure Policy.
  azure_active_directory_role_based_access_control {
    managed            = true
    admin_group_object_ids = var.aks_admin_group_ids
    azure_rbac_enabled = true
  }

  # ARCHITECTURE DECISION: Private cluster with private DNS zone integration.
  # The API server FQDN resolves to a private IP within the hub vnet.
  private_cluster_enabled          = true
  private_dns_zone_id              = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = false

  # ARCHITECTURE DECISION: OIDC issuer enables Workload Identity federation.
  # Each Kubernetes service account can be bound to an Azure Managed Identity.
  oidc_issuer_enabled = true

  # ARCHITECTURE DECISION: Workload Identity is the recommended approach for pod
  # authentication. It replaces both managed pod identity (deprecated) and
  # service principal-based authentication.
  workload_identity_enabled = true

  # ARCHITECTURE DECISION: Azure CNI with Cilium data plane provides eBPF-based
  # networking, observability, and security policies.
  network_profile {
    network_plugin     = "azure"
    network_plugin_mode = "cilium"
    network_policy     = "cilium"
    dns_service_ip     = var.dns_service_ip
    service_cidr       = var.service_cidr
    pod_cidr           = var.pod_cidr
    outbound_type      = "userDefinedRouting"
    load_balancer_sku  = "standard"
  }

  # ARCHITECTURE DECISION: Azure Policy addon enforces Gatekeeper-based constraints
  # from Azure Policy at the admission controller level.
  azure_policy_enabled = true

  # ARCHITECTURE DECISION: Microsoft Defender for Containers provides vulnerability
  # assessment, runtime threat detection, and security recommendations.
  microsoft_defender {
    log_analytics_workspace_id = var.defender_workspace_id
  }

  # SECURITY SAFEGUARD: Image Cleaner automatically removes unused container images
  # from node VMs, reducing the attack surface from stale vulnerable images.
  image_cleaner_enabled       = true
  image_cleaner_interval_hours = 24

  # SECURITY SAFEGUARD: HTTP application routing is disabled — all ingress traffic
  # flows through NGINX Ingress Controller with WAF in front.
  http_application_routing_enabled = false

  # ARCHITECTURE DECISION: Key Management Service (KMS) etcd encryption ensures
  # secrets at rest in etcd are encrypted with a key from Azure Key Vault.
  key_management_service {
    key_vault_key_id = var.kms_key_vault_key_id
  }

  # SECURITY SAFEGUARD: Autoscaling with cluster autoscaler ensures capacity
  # availability without over-provisioning.
  default_node_pool {
    name                = "system"
    vm_size             = var.system_node_pool_vm_size
    vnet_subnet_id      = var.vnet_subnet_id
    zones               = var.zones
    enable_auto_scaling = true
    min_count           = var.system_node_pool_min_count
    max_count           = var.system_node_pool_max_count
    node_count          = var.system_node_pool_node_count
    os_disk_size_gb     = var.system_node_pool_os_disk_size_gb
    os_disk_type        = "Ephemeral"
    os_sku              = "AzureLinux"
    max_pods            = var.max_pods_per_node
    node_taints         = ["CriticalAddonsOnly=true:NoSchedule"]
    only_critical_addons_enabled = true
  }

  # ARCHITECTURE DECISION: ACR integration allows AKS nodes to pull images
  # from Azure Container Registry using managed identity authentication.
  identity {
    type = "SystemAssigned"
  }

  # ARCHITECTURE DECISION: Automatic upgrades enabled with rapid channel for
  # security patches.
  auto_upgrade_channel = "rapid"

  maintenance_window_auto_upgrade {
    frequency   = "weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "02:00"
    duration    = 4
  }

  maintenance_window_node_os {
    frequency   = "weekly"
    interval    = 1
    day_of_week = "Sunday"
    start_time  = "02:00"
    duration    = 4
  }
}

# ARCHITECTURE DECISION: Separate system node pool management is delegated to
# the aks-node-pools module for consistency with user pools.

# SECURITY SAFEGUARD: Attach ACR via managed identity role assignment to avoid
# using admin keys or service principal secrets.

resource "azurerm_role_assignment" "acr_pull" {
  for_each = var.acr_ids

  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  role_definition_name = "AcrPull"
  scope                = each.value
}

# ARCHITECTURE DECISION: The cluster's managed identity is used for cross-resource
# authentication (e.g., ACR, Azure DNS, Key Vault) via RBAC rather than secrets.

data "azurerm_client_config" "current" {}
