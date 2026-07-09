# ADR-003: Private AKS Cluster (No Public API Server Access)

## Status

Accepted (2026-07-02)

## Context

The SecondWave insurance platform handles sensitive customer data including:
- Personally identifiable information (PII) for policy holders
- Financial transaction data for premium payments
- Underwriting algorithms (intellectual property)

AKS clusters can be deployed as:
1. **Public cluster** — API server has a public endpoint with optional authorized
   IP ranges
2. **Private cluster** — API server has only a private endpoint accessible from
   peered VNets or via private link

The UK Financial Conduct Authority (FCA) and Prudential Regulation Authority (PRA)
require that management planes for systems handling financial data are not directly
accessible from the public internet.

## Decision

**The AKS cluster will be private with the API server accessible only via private
endpoint.**

## Reasons

### 1. FCA/PRA compliance

The FCA's SYSC and the PRA's SS2/21 require:
- Management interfaces must be isolated from public networks
- Access to control planes must be logged and monitored
- Network segmentation between environments

A private AKS cluster satisfies these requirements. The API server is only
reachable over the Azure backbone network via VNet peering or ExpressRoute.

### 2. Reduced attack surface

With a public AKS cluster:
- The API server is discoverable via DNS enumeration
- Authorized IP ranges can be bypassed if a node is compromised (pods can reach
  the public endpoint from inside the cluster)
- DDoS attacks against the public endpoint can impact cluster operations

With a private cluster:
- The API server is not DNS-resolvable from the internet
- No public IP exists to attack
- All requests must traverse the private endpoint, which has NSG rules

### 3. No authorized IP ranges to manage

Authorized IP ranges for public clusters require:
- Tracking all engineer IPs (problematic with remote work and VPN)
- Updating ranges when office IPs change
- Managing jump box IPs in CI/CD (NAT Gateway IPs change)

A private cluster uses VNet integration — any resource in the peered VNet
(including Azure Bastion, DevOps agents on VNet, or on-prem via ExpressRoute)
can access the API server without IP list management.

### 4. GitOps compatibility

A private cluster works well with GitOps because:
- Flux/ArgoCD controllers run inside the cluster and talk to the internal API
- No egress from the cluster to a public API endpoint
- Git repo webhooks push to the cluster via the private endpoint (or via a
  relay in the VNet)

## Consequences

- All kubectl access must go through Azure Bastion, a jump box in the VNet, or
  via Azure CLI with `az aks get-credentials` from a peered resource
- CI/CD runners must be on the VNet (or use self-hosted runners with VNet
  injection)
- Azure DevOps Microsoft-hosted agents cannot directly reach the API server —
  use a scale set agent with VNet integration
- GitHub Actions requires a self-hosted runner or a tunnel (e.g., actions-runner-controller
  on the cluster itself)
- Private DNS zones are created automatically by AKS but may require manual
  configuration if using custom DNS

## Trade-offs

| Aspect | Public Cluster | Private Cluster |
|--------|---------------|-----------------|
| Management access | From anywhere (with IP whitelist) | VNet only via Bastion/jump box |
| Setup complexity | Simple | Medium (networking) |
| CI/CD integration | Direct from GitHub Actions | VNet-injected runners |
| Compliance | Limited | FCA/PRA compliant |
| Cost | No additional | Bastion / jump box costs |
| Operational overhead | IP range management | VNet management |

## Mitigations for CI/CD

To support GitOps with a private cluster:
1. **Self-hosted runners** — Deploy actions-runner-controller or Flux in the
   cluster itself (most secure, simplest)
2. **VNet-injected runners** — Azure DevOps agents on a scale set injected into
   the spoke VNet
3. **Azure Bastion** — For break-glass administrative access with session recording
   and just-in-time (JIT) access

## References

- [Create a private AKS cluster](https://learn.microsoft.com/en-us/azure/aks/private-clusters)
- [FCA SYSC 4.1 - Systems and controls](https://www.handbook.fca.org.uk/handbook/SYSC/4/1.html)
- [PRA SS2/21 - Outsourcing and third party risk management](https://www.bankofengland.co.uk/prudential-regulation/publication/2021/march/outsourcing-and-third-party-risk-management-ss2-21)
- [Azure Bastion for AKS](https://learn.microsoft.com/en-us/azure/bastion/)
