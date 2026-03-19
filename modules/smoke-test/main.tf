# Lightweight smoke test Function App — lives inside the VNet and tests the
# main API function end-to-end with mTLS. Intentionally minimal: no private
# endpoints, no mTLS on itself (it's internal tooling, not a public API).

resource "random_string" "sa_suffix" {
  length  = 4
  special = false
  upper   = false
}

# --- Storage Account (required by Consumption plan) ---

resource "azurerm_storage_account" "smoke_test" {
  name                            = "stsmoke${replace(var.name_prefix, "-", "")}${random_string.sa_suffix.result}"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  network_rules {
    default_action = "Allow"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }
}

# --- Service Plan ---

resource "azurerm_service_plan" "smoke_test" {
  name                = "asp-smoke-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = "Y1"
  tags                = var.tags
}

# --- Function App ---

resource "azurerm_linux_function_app" "smoke_test" {
  name                                           = "func-smoke-${var.name_prefix}"
  location                                       = var.location
  resource_group_name                            = var.resource_group_name
  service_plan_id                                = azurerm_service_plan.smoke_test.id
  storage_account_name                           = azurerm_storage_account.smoke_test.name
  storage_account_access_key                     = azurerm_storage_account.smoke_test.primary_access_key
  https_only                                     = true
  public_network_access_enabled                  = true
  client_certificate_mode                        = "Optional" # Not a public API — no mTLS needed on itself
  webdeploy_publish_basic_authentication_enabled = true
  ftp_publish_basic_authentication_enabled       = false
  tags                                           = var.tags

  # NOTE: VNet integration (virtual_network_subnet_id) is NOT supported on
  # Consumption plan (Y1/Dynamic). Production would use EP1+ with VNet integration.
  # The smoke test function reaches the main function via its public hostname
  # with mTLS authentication (same as APIM would).

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
    "WEBSITE_CONTENTAZUREFILECONNECTIONSTRING" = "DefaultEndpointsProtocol=https;AccountName=${azurerm_storage_account.smoke_test.name};AccountKey=${azurerm_storage_account.smoke_test.primary_access_key};EndpointSuffix=core.windows.net"
    "WEBSITE_CONTENTSHARE"                     = "func-smoke-${var.name_prefix}-content"
    "FUNCTIONS_WORKER_RUNTIME"                 = "custom"
    "WEBSITE_RUN_FROM_PACKAGE"                 = "1"
    # Smoke test configuration
    "TARGET_FUNCTION_HOSTNAME" = var.target_function_hostname
    "KEY_VAULT_URI"            = var.key_vault_uri
  }
}

# --- Key Vault RBAC for Managed Identity ---
# Needs to read the client certificate and its private key from Key Vault

resource "azurerm_role_assignment" "smoke_kv_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_function_app.smoke_test.identity[0].principal_id
}

resource "azurerm_role_assignment" "smoke_kv_certs" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Certificate User"
  principal_id         = azurerm_linux_function_app.smoke_test.identity[0].principal_id
}
