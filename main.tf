resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name_prefix}"
  location = var.location
  tags     = local.common_tags
}

# --- Networking ---

module "networking" {
  source = "./modules/networking"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  vnet_address_space  = var.vnet_address_space
  subnets             = local.subnets
  tags                = local.common_tags
}

# --- Observability ---

module "observability" {
  source = "./modules/observability"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  alert_email         = var.alert_email
  tags                = local.common_tags
}

# --- Key Vault ---

module "key_vault" {
  source = "./modules/key-vault"

  name_prefix         = local.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  subnet_id           = module.networking.subnet_ids["private_endpoints"]
  vnet_id             = module.networking.vnet_id
  allowed_subnet_ids  = [module.networking.subnet_ids["function"], module.networking.subnet_ids["smoke_test"]]
  tags                = local.common_tags

}

# Key Vault RBAC: CI/CD service principal gets admin access for cert/secret management
resource "azurerm_role_assignment" "kv_cicd_admin" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# --- Certificates ---

module "certificates" {
  source = "./modules/certificates"

  client_common_name = var.allowed_client_cn
  key_vault_id       = module.key_vault.key_vault_id

  depends_on = [module.key_vault]
}

# --- Function App ---

module "function_app" {
  source = "./modules/function-app"

  name_prefix                      = local.name_prefix
  location                         = var.location
  resource_group_name              = azurerm_resource_group.main.name
  pe_subnet_id                     = module.networking.subnet_ids["private_endpoints"]
  vnet_id                          = module.networking.vnet_id
  app_insights_instrumentation_key = module.observability.app_insights_instrumentation_key
  app_insights_connection_string   = module.observability.app_insights_connection_string
  key_vault_id                     = module.key_vault.key_vault_id
  tags                             = local.common_tags
}

# --- API Management ---

module "api_management" {
  source = "./modules/api-management"

  name_prefix           = local.name_prefix
  location              = var.location
  resource_group_name   = azurerm_resource_group.main.name
  publisher_email       = var.alert_email
  subnet_id             = module.networking.subnet_ids["apim"]
  function_app_hostname = module.function_app.function_app_default_hostname
  ca_cert_pem           = module.certificates.ca_cert_pem
  allowed_client_cn     = var.allowed_client_cn
  tags                  = local.common_tags
}

# --- Smoke Test Function ---
# VNet-internal function that validates the main API end-to-end with mTLS.
# Triggered by CI via ARM control plane (az functionapp function call).

module "smoke_test" {
  source = "./modules/smoke-test"

  name_prefix                      = local.name_prefix
  location                         = var.location
  resource_group_name              = azurerm_resource_group.main.name
  subnet_id                        = module.networking.subnet_ids["smoke_test"]
  target_function_hostname         = module.function_app.function_app_default_hostname
  key_vault_id                     = module.key_vault.key_vault_id
  key_vault_uri                    = module.key_vault.key_vault_uri
  app_insights_instrumentation_key = module.observability.app_insights_instrumentation_key
  app_insights_connection_string   = module.observability.app_insights_connection_string
  tags                             = local.common_tags
}

# --- Alerts (in root to avoid circular deps between observability and function-app) ---

resource "azurerm_monitor_metric_alert" "function_5xx" {
  name                = "alert-func-5xx-${local.name_prefix}"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [module.function_app.function_app_id]
  description         = "Triggered when Function App returns HTTP 5xx errors"
  severity            = 1
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Web/sites"
    metric_name      = "Http5xx"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  action {
    action_group_id = module.observability.action_group_id
  }
}

# --- Data Sources ---

data "azurerm_client_config" "current" {}
