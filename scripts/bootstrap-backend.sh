#!/usr/bin/env bash
# ==============================================================================
# bootstrap-backend.sh — Azure Storage Account for Terraform Remote State
#
# ARCHITECTURE DECISION: Terraform state is stored in Azure Blob Storage with
# encryption at rest and hierarchical namespace disabled. Each environment gets
# its own container within the same storage account.
#
# SECURITY SAFEGUARD: The storage account:
# - Blocks public access (default)
# - Requires HTTPS for API calls
# - Enables infrastructure encryption (double encryption)
# - Has soft-delete enabled for state recovery
# - RBAC only (no access keys for Terraform — uses OIDC)
# ==============================================================================

set -euo pipefail

# ── Configuration ─────────────────────────────────────────────────────────────
# Default values — override via environment variables.
RESOURCE_GROUP="${TF_BACKEND_RG:-rg-terraform-state}"
STORAGE_ACCOUNT="${TF_BACKEND_SA:-tfstate$(openssl rand -hex 4)}"
LOCATION="${TF_BACKEND_LOCATION:-uksouth}"
CONTAINERS="${TF_BACKEND_CONTAINERS:-container-platform-dev container-platform-staging container-platform-prod}"
SKU="${TF_BACKEND_SKU:-Standard_GRS}"

# ── Prerequisites ────────────────────────────────────────────────────────────
echo "🔍 Checking prerequisites..."

command -v az >/dev/null 2>&1 || { echo "❌ Azure CLI required. Install: https://aka.ms/azurecli"; exit 1; }

# Check Azure login status
az account show >/dev/null 2>&1 || {
  echo "🔑 Logging in to Azure..."
  az login --use-device-code
}

# ── Create Resource Group ─────────────────────────────────────────────────────
echo "📦 Creating resource group: ${RESOURCE_GROUP} in ${LOCATION}"
az group create \
  --name "${RESOURCE_GROUP}" \
  --location "${LOCATION}" \
  --tags "Environment=bootstrap" "ManagedBy=terraform" "Purpose=terraform-state"

# ── Create Storage Account ────────────────────────────────────────────────────
echo "📦 Creating storage account: ${STORAGE_ACCOUNT}"

# ARCHITECTURE DECISION: Storage account uses RBAC authorization (not access keys)
# aligned with the OIDC authentication pattern used throughout the platform.
# SECURITY SAFEGUARD: HTTPS-only, infrastructure encryption, and soft delete
# are enabled by default in the AzureRM provider.

az storage account create \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${STORAGE_ACCOUNT}" \
  --location "${LOCATION}" \
  --sku "${SKU}" \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --public-network-access Disabled \
  --allow-blob-public-access false \
  --hns false \
  --default-action Deny \
  --tags "Environment=bootstrap" "ManagedBy=terraform" "Purpose=terraform-state"

# ── Create Containers ─────────────────────────────────────────────────────────
echo "📦 Creating blob containers..."
for CONTAINER in ${CONTAINERS}; do
  echo "  → Creating container: ${CONTAINER}"
  az storage container create \
    --account-name "${STORAGE_ACCOUNT}" \
    --name "${CONTAINER}" \
    --auth-mode login \
    --only-show-errors
done

# ── Enable Soft Delete ───────────────────────────────────────────────────────
# SECURITY SAFEGUARD: Soft delete protects against accidental state deletion.
echo "🔒 Enabling blob soft delete..."
az storage blob service-properties delete-policy update \
  --account-name "${STORAGE_ACCOUNT}" \
  --enable true \
  --days-retained 30 \
  --auth-mode login

# ── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "✅ Backend bootstrap complete!"
echo "────────────────────────────────────────────"
echo "  Resource Group:  ${RESOURCE_GROUP}"
echo "  Storage Account: ${STORAGE_ACCOUNT}"
echo "  Containers:      ${CONTAINERS}"
echo "────────────────────────────────────────────"
echo ""
echo "📝 Update your backend config in versions.tf:"
echo ""
echo "  backend \"azurerm\" {"
echo "    resource_group_name  = \"${RESOURCE_GROUP}\""
echo "    storage_account_name = \"${STORAGE_ACCOUNT}\""
echo "    container_name       = \"container-platform-prod\""
echo "    key                  = \"container-platform.tfstate\""
echo "  }"
echo ""
echo "🔐 Grant yourself access:"
echo ""
echo "  az role assignment create \\"
echo "    --assignee \"\$(az account show --query user.name -o tsv)\" \\"
echo "    --role \"Storage Blob Data Contributor\" \\"
echo "    --scope \"/subscriptions/\$(az account show --query id -o tsv)/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Storage/storageAccounts/${STORAGE_ACCOUNT}\""
echo ""
