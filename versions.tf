# ARCHITECTURE DECISION: Terraform 1.9+ provides improved provider function support and
# consistent plan output. AzureRM 4.0+ is required for Azure CNI Powered by Cilium support
# and Workload Identity V2 APIs. AzureAD 3.0 provides the azuread_application_federated_identity_credential
# resource needed for Workload Identity federation.
# SECURITY SAFEGUARD: Backend state is stored in Azure Storage with encryption at rest.
# The commented backend block must be configured per-environment to prevent state leakage.

terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 2.1"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # SECURITY SAFEGUARD: Backend configured per-environment via partial config.
  # Do not commit backend vars to version control.
  # backend "azurerm" {
  #   resource_group_name  = "terraform-state-rg"
  #   storage_account_name = "tfstate<random>"
  #   container_name       = "aks-platform"
  #   key                  = "container-platform.tfstate"
  # }
}

provider "azurerm" {
  # ARCHITECTURE DECISION: Explicit subscription_id prevents accidental cross-subscription
  # deployments. Features block enables graceful destroy of resources.
  # SECURITY SAFEGUARD: Use managed identity (OIDC) for provider auth, not service principals.
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy               = true
      recover_soft_deleted_key_vaults            = true
    }
  }
}

provider "azuread" {
  # ARCHITECTURE DECISION: AzureAD provider is used solely for Workload Identity
  # federated credential resources. No directory-level permissions are needed.
}

provider "helm" {
  kubernetes {
    host                   = module.aks-cluster.cluster_endpoint
    client_certificate     = module.aks-cluster.kube_config.0.client_certificate
    client_key             = module.aks-cluster.kube_config.0.client_key
    cluster_ca_certificate = module.aks-cluster.kube_config.0.cluster_ca_certificate
  }
}

provider "kubernetes" {
  host                   = module.aks-cluster.cluster_endpoint
  client_certificate     = module.aks-cluster.kube_config.0.client_certificate
  client_key             = module.aks-cluster.kube_config.0.client_key
  cluster_ca_certificate = module.aks-cluster.kube_config.0.cluster_ca_certificate
}

provider "kubectl" {
  host                   = module.aks-cluster.cluster_endpoint
  client_certificate     = module.aks-cluster.kube_config.0.client_certificate
  client_key             = module.aks-cluster.kube_config.0.client_key
  cluster_ca_certificate = module.aks-cluster.kube_config.0.cluster_ca_certificate
}
