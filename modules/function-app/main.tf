resource "random_string" "sa_suffix" {
  length  = 4
  special = false
  upper   = false
}

# --- Storage Account ---

resource "azurerm_storage_account" "function" {
  name                          = "stfunc${replace(var.name_prefix, "-", "")}${random_string.sa_suffix.result}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  account_tier                  = "Standard"
  account_replication_type      = "LRS"
  min_tls_version               = "TLS1_2"
  public_network_access_enabled = false
  tags                          = var.tags
}

# --- Storage Private Endpoints ---

locals {
  storage_subresources = ["blob", "table", "queue", "file"]
  storage_dns_zones = {
    blob  = "privatelink.blob.core.windows.net"
    table = "privatelink.table.core.windows.net"
    queue = "privatelink.queue.core.windows.net"
    file  = "privatelink.file.core.windows.net"
  }
}

resource "azurerm_private_endpoint" "storage" {
  for_each = toset(local.storage_subresources)

  name                = "pe-st-${each.key}-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-st-${each.key}-${var.name_prefix}"
    private_connection_resource_id = azurerm_storage_account.function.id
    subresource_names              = [each.key]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "st-${each.key}-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage[each.key].id]
  }
}

resource "azurerm_private_dns_zone" "storage" {
  for_each = local.storage_dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage" {
  for_each = local.storage_dns_zones

  name                  = "link-st-${each.key}-${var.name_prefix}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.storage[each.key].name
  virtual_network_id    = var.vnet_id
}

# --- Service Plan ---

resource "azurerm_service_plan" "main" {
  name                = "asp-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "Y1" # Consumption plan
  tags                = var.tags
}

# --- Function App ---

resource "azurerm_linux_function_app" "main" {
  name                          = "func-${var.name_prefix}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  service_plan_id               = azurerm_service_plan.main.id
  storage_account_name          = azurerm_storage_account.function.name
  storage_account_access_key    = azurerm_storage_account.function.primary_access_key
  virtual_network_subnet_id     = var.function_subnet_id
  public_network_access_enabled = false
  client_certificate_mode       = "Required"
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      use_custom_runtime = true
    }

    vnet_route_all_enabled = true
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = var.app_insights_instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = var.app_insights_connection_string
    "WEBSITE_CONTENTOVERVNET"               = "1"
    "FUNCTIONS_WORKER_RUNTIME"              = "custom"
  }
}

# --- Key Vault Access for Managed Identity ---

resource "azurerm_key_vault_access_policy" "function_app" {
  key_vault_id = var.key_vault_id
  tenant_id    = azurerm_linux_function_app.main.identity[0].tenant_id
  object_id    = azurerm_linux_function_app.main.identity[0].principal_id

  secret_permissions = [
    "Get",
    "List",
  ]

  certificate_permissions = [
    "Get",
    "List",
  ]
}
