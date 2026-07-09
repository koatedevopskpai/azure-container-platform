# ARCHITECTURE DECISION: Pool-level outputs enable monitoring and alerting automation.
# SECURITY SAFEGUARD: Node pool names are not sensitive, but avoid exposing
# non-essential identifiers in production logs.

output "node_pool_ids" {
  description = "Map of node pool names to resource IDs"
  value = {
    for k, v in azurerm_kubernetes_cluster_node_pool.this : k => v.id
  }
}

output "node_pool_names" {
  description = "List of node pool names"
  value = [for k, v in azurerm_kubernetes_cluster_node_pool.this : v.name]
}

output "node_pool_taints" {
  description = "Map of node pool names to their taints"
  value = {
    for k, v in azurerm_kubernetes_cluster_node_pool.this : k => v.node_taints
  }
}
