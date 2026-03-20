resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.vnet_address_space
  tags                = var.tags
}

# --- Subnets ---

resource "azurerm_subnet" "function" {
  name                 = "snet-function"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnets["function"]]

  # Service endpoints allow VNet-integrated resources to reach PaaS services
  # over the Azure backbone rather than the public internet.
  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]

  delegation {
    name = "function-delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnets["private_endpoints"]]
}

resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnets["apim"]]
}

resource "azurerm_subnet" "smoke_test" {
  name                 = "snet-smoke-test"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [var.subnets["smoke_test"]]

  # Service endpoints for Key Vault access (fetch client cert for mTLS)
  service_endpoints = [
    "Microsoft.KeyVault",
    "Microsoft.Storage",
  ]

  delegation {
    name = "smoke-test-delegation"

    service_delegation {
      name = "Microsoft.Web/serverFarms"
      actions = [
        "Microsoft.Network/virtualNetworks/subnets/action",
      ]
    }
  }
}

# --- Network Security Groups ---

resource "azurerm_network_security_group" "function" {
  name                = "nsg-function-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "nsg-pe-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# =============================================================================
# NSG Rules: Zero Trust Microsegmentation
# =============================================================================
# Every allowed flow is explicit: source subnet CIDR → destination subnet CIDR
# on specific ports. Default Azure NSG behaviour denies everything not matched.
# No "VirtualNetwork" catch-all — each subnet pair must be explicitly permitted.
#
# Traffic Flow Matrix:
#   APIM subnet        → Function subnet     : 443 (API gateway → backend)
#   Smoke test subnet   → Function subnet     : 443 (mTLS integration test)
#   Smoke test subnet   → PE subnet           : 443 (Key Vault cert fetch)
#   Function subnet     → PE subnet           : 443 (KV + Storage PEs)
#   Function subnet     → Storage (svc endpt) : 443 (AzureWebJobsStorage)
#   Function subnet     → KV (svc endpt)      : 443 (Key Vault secrets)
#   Internet            → APIM subnet         : 443 (client → gateway)
#   ApiManagement       → APIM subnet         : 3443 (Azure control plane)
#   AzureLoadBalancer   → APIM subnet         : 6390 (health probes)
# =============================================================================

# --- Function subnet: Inbound ---

resource "azurerm_network_security_rule" "function_allow_apim_inbound" {
  name                        = "AllowApimInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["apim"]
  destination_address_prefix  = var.subnets["function"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

resource "azurerm_network_security_rule" "function_allow_smoke_test_inbound" {
  name                        = "AllowSmokeTestInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = var.subnets["function"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

resource "azurerm_network_security_rule" "function_deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

# --- Function subnet: Outbound ---

resource "azurerm_network_security_rule" "function_allow_pe_outbound" {
  name                        = "AllowPrivateEndpointsOutbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["function"]
  destination_address_prefix  = var.subnets["private_endpoints"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

resource "azurerm_network_security_rule" "function_allow_storage_svc_endpoint" {
  name                        = "AllowStorageServiceEndpoint"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["function"]
  destination_address_prefix  = "Storage"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

resource "azurerm_network_security_rule" "function_allow_kv_svc_endpoint" {
  name                        = "AllowKeyVaultServiceEndpoint"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["function"]
  destination_address_prefix  = "AzureKeyVault"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

resource "azurerm_network_security_rule" "function_allow_monitor_outbound" {
  name                        = "AllowAzureMonitorOutbound"
  priority                    = 130
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["function"]
  destination_address_prefix  = "AzureMonitor"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.function.name
}

# --- Private Endpoints subnet: Inbound ---

resource "azurerm_network_security_rule" "pe_allow_function_inbound" {
  name                        = "AllowFunctionSubnetInbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["function"]
  destination_address_prefix  = var.subnets["private_endpoints"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "pe_allow_smoke_test_inbound" {
  name                        = "AllowSmokeTestInbound"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = var.subnets["private_endpoints"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

resource "azurerm_network_security_rule" "pe_deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.private_endpoints.name
}

# --- NSG: APIM subnet (required for Internal VNet mode) ---
# See: https://aka.ms/apiminternalvnet

resource "azurerm_network_security_group" "apim" {
  name                = "nsg-apim-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "apim_allow_management" {
  name                        = "AllowAPIMManagement"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3443"
  source_address_prefix       = "ApiManagement"
  destination_address_prefix  = var.subnets["apim"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apim.name
}

resource "azurerm_network_security_rule" "apim_allow_lb" {
  name                        = "AllowAzureLoadBalancer"
  priority                    = 110
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "6390"
  source_address_prefix       = "AzureLoadBalancer"
  destination_address_prefix  = var.subnets["apim"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apim.name
}

resource "azurerm_network_security_rule" "apim_allow_https_from_internet" {
  name                        = "AllowHttpsFromInternet"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = var.subnets["apim"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apim.name
}

resource "azurerm_network_security_rule" "apim_deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apim.name
}

# --- APIM subnet: Outbound ---

resource "azurerm_network_security_rule" "apim_allow_function_outbound" {
  name                        = "AllowFunctionOutbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["apim"]
  destination_address_prefix  = var.subnets["function"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.apim.name
}

# --- NSG: Smoke Test subnet ---

resource "azurerm_network_security_group" "smoke_test" {
  name                = "nsg-smoke-test-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_network_security_rule" "smoke_test_allow_function_outbound" {
  name                        = "AllowFunctionOutbound"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = var.subnets["function"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.smoke_test.name
}

resource "azurerm_network_security_rule" "smoke_test_allow_pe_outbound" {
  name                        = "AllowPrivateEndpointsOutbound"
  priority                    = 110
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = var.subnets["private_endpoints"]
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.smoke_test.name
}

resource "azurerm_network_security_rule" "smoke_test_allow_kv_svc_endpoint" {
  name                        = "AllowKeyVaultServiceEndpoint"
  priority                    = 120
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = "AzureKeyVault"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.smoke_test.name
}

resource "azurerm_network_security_rule" "smoke_test_allow_storage_svc_endpoint" {
  name                        = "AllowStorageServiceEndpoint"
  priority                    = 130
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = var.subnets["smoke_test"]
  destination_address_prefix  = "Storage"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.smoke_test.name
}

resource "azurerm_network_security_rule" "smoke_test_deny_all_inbound" {
  name                        = "DenyAllInbound"
  priority                    = 4096
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group_name
  network_security_group_name = azurerm_network_security_group.smoke_test.name
}

# --- NSG Associations ---

resource "azurerm_subnet_network_security_group_association" "function" {
  subnet_id                 = azurerm_subnet.function.id
  network_security_group_id = azurerm_network_security_group.function.id
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

resource "azurerm_subnet_network_security_group_association" "smoke_test" {
  subnet_id                 = azurerm_subnet.smoke_test.id
  network_security_group_id = azurerm_network_security_group.smoke_test.id
}
