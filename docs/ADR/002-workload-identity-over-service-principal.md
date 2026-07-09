# ADR-002: Workload Identity over Service Principal for Pod Authentication

## Status

Accepted (2026-07-02)

## Context

Pods running in AKS often need to authenticate to Azure resources (Key Vault,
Storage, Service Bus, Cosmos DB, etc.). Two primary approaches exist:

1. **Service Principal** — Store client ID and client secret as Kubernetes Secrets,
   mount them as environment variables or volumes in pods.
2. **Workload Identity** — Bind a Kubernetes service account to an Azure Managed
   Identity via OIDC federation. Pods request tokens via the Azure Identity SDK
   without any secrets.

The SecondWave insurance platform must meet FCA regulations for secrets management
including:
- Secrets must be rotated regularly
- Secrets must not be stored in etcd (Kubernetes Secrets are base64 encoded, not
  encrypted by default)
- Audit logs must show which workload accessed which Azure resource

## Decision

**We will use Azure Workload Identity for all pod-to-Azure authentication.**

Service principals will only be used for scenario where Workload Identity is not
supported.

## Reasons

### 1. No secrets to rotate or leak

Workload Identity uses OIDC federation — the Kubernetes service account token
is exchanged for an Azure AD token via the token exchange endpoint. There are no
client secrets, no rotation schedules, and no risk of secrets leaking in:
- Git repositories (committed client_secret)
- Environment variable dumps
- CI/CD logs
- Pod crash logs

### 2. Scoped to specific workloads

Each federated identity credential is scoped to a specific namespace and service
account (e.g., `system:serviceaccount:api:api-sa`). A compromised workload in
namespace A cannot steal the identity of namespace B.

### 3. Azure RBAC for permissions

Permissions are assigned via Azure RBAC on the managed identity, not via
role assignments on the service principal. This means:
- Clear audit trail showing which identity accessed what resource
- Permissions are managed through Azure RBAC (same as all other Azure resources)
- Fine-grained: one identity per workload

### 4. Replaces Azure AD Pod Identity

Azure AD Pod Identity (aad-pod-identity) is deprecated and will be retired. It
required running MIC and NMI components on each node, and had known issues with:
- Token caching causing stale credentials
- NMI race conditions on node restart
- ARM template deployment failures

Workload Identity is the supported replacement from both Microsoft and the
community.

## Consequences

- Each workload requires a Kubernetes service account annotated with the managed
  identity client ID
- Azure Identity SDK v1.15+ (or newer) is required in application code
- The cluster must have OIDC issuer enabled (configured in the cluster module)
- Federated credentials must be created for each service account (automated via
  the workload-identity Terraform module)
- Legacy SDKs (Go 1.x, Node v14) may need updates to support token exchange

## Trade-offs

| Aspect | Service Principal | Workload Identity |
|--------|-------------------|-------------------|
| Secret storage | Required (K8s Secret) | None |
| Rotation | Manual rotation needed | Automatic (token-based) |
| Scope | Application-wide | Namespace + SA |m
| Audit | SP-level only | Identity-level |
| Complexity | Low initial | Medium (OIDC setup) |
| Security | Lower (secret leak risk) | Higher (keyless) |
| Legacy support | All SDKs | Token exchange support needed |

## References

- [Azure Workload Identity overview](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)
- [Migrate from Pod Identity to Workload Identity](https://learn.microsoft.com/en-us/azure/aks/migrate-to-workload-identity)
- [OIDC federation with Azure AD](https://learn.microsoft.com/en-us/azure/active-directory/develop/workload-identity-federation)
