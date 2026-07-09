# AKS Cluster Recovery Runbook

**RTO Target:** 4 hours  
**RPO Target:** 1 hour (Terraform state) / 0 hours (GitOps)

---

## Table of Contents

1. [Failure Scenarios](#1-failure-scenarios)
2. [Recovery from Terraform State Loss](#2-recovery-from-terraform-state-loss)
3. [Recovery from Cluster Failure](#3-recovery-from-cluster-failure)
4. [Recovery from Regional Outage](#4-recovery-from-regional-outage)
5. [Data Recovery](#5-data-recovery)
6. [Post-Recovery Verification](#6-post-recovery-verification)

---

## 1. Failure Scenarios

| Scenario | Impact | Recovery Strategy |
|----------|--------|-------------------|
| Terraform state corruption | Cannot manage cluster via IaC | Restore state from blob backup |
| Control plane failure | API server down | AKS auto-recovery (SLA 99.95%) |
| Node pool failure | Workloads unschedulable | `terraform taint` + `apply` or node image upgrade |
| Regional outage | Full cluster loss | Deploy to paired region |
| Accidental resource deletion | Partial/full cluster missing | `terraform apply` from state or restore |
| etcd corruption | Cluster state inconsistent | AKS support ticket for restore |

## 2. Recovery from Terraform State Loss

### 2.1 Restore from Azure Blob Backup

```bash
# ARCHITECTURE DECISION: Terraform state is stored in Azure Blob Storage with
# soft delete enabled. State can be restored from soft-deleted blobs within
# 30 days of deletion.

# Identify the storage account
STORAGE_ACCOUNT="<terraform-state-sa>"
CONTAINER="container-platform-prod"

# List soft-deleted blobs
az storage blob list \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --include d \
  --auth-mode login \
  --query "[?deleted].{name:name, deleted:deleted, remainingRetentionDays:remainingRetentionDays}"

# Restore the soft-deleted blob
az storage blob undelete \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --name "container-platform.tfstate" \
  --auth-mode login
```

### 2.2 Import Existing Resources

If state is unrecoverable, import existing Azure resources into new state:

```bash
# SECURITY SAFEGUARD: Run terraform plan first with -generate-config-out
# to verify the import before making changes.

# Import AKS cluster
terraform import module.aks-cluster.azurerm_kubernetes_cluster.this \
  /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>

# Import node pools
for POOL in $(az aks nodepool list --cluster-name <cluster> -g <rg> --query "[].name" -o tsv); do
  terraform import "module.aks-node-pools.azurerm_kubernetes_cluster_node_pool.this[\"${POOL}\"]" \
    /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>/agentPools/${POOL}
done
```

## 3. Recovery from Cluster Failure

### 3.1 Control Plane Failure

AKS manages control plane availability automatically. If the API server is
unreachable:

```bash
# Check control plane status
az aks show -g <rg> -n <cluster> --query "provisioningState"

# If provisioningState is "Failed", escalate to Microsoft support
az aks show -g <rg> -n <cluster> --query "powerState.code"

# Force AKS to recover the control plane (rarely needed)
az aks update -g <rg> -n <cluster> --no-wait
```

### 3.2 Node Pool Failure

```bash
# Identify unhealthy nodes
kubectl get nodes -o wide
kubectl describe node <unhealthy-node>

# Force node replacement via cordon + drain + delete
kubectl cordon <unhealthy-node>
kubectl drain <unhealthy-node> --ignore-daemonsets --delete-emptydir-data

# Delete the node (AKS will recreate it)
az aks nodepool delete -g <rg> --cluster-name <cluster> -n <pool-name> --no-wait
```

### 3.3 Full Cluster Redeployment

```bash
# SECURITY SAFEGUARD: Ensure state is backed up before destroy
az storage blob download \
  --account-name "${STORAGE_ACCOUNT}" \
  --container-name "${CONTAINER}" \
  --name "container-platform.tfstate" \
  --file "backup.tfstate.$(date +%Y%m%d%H%M%S)"

# Rebuild cluster from Terraform
terraform plan -out=tfplan
terraform apply tfplan

# Verify GitOps sync
if [ "${GITOPS_TOOL}" = "argocd" ]; then
  argocd app list
elif [ "${GITOPS_TOOL}" = "flux" ]; then
  flux get kustomizations --all-namespaces
fi
```

## 4. Recovery from Regional Outage

### 4.1 Prerequisites

Before a regional failure occurs, ensure:
- Terraform state is accessible from paired region
- Container images are replicated to ACR in paired region
- GitOps repo is accessible from paired region
- DNS failover is configured (Azure Traffic Manager or Front Door)

### 4.2 Deploy to Secondary Region

```bash
# ARCHITECTURE DECISION: Multi-region deployment uses a separate Terraform
# workspace and state file per region.

# Switch to DR workspace
terraform workspace new dr-uksouth
terraform workspace select dr-uksouth

# Apply with DR-specific tfvars
terraform apply -var-file="terraform.dr.tfvars"

# Verify Workload Identity federation in DR region
az aks show -g <rg> -n <cluster> --query "oidcIssuerProfile.issuerUrl"
```

### 4.3 Data Recovery

For stateful workloads:
- **Azure Database for PostgreSQL/MySQL**: Geo-replicated replicas
- **Azure Cosmos DB**: Multi-region writes enabled
- **Azure Storage**: GRS or GZRS redundancy
- **Azure Key Vault**: Separate vault in DR region with key replication

## 5. Data Recovery

### 5.1 Key Vault Secrets

```bash
# ARCHITECTURE DECISION: Secrets are stored in AKV and mounted via Secrets Store
# CSI Driver. No secrets are stored in etcd.

# Verify KV is accessible from DR cluster
kubectl get secretproviderclass -A
kubectl describe secretproviderclass -n <namespace> <spc-name>
```

### 5.2 Persistent Volumes

```bash
# List PVCs requiring manual recovery
kubectl get pvc -A

# For Azure Disk: restore from snapshots
az disk show --ids <disk-id> --query "diskState"

# For Azure Files: restore from soft-deleted shares
az storage share-rm list-deleted \
  --storage-account <sa> \
  --query "[].{name:name, deletedTime:deletedTime}"
```

## 6. Post-Recovery Verification

```markdown
### Verification Checklist

- [ ] AKS API server accessible via private endpoint
  ```bash
  az aks show -g <rg> -n <cluster> --query "privateFqdn"
  ```

- [ ] Node pools healthy with correct count
  ```bash
  kubectl get nodes
  ```

- [ ] All namespaces present
  ```bash
  kubectl get ns | grep -E "argocd|flux-system|ingress-nginx|cert-manager|kyverno|keda"
  ```

- [ ] GitOps sync healthy
  ```bash
  argocd app list -o json | jq '.[].status.sync.status'
  ```

- [ ] Workload Identity operational
  ```bash
  az aks show -g <rg> -n <cluster> --query "oidcIssuerProfile.issuerUrl"
  ```

- [ ] Ingress endpoints respond
  ```bash
  curl -k -I https://app.${DOMAIN}/healthz
  ```

- [ ] Certificates valid
  ```bash
  openssl s_client -connect app.${DOMAIN}:443 -servername app.${DOMAIN} < /dev/null 2>/dev/null | openssl x509 -noout -dates
  ```

- [ ] KEDA ScaledObjects active
  ```bash
  kubectl get scaledobject -A
  ```

- [ ] Microsoft Defender alerts reviewed
  ```bash
  az security alert list --query "[?severity=='High']"
  ```

- [ ] Terraform state validated
  ```bash
  terraform plan -detailed-exitcode
  ```
```

## References

- [AKS disaster recovery guidance](https://learn.microsoft.com/en-us/azure/aks/disaster-recovery)
- [Azure paired regions](https://learn.microsoft.com/en-us/azure/reliability/cross-region-replication-azure)
- [Backup AKS workloads using Velero](https://velero.io/docs/v1.14/locations/)
