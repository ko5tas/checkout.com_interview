mock_provider "azurerm" {}

variables {
  name_prefix         = "test-dev"
  location            = "uksouth"
  resource_group_name = "rg-test-dev"
  vnet_address_space  = ["10.0.0.0/16"]
  subnets = {
    function          = "10.0.1.0/24"
    private_endpoints = "10.0.2.0/24"
    apim              = "10.0.3.0/27"
  }
  tags = {
    environment = "test"
  }
}

run "vnet_is_created" {
  command = plan

  assert {
    condition     = azurerm_virtual_network.main.name == "vnet-test-dev"
    error_message = "VNet name should follow naming convention"
  }

  assert {
    condition     = azurerm_virtual_network.main.address_space[0] == "10.0.0.0/16"
    error_message = "VNet should use the provided address space"
  }
}

run "function_subnet_has_delegation" {
  command = plan

  assert {
    condition     = azurerm_subnet.function.delegation[0].service_delegation[0].name == "Microsoft.Web/serverFarms"
    error_message = "Function subnet must have Web/serverFarms delegation"
  }
}

run "nsg_denies_internet" {
  command = plan

  assert {
    condition     = azurerm_network_security_rule.function_deny_internet_inbound.access == "Deny"
    error_message = "Function NSG must deny internet inbound"
  }

  assert {
    condition     = azurerm_network_security_rule.pe_deny_internet_inbound.access == "Deny"
    error_message = "Private endpoints NSG must deny internet inbound"
  }
}
