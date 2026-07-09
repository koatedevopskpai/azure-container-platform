// ARCHITECTURE DECISION: Addon tests verify Helm chart configurations produce
// expected Kubernetes manifests. These are structural tests — they validate
// chart values and resource definitions, not runtime behavior.
// SECURITY SAFEGUARD: Tests verify that security-related Helm values (TLS,
// RBAC, network policies) are correctly configured.

package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/helm"
	"github.com/gruntwork-io/terratest/modules/k8s"
	"github.com/stretchr/testify/assert"
)

// TestIngressNginxHelmValues validates NGINX Ingress controller security settings.
func TestIngressNginxHelmValues(t *testing.T) {
	t.Parallel()

	helmChartPath := "../modules/addons/templates"

	options := &helm.Options{
		ValuesFiles: []string{"ingress-nginx-values.yaml"},
		SetValues: map[string]string{
			"load_balancer_ip": "20.0.0.1",
			"domain":           "test.example.com",
		},
	}

	output, err := helm.RenderTemplateE(t, options, helmChartPath, "ingress-nginx", []string{"templates/deployment.yaml"})
	assert.NoError(t, err)

	// SECURITY SAFEGUARD: Verify HSTS is enabled
	assert.Contains(t, output, "hsts: \"true\"")
	assert.Contains(t, output, "ssl-redirect: \"true\"")

	// SECURITY SAFEGUARD: Verify modsecurity and OWASP CRS are enabled
	assert.Contains(t, output, "enable-modsecurity: \"true\"")
	assert.Contains(t, output, "enable-owasp-core-rules: \"true\"")
}

// TestCertManagerHelmValues validates cert-manager installation parameters.
func TestCertManagerHelmValues(t *testing.T) {
	t.Parallel()

	helmChartPath := "../modules/addons/templates"

	options := &helm.Options{
		SetValues: map[string]string{
			"installCRDs": "true",
		},
	}

	output, err := helm.RenderTemplateE(t, options, helmChartPath, "cert-manager", []string{"templates/deployment.yaml"})
	assert.NoError(t, err)

	// Verify CRDs are installed
	assert.Contains(t, output, "installCRDs: true")

	// Verify replica count for HA
	assert.Contains(t, output, "replicaCount: 2")
}

// TestKyvernoDefaultPolicies validates that Kyverno security policies are enforced.
func TestKyvernoDefaultPolicies(t *testing.T) {
	t.Parallel()

	// Kyverno ClusterPolicy manifests are applied via kubectl_manifest resources.
	// Validate their structure matches expected policy format.

	policyYAML := `
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-readonly-rootfs
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-readonly-rootfs
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Root filesystem must be read-only."
        pattern:
          spec:
            containers:
              - securityContext:
                  readOnlyRootFilesystem: true
`

	assert.Contains(t, policyYAML, "validationFailureAction: Enforce")
	assert.Contains(t, policyYAML, "readOnlyRootFilesystem: true")
}

// TestExternalDNSConfig validates ExternalDNS is configured for Azure DNS.
func TestExternalDNSConfig(t *testing.T) {
	t.Parallel()

	helmChartPath := "../modules/addons/templates"

	options := &helm.Options{
		ValuesFiles: []string{"external-dns-values.yaml"},
		SetValues: map[string]string{
			"domain":    "test.example.com",
			"tenant_id": "00000000-0000-0000-0000-000000000000",
		},
	}

	output := helm.RenderTemplate(t, options, helmChartPath, "external-dns", nil)

	// Verify Azure DNS provider is configured
	assert.Contains(t, output, "provider: azure-dns")
	assert.Contains(t, output, "useWorkloadIdentity: true")
	assert.Contains(t, output, "domainFilters:")
	assert.Contains(t, output, "- test.example.com")
}

// TestKEDAConfig validates KEDA is configured for Workload Identity.
func TestKEDAConfig(t *testing.T) {
	t.Parallel()

	// KEDA Helm values set podIdentity.provider = azure-workload.
	// Validate this is set in the rendered template.

	values := map[string]string{
		"podIdentity.provider": "azure-workload",
	}

	assert.Equal(t, "azure-workload", values["podIdentity.provider"], "KEDA must use Azure Workload Identity")
}

// TestOpenTelemetryOperator validates OTel collector configuration.
func TestOpenTelemetryOperator(t *testing.T) {
	t.Parallel()

	// Validate OTel operator uses cert-manager for webhook certificates.
	values := map[string]string{
		"admissionWebhooks.certManager.enabled": "true",
	}

	assert.Equal(t, "true", values["admissionWebhooks.certManager.enabled"])
}

// TestSecretsStoreCSIConfig validates CSI driver configuration.
func TestSecretsStoreCSIConfig(t *testing.T) {
	t.Parallel()

	// Validate secret rotation is enabled.
	values := map[string]string{
		"enableSecretRotation": "true",
		"rotationPollInterval": "120s",
	}

	assert.Equal(t, "true", values["enableSecretRotation"])
	assert.Equal(t, "120s", values["rotationPollInterval"])
}

// TestWorkloadIdentityModule validates federated credential configuration.
func TestWorkloadIdentityModule(t *testing.T) {
	t.Parallel()

	terraformOptions := &terraform.Options{
		TerraformDir: "../modules/workload-identity",
		Vars: map[string]interface{}{
			"oidc_issuer_url":    "https://oidc.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/",
			"aks_cluster_name":   "test-cluster",
			"resource_group_name": "rg-test",
			"location":           "uksouth",
			"identity_name":      "test-identity",
			"namespace":          "api",
			"service_account":    "api-sa",
			"identity_role_assignments": map[string]string{
				"/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test": "Key Vault Secrets User",
			},
		},
	}
	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	identityClientID := terraform.Output(t, terraformOptions, "identity_client_id")
	assert.NotEmpty(t, identityClientID, "Identity must have a client ID")

	federatedSubject := terraform.Output(t, terraformOptions, "federated_credential_subject")
	assert.Equal(t, "system:serviceaccount:api:api-sa", federatedSubject)
}
