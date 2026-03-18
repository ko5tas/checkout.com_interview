mock_provider "azurerm" {}
mock_provider "tls" {}

variables {
  ca_common_name     = "Test CA"
  client_common_name = "test-client.internal.checkout.com"
  key_vault_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.KeyVault/vaults/kv-test"
}

run "ca_is_certificate_authority" {
  command = plan

  assert {
    condition     = tls_self_signed_cert.ca.is_ca_certificate == true
    error_message = "CA certificate must have is_ca_certificate = true"
  }
}

run "ca_uses_strong_key" {
  command = plan

  assert {
    condition     = tls_private_key.ca.rsa_bits == 4096
    error_message = "CA should use RSA 4096"
  }
}

run "client_cert_allows_client_auth" {
  command = plan

  assert {
    condition     = contains(tls_locally_signed_cert.client.allowed_uses, "client_auth")
    error_message = "Client certificate must allow client_auth usage"
  }
}
