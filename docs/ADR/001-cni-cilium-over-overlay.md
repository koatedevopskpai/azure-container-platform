# ADR-001: Azure CNI Powered by Cilium over Azure CNI Overlay

## Status

Accepted (2026-07-02)

## Context

AKS offers two network plugin modes for Azure CNI:
- **Azure CNI Overlay** — Traditional Azure networking with VNet IPs for pods, using
  an overlay network for pod-to-pod communication.
- **Azure CNI Powered by Cilium** — eBPF-based data plane with Cilium for networking,
  observability, and security policies.

We need a networking solution for the SecondWave insurer migration that supports:
1. Multi-tenant workload isolation with Kubernetes Network Policies
2. L7-aware observability and monitoring (HTTP/gRPC metrics per pod pair)
3. High-scale pod density (up to 250 pods/node with Azure CNI Cilium vs 30 in Overlay)
4. Cluster-wide network policy enforcement across namespaces
5. Compliance with UK financial services FCA/PRA regulations for network segmentation

## Decision

**We will use Azure CNI Powered by Cilium.**

## Reasons

### 1. eBPF-based observability (Hubble)

Cilium provides Hubble, a fully distributed networking and security observability
platform built on eBPF. Hubble provides:
- Service dependency graphs at L3-L7
- HTTP/gRPC request rates and latencies per pod pair
- TCP flow metrics with process-level identity
- This is critical for the SecondWave migration's observability requirements.

### 2. Cluster-wide network policies

CiliumClusterWideNetworkPolicy (CCNP) enables policies that span multiple namespaces.
This allows the platform team to enforce:
- Default-deny ingress/egress for all namespaces
- Allow rules for monitoring and DNS in a single policy object
- This is not possible with standard Kubernetes NetworkPolicy (namespace-scoped).

### 3. No sidecar proxies

Unlike Istio or Linkerd, Cilium enforces L7 policies at the kernel level using eBPF.
This means:
- Lower latency overhead (~1-3μs vs ~5-15ms for sidecar proxies)
- No sidecar resource consumption (CPU/memory for every pod)
- Simpler operational model — no sidecar injection or upgrade coordination

### 4. Azure CNI Cilium is managed by AKS

Microsoft and Isovalent collaborate on Azure CNI Cilium. The eBPF data plane is
managed as part of the AKS control plane, eliminating the operational burden of
self-managing Cilium.

### 5. Higher pod density

Azure CNI Cilium supports up to 250 pods per node (with /20 subnet), compared to
30 pods/node for Azure CNI Overlay. This allows denser packing for ML inference
workloads in the SecondWave insurance platform.

## Consequences

- Requires Azure CNI (not kubenet) with a /21 or larger subnet
- eBPF requires Linux kernel 5.10+ (available in AKS node images)
- CiliumNetworkPolicy CRDs must be used instead of standard NetworkPolicy for
  L7 policies
- Team training required on Cilium-specific policy resources
- eBPF kernel operations require privileged containers for the Cilium agent
  (managed by AKS)

## Trade-offs

| Factor | Azure CNI Overlay | Azure CNI Cilium |
|--------|-------------------|-------------------|
| Network policy scope | Namespace only | Cluster-wide |
| L7 awareness | Requires sidecar | eBPF native |
| Pod density | 30 pods/node | 250 pods/node |
| Observability | Basic | Hubble (L3-L7) |
| Operations | Simpler (Azure managed) | More eBPF debugging |
| Latency overhead | Minimal | Sub-millisecond |

## References

- [Azure CNI Powered by Cilium](https://learn.microsoft.com/en-us/azure/aks/azure-cni-powered-by-cilium)
- [Cilium eBPF documentation](https://docs.cilium.io/en/stable/bpf/)
- [Hubble observability](https://docs.cilium.io/en/stable/overview/intro/#hubble)
