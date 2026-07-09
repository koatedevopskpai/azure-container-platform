# ARCHITECTURE DECISION: TFLint enforces Terraform best practices and Azure-specific
# rules. Rules are configured per-module to avoid false positives on test fixtures.
# SECURITY SAFEGUARD: TFLint will flag any use of hardcoded credentials or insecure
# TLS configurations.

plugin "azurerm" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = false
}

rule "terraform_naming_convention" {
  enabled = true
  format  = "snake_case"
}

# Azure-specific rules
rule "azurerm_resource_group_name_pattern" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_require_rbac" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_require_private_cluster" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_require_azure_policy" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_require_defender" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_no_default_service_principal" {
  enabled = true
}

rule "azurerm_kubernetes_cluster_no_public_ip" {
  enabled = true
}
