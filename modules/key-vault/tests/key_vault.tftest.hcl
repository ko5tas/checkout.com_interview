mock_provider "azurerm" {}
mock_provider "random" {}

variables {
  name_prefix         = "test-dev"
  location            = "uksouth"
  resource_group_name = "rg-test-dev"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  subnet_id           = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet"
  vnet_id             = "/subscriptions/00000000/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  tags = {
    environment = "test"
  }
}

run "purge_protection_enabled" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.purge_protection_enabled == true
    error_message = "Key Vault must have purge protection enabled"
  }
}

run "network_acls_deny_by_default" {
  command = plan

  assert {
    condition     = azurerm_key_vault.main.network_acls[0].default_action == "Deny"
    error_message = "Key Vault network ACLs must deny by default"
  }
}

run "private_dns_zone_is_correct" {
  command = plan

  assert {
    condition     = azurerm_private_dns_zone.key_vault.name == "privatelink.vaultcore.azure.net"
    error_message = "Private DNS zone must be privatelink.vaultcore.azure.net"
  }
}
