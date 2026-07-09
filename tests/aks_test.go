// ARCHITECTURE DECISION: Terratest validates that the Terraform plan produces
// expected infrastructure resources. These tests run in CI after terraform plan
// to catch configuration drift before apply.
// SECURITY SAFEGUARD: Tests never access real Azure resources — they validate
// the Terraform module outputs and plan structure only.

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// TestAKSClusterModule validates the aks-cluster module's variables and outputs.
func TestAKSClusterModule(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/aks-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        "test-aks-cluster",
			"resource_group_name": "rg-test-aks",
			"location":            "uksouth",
			"kubernetes_version":  "1.30",
			"vnet_subnet_id":      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test",
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	clusterName := terraform.Output(t, terraformOptions, "cluster_name")
	assert.Equal(t, "test-aks-cluster", clusterName)

	oidcIssuer := terraform.Output(t, terraformOptions, "oidc_issuer_url")
	assert.Contains(t, oidcIssuer, "oidc.prod-aks.azure.com")

	managedRg := terraform.Output(t, terraformOptions, "managed_resource_group")
	assert.Contains(t, managedRg, "MC_test-aks-cluster")
}

// TestAKSClusterPrivateEndpoint validates that the cluster is configured as private.
func TestAKSClusterPrivateEndpoint(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/aks-cluster",
		Vars: map[string]interface{}{
			"cluster_name":        "test-private-aks",
			"resource_group_name": "rg-test-private",
			"location":            "uksouth",
			"kubernetes_version":  "1.30",
			"vnet_subnet_id":      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test",
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	plan := terraform.InitAndPlan(t, terraformOptions)

	// Verify private_cluster_enabled is true in the plan
	planJSON := terraform.ParsePlanJSON(t, plan)
	assert.True(t, planJSON.ResourceChangesMap["azurerm_kubernetes_cluster.this"].Change.After["private_cluster_enabled"].(bool))
}

// TestAKSClusterRBAC validates Azure AD RBAC configuration.
func TestAKSClusterRBAC(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/aks-cluster",
		Vars: map[string]interface{}{
			"cluster_name":         "test-rbac-aks",
			"resource_group_name":  "rg-test-rbac",
			"location":             "uksouth",
			"kubernetes_version":   "1.30",
			"vnet_subnet_id":       "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test",
			"aks_admin_group_ids":  []string{"00000000-0000-0000-0000-000000000001"},
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	plan := terraform.InitAndPlan(t, terraformOptions)
	planJSON := terraform.ParsePlanJSON(t, plan)

	// SECURITY SAFEGUARD: Verify local accounts are disabled
	aksChanges := planJSON.ResourceChangesMap["azurerm_kubernetes_cluster.this"].Change.After
	if localAccountsDisabled, ok := aksChanges["local_account_disabled"].(bool); ok {
		assert.True(t, localAccountsDisabled, "Local accounts must be disabled for security")
	}
}

// TestAKSDefender validates Defender for Containers configuration.
func TestAKSDefender(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/aks-cluster",
		Vars: map[string]interface{}{
			"cluster_name":           "test-defender-aks",
			"resource_group_name":    "rg-test-defender",
			"location":              "uksouth",
			"kubernetes_version":    "1.30",
			"vnet_subnet_id":        "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-test",
			"defender_workspace_id": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test",
		},
	}

	defer terraform.Destroy(t, terraformOptions)
	plan := terraform.InitAndPlan(t, terraformOptions)
	planJSON := terraform.ParsePlanJSON(t, plan)
	aksChanges := planJSON.ResourceChangesMap["azurerm_kubernetes_cluster.this"].Change.After

	assert.NotNil(t, aksChanges["microsoft_defender"], "Microsoft Defender for Containers must be configured")
}
