# Certificate Renewal Runbook

## cert-manager Troubleshooting Guide

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Monitoring Certificate Status](#2-monitoring-certificate-status)
3. [Common Issues](#3-common-issues)
4. [Manual Renewal](#4-manual-renewal)
5. [Azure DNS Challenge Debugging](#5-azure-dns-challenge-debugging)
6. [Emergency Procedures](#6-emergency-procedures)

---

## 1. Architecture Overview

```
Ingress -> cert-manager -> ClusterIssuer (Let's Encrypt Prod)
                                    |
                                    v
                               Azure DNS Zone
                                    |
                                    v
                              DNS-01 Challenge
                                    |
                                    v
                            ACME Server (Let's Encrypt)
```

- **cert-manager version:** 1.16.x (Helm chart)
- **Issuer:** Let's Encrypt Production (via ClusterIssuer)
- **Challenge type:** DNS-01 (Azure DNS)
- **Renewal window:** 30 days before expiry
- **Certificate duration:** 90 days

## 2. Monitoring Certificate Status

```bash
# List all certificates and their renewal status
kubectl get certificates -A

# Check certificate details (especially Not After)
kubectl describe certificate -n <namespace> <cert-name>

# Check the corresponding secret
kubectl get secret -n <namespace> <cert-name> -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text

# List certificate requests
kubectl get certificaterequest -A

# Check order status
kubectl get orders -A
kubectl get challenges -A
```

## 3. Common Issues

### 3.1 Certificate Not Renewing

**Symptoms:**
- Certificate is within 30 days of expiry
- `kubectl get certificates` shows `Ready: False`

**Diagnosis:**

```bash
# Check certificate conditions
CERT_NAME="<cert-name>"
NAMESPACE="<namespace>"

kubectl get certificate "${CERT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions}' | jq

# Expected: condition type "Ready" with status "True"
# If False, check the message field for details
```

**Common causes:**

| Cause | Symptom | Fix |
|-------|---------|-----|
| DNS zone permissions revoked | Challenge stuck in "pending" | Check Azure DNS zone RBAC |
| Let's Encrypt rate limit | Order shows "invalid" | Wait 1 hour, check rate-limit headers |
| Azure DNS zone deleted | Challenge fails to find zone | Recreate DNS zone and verify |
| cert-manager pod OOMKilled | Order stuck in "processing" | Increase resource limits |

### 3.2 Azure DNS Challenge Failure

```bash
# Identify the challenge
kubectl get challenges -A
kubectl describe challenge -n <namespace> <challenge-name>

# Check if DNS record was created
az network dns record-set txt show \
  --resource-group "${DOMAIN_RG}" \
  --zone-name "${DOMAIN}" \
  --name "_acme-challenge.${SUBDOMAIN}"

# Verify cert-manager has DNS zone contributor access
az role assignment list \
  --assignee "$(kubectl get secret azuredns-config -n cert-manager -o jsonpath='{.data.client-secret}' | base64 -d)" \
  --scope "/subscriptions/<sub>/resourceGroups/${DOMAIN_RG}"
```

### 3.3 Let's Encrypt Rate Limiting

Let's Encrypt production environment has strict rate limits:
- **50 certificates per registered domain per week**
- **300 orders per account per 3 hours**
- **5 failed authorizations per account per hour**

**Check rate limits:**

```bash
# Inspect the ACME order headers
kubectl get order -n <namespace> -o yaml | grep -A5 "replay-nonce"

# If rate limited, switch to staging issuer temporarily
kubectl patch clusterissuer letsencrypt-prod --type=merge \
  -p '{"spec":{"acme":{"server":"https://acme-staging-v02.api.letsencrypt.org/directory"}}}'
```

## 4. Manual Renewal

Force immediate renewal of a certificate:

```bash
# ARCHITECTURE DECISION: Manual renewal is for emergency only.
# cert-manager handles auto-renewal at 30 days before expiry.

# Delete the certificate and its secret (will be recreated)
NAMESPACE="<namespace>"
CERT_NAME="<cert-name>"

kubectl delete certificate "${CERT_NAME}" -n "${NAMESPACE}"
kubectl delete secret "${CERT_NAME}" -n "${NAMESPACE}"
kubectl delete certificaterequest -n "${NAMESPACE}" -l "cert-manager.io/certificate-name=${CERT_NAME}"

# Reapply the certificate manifest (from GitOps)
kubectl apply -f "clusters/production/certificates/${CERT_NAME}.yaml"

# Watch the renewal
kubectl get certificaterequest -n "${NAMESPACE}" -w
```

## 5. Azure DNS Challenge Debugging

### 5.1 Verify DNS Zone Configuration

```bash
# ARCHITECTURE DECISION: cert-manager uses Azure DNS with Workload Identity
# (or service principal) for DNS-01 challenge validation.

# Check cert-manager Azure DNS credentials
kubectl get secret azuredns-config -n cert-manager -o yaml

# Verify the managed identity / service principal has correct permissions
az role assignment list \
  --assignee "<principal-id>" \
  --scope "/subscriptions/<sub>/resourceGroups/${DOMAIN_RG}/providers/Microsoft.Network/dnszones/${DOMAIN}" \
  --query "[].roleDefinitionName"

# Expected: "DNS Zone Contributor"
```

### 5.2 Manual TXT Record Validation

```bash
DOMAIN="secondwave-insurance.com"
SUBDOMAIN="api"
CHALLENGE_VALUE="$(kubectl get challenge -n <ns> <challenge> -o jsonpath='{.spec.key}')"

# Check if the challenge TXT record exists
nslookup -type=TXT "_acme-challenge.${SUBDOMAIN}.${DOMAIN}"

# If record exists but challenge still fails, check propagation
dig TXT "_acme-challenge.${SUBDOMAIN}.${DOMAIN}" @8.8.8.8
```

## 6. Emergency Procedures

### 6.1 Immediate Certificate Revocation

If a private key is compromised:

```bash
# ARCHITECTURE DECISION: Revocation is done via cert-manager, not manually,
# to maintain audit trail.

# Revoke via cert-manager CLI
kubectl annotate certificate <cert-name> -n <namespace> \
  cert-manager.io/issue-temporary-certificate="true"

# Delete the compromised secret
kubectl delete secret <cert-name> -n <namespace>

# cert-manager will reissue automatically
```

### 6.2 Temporary Self-Signed Certificate

If Let's Encrypt is unavailable:

```bash
# Generate self-signed cert using clusterissuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ${CERT_NAME}-emergency
  namespace: ${NAMESPACE}
spec:
  secretName: ${CERT_NAME}-emergency
  duration: 24h
  renewBefore: 12h
  isCA: false
  privateKey:
    algorithm: RSA
    encoding: PKCS1
    size: 2048
  dnsNames:
  - "${SUBDOMAIN}.${DOMAIN}"
  issuerRef:
    name: selfsigned-cluster-issuer
    kind: ClusterIssuer
EOF

# Update ingress to use emergency cert
kubectl patch ingress <ingress-name> -n "${NAMESPACE}" \
  -p "{\"spec\":{\"tls\":[{\"hosts\":[\"${SUBDOMAIN}.${DOMAIN}\"],\"secretName\":\"${CERT_NAME}-emergency\"}]}}"
```

### 6.3 Check cert-manager Logs

```bash
# cert-manager controller logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager --tail=100

# cert-manager webhook logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=webhook --tail=50

# cert-manager cainjector logs
kubectl logs -n cert-manager -l app.kubernetes.io/name=cainjector --tail=50
```

## References

- [cert-manager DNS-01 Azure configuration](https://cert-manager.io/docs/configuration/acme/dns01/azuredns/)
- [Let's Encrypt rate limits](https://letsencrypt.org/docs/rate-limits/)
- [ACME challenge types](https://letsencrypt.org/docs/challenge-types/)
