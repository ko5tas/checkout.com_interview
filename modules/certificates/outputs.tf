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
  description = "SHA-1 thumbprint of the CA certificate (for APIM policy)"
  # PEM has headers/newlines that base64decode can't handle — strip them first
  value = sha1(base64decode(
    replace(replace(replace(
      tls_self_signed_cert.ca.cert_pem,
      "-----BEGIN CERTIFICATE-----", ""),
      "-----END CERTIFICATE-----", ""),
      "\n", "")
  ))
}

output "client_cert_thumbprint" {
  description = "SHA-1 thumbprint of the client certificate"
  value = sha1(base64decode(
    replace(replace(replace(
      tls_locally_signed_cert.client.cert_pem,
      "-----BEGIN CERTIFICATE-----", ""),
      "-----END CERTIFICATE-----", ""),
      "\n", "")
  ))
}

output "ca_key_vault_certificate_id" {
  description = "Key Vault certificate ID for the CA cert"
  value       = azurerm_key_vault_secret.ca_cert.id
}

output "client_key_vault_certificate_id" {
  description = "Key Vault certificate ID for the client cert"
  value       = azurerm_key_vault_secret.client_cert.id
}
