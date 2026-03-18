---
name: mtls-azure-functions
description: mTLS setup on Azure with self-signed certs — APIM gateway validation + Function App defense-in-depth with CN checking
---

# mTLS on Azure Functions with APIM

## Certificate Chain (Terraform tls provider)

1. **CA**: `tls_private_key` (RSA 4096) + `tls_self_signed_cert` (is_ca=true, 10yr validity)
2. **Client**: `tls_private_key` (RSA 2048) + `tls_cert_request` + `tls_locally_signed_cert` (1yr, client_auth)
3. Store as `azurerm_key_vault_secret` (PEM content, not `azurerm_key_vault_certificate` which expects PFX)

## Layer 1: APIM Gateway

APIM Developer tier with `virtual_network_type = "Internal"`:

```xml
<validate-client-certificate
  validate-revocation="false"
  validate-trust="true"
  validate-not-before="true"
  validate-not-after="true">
  <identities>
    <identity subject="api-client.internal.checkout.com"
              certificate-id="internal-ca" />
  </identities>
</validate-client-certificate>
```

**Key**: Consumption tier does NOT support `Internal` VNet mode. Use Developer ($50/mo) or Premium.

## Layer 2: Function App

```hcl
resource "azurerm_linux_function_app" "main" {
  client_certificate_mode = "Required"
}
```

Go code reads `X-ARR-ClientCert` header, base64-decodes, validates:
- CA chain verification with `x509.VerifyOptions`
- CN match against expected value
- This catches compromised services that bypass APIM

## Layer 3: Payload Validation

- `json.Decoder.DisallowUnknownFields()` — strict schema
- Max payload size (1MB)
- Field type/length validation
- Structured error responses with request ID

## Common Mistakes

- APIM Consumption doesn't support VNet injection or mTLS policies
- `azurerm_key_vault_certificate` vs `azurerm_key_vault_secret` — use secret for PEM from tls provider
- Forgetting `WEBSITE_CONTENTOVERVNET = 1` when using VNet integration
