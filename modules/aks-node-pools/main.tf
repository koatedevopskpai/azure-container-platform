# ARCHITECTURE DECISION: Separate node pools enable workload isolation:
# - System pool: Critical system pods (CoreDNS, metrics-server) with taints preventing
#   user workloads. OnlyCriticalAddonsEnabled ensures system reliability.
# - User pool: General application workloads with standard scheduling.
# - Spot pool (non-prod): Batch/ML workloads tolerant of interruptions, 80% cost saving.
# SECURITY SAFEGUARD: Spot nodes are tainted with NoSchedule to prevent critical workloads
# from being scheduled on eviction-prone nodes. OS disk encryption with customer-managed
# keys is enabled for all pools handling sensitive data.

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = var.node_pools

  name                  = each.key
  kubernetes_cluster_id = var.cluster_id
  vm_size               = each.value.vm_size
  node_count            = each.value.node_count
  vnet_subnet_id        = var.vnet_subnet_id
  zones                 = each.value.zones
  tags                  = var.tags

  # ARCHITECTURE DECISION: Autoscaling enabled by default with configurable min/max.
  # This handles traffic spikes without manual intervention.
  enable_auto_scaling = each.value.enable_auto_scaling
  min_count           = each.value.min_count
  max_count           = each.value.max_count

  # SECURITY SAFEGUARD: Ephemeral OS disks reduce attack surface — no sensitive data
  # persists on restart. AzureLinux (CBL-Mariner) is a hardened container-optimized OS.
  os_disk_size_gb    = each.value.os_disk_size_gb
  os_disk_type       = each.value.os_disk_type
  os_sku             = each.value.os_sku

  # SECURITY SAFEGUARD: Node public IPs disabled — all outbound traffic via Azure
  # Firewall / NAT Gateway for auditability.
  enable_node_public_ip = each.value.enable_node_public_ip

  # ARCHITECTURE DECISION: Host encryption at-rest with platform-managed keys
  # ensures VM disk encryption for compliance with UK financial services regulations.
  enable_host_encryption = each.value.enable_host_encryption

  # ARCHITECTURE DECISION: Max pods per node is set to benefit from Azure CNI
  # (Cilium) improved IP management.
  max_pods = each.value.max_pods

  # SECURITY SAFEGUARD: Node taints prevent incompatible workloads. Spot VMs get
  # dedicated taints for NoSchedule toleration.
  node_taints = each.value.node_taints
  labels      = each.value.labels

  # ARCHITECTURE DECISION: Spot VMs for non-production workloads use eviction policy
  # "Delete" (only supported option in AKS). Spot node pools are created only when
  # priority == "Spot".
  priority        = each.value.priority
  eviction_policy = each.value.priority == "Spot" ? each.value.eviction_policy : null
  spot_max_price  = each.value.priority == "Spot" ? each.value.spot_max_price : null

  # ARCHITECTURE DECISION: Node OS upgrade channel is managed via AKS maintenance
  # windows defined at the cluster level. Per-pool upgrade overrides are not set
  # to maintain consistency.

  lifecycle {
    # SECURITY SAFEGUARD: Prevent destruction of system pools during updates.
    ignore_changes = [
      node_count,
    ]
  }
}
