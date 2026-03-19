output "ca_cert_pem" {
  description = "PEM-encoded CA certificate"
  value       = tls_self_signed_cert.ca.cert_pem
  sensitive   = true
}

output "client_cert_pem" {
  description = "PEM-encoded client certificate"
  value       = tls_locally_signed_cert.client.cert_pem
  sensitive   = true
}

output "client_key_pem" {
  description = "PEM-encoded client private key"
  value       = tls_private_key.client.private_key_pem
  sensitive   = true
}

output "ca_cert_thumbprint" {
  description = "SHA-1 fingerprint of the CA certificate PEM content"
  # Computing a true DER thumbprint requires binary handling that Terraform's
  # string-based functions don't support. This SHA-1 of the PEM text serves
  # as a stable fingerprint for change detection. For APIM mTLS validation,
  # the policy uses issuer CN matching rather than thumbprint pinning.
  value = sha1(tls_self_signed_cert.ca.cert_pem)
}

output "client_cert_thumbprint" {
  description = "SHA-1 fingerprint of the client certificate PEM content"
  value = sha1(tls_locally_signed_cert.client.cert_pem)
}

output "ca_key_vault_certificate_id" {
  description = "Key Vault certificate ID for the CA cert"
  value       = azurerm_key_vault_secret.ca_cert.id
}

output "client_key_vault_certificate_id" {
  description = "Key Vault certificate ID for the client cert"
  value       = azurerm_key_vault_secret.client_cert.id
}
