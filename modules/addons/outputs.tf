# ARCHITECTURE DECISION: Addon outputs are minimal — most configuration is done via
# GitOps after bootstrap. The outputs here help with integration testing.
# SECURITY SAFEGUARD: Only ingress-related public endpoints are exposed.

output "ingress_namespace" {
  description = "Namespace for NGINX Ingress Controller"
  value       = "ingress-nginx"
}

output "cert_manager_namespace" {
  description = "Namespace for cert-manager"
  value       = "cert-manager"
}

output "kyverno_namespace" {
  description = "Namespace for Kyverno"
  value       = "kyverno"
}

output "keda_namespace" {
  description = "Namespace for KEDA"
  value       = "keda"
}

output "opentelemetry_namespace" {
  description = "Namespace for OpenTelemetry Operator"
  value       = "opentelemetry"
}

output "ingress_controller_ip" {
  description = "Load balancer IP for NGINX Ingress"
  value       = var.ingress_load_balancer_ip
}
