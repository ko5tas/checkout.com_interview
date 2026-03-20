resource "random_string" "sa_suffix" {
  length  = 4
  special = false
  upper   = false
}

# --- Storage Account ---

resource "azurerm_storage_account" "function" {
  name                     = "stfunc${replace(var.name_prefix, "-", "")}${random_string.sa_suffix.result}"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  min_tls_version          = "TLS1_2"
  # NOTE: Consumption plan with GitHub-hosted runners requires public access for zip deploy.
  # Production with Elastic Premium (EP1+) would use VNet-integrated self-hosted runners
  # and set this to false. Private endpoints still provide in-VNet connectivity.
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  # NOTE: Consumption plan Kudu runs in shared multi-tenant infra that doesn't
  # qualify for AzureServices bypass. Must Allow for zip deploy and file share access.
  # Production with EP1+ plan: set to Deny with VNet rules for the function subnet.
  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "00.01:00:00" # 1 hour max SAS token validity
  }
}

resource "azurerm_storage_account_queue_properties" "function" {
  storage_account_id = azurerm_storage_account.function.id

  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
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
  name                       = "func-${var.name_prefix}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  service_plan_id            = azurerm_service_plan.main.id
  storage_account_name       = azurerm_storage_account.function.name
  storage_account_access_key = azurerm_storage_account.function.primary_access_key
  https_only                 = true
  # NOTE: Must be true for Consumption plan deployed from GitHub-hosted runners.
  # mTLS (client_certificate_mode=Required) still enforces authentication.
  # Production: set false with VNet-integrated EP1+ plan and self-hosted runners.
  public_network_access_enabled                  = true
  client_certificate_mode                        = "Required"
  webdeploy_publish_basic_authentication_enabled = true  # Required for config-zip deploy from GitHub Actions
  ftp_publish_basic_authentication_enabled       = false # FTP not needed
  # NOTE: VNet integration (virtual_network_subnet_id) is NOT supported on
  # Consumption plan (Y1/Dynamic). Requires Elastic Premium (EP1+) or Dedicated.
  # Azure silently rejects the update, causing "Missing Resource Identity" errors.
  # Production would use EP1+ with VNet integration for private outbound traffic.
  tags = var.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      use_custom_runtime = true
    }
  }

  app_settings = {
    "APPINSIGHTS_INSTRUMENTATIONKEY"           = var.app_insights_instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING"    = var.app_insights_connection_string
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.function.name};AccountKey=${azurerm_storage_account.function.primary_access_key};EndpointSuffix=core.windows.net"
    "WEBSITE_CONTENTSHARE"                     = "func-${var.name_prefix}-content"
    "FUNCTIONS_WORKER_RUNTIME"                 = "custom"
    "WEBSITE_RUN_FROM_PACKAGE"                  = "1"
    "WEBSITE_RUN_FROM_PACKAGE"                 = "1"
  }
}

# --- Key Vault RBAC for Managed Identity ---
# Uses Entra ID RBAC instead of vault-local access policies.
# "Key Vault Secrets User" grants Get/List on secrets and certificates.

resource "azurerm_role_assignment" "function_kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}

resource "azurerm_role_assignment" "function_kv_certs" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_linux_function_app.main.identity[0].principal_id
}
