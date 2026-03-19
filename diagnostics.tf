# Diagnostic settings — streams resource logs to Log Analytics (stretch goal)

resource "azurerm_monitor_diagnostic_setting" "function_app" {
  name                       = "diag-func-${local.name_prefix}"
  target_resource_id         = module.function_app.function_app_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  enabled_log {
    category = "FunctionAppLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# depends_on chains through module.api_management.ready which waits for
# time_sleep after APIM provisioning — prevents "already exists" race condition.
resource "azurerm_monitor_diagnostic_setting" "apim" {
  depends_on                 = [module.api_management]
  name                       = "diag-apim-${local.name_prefix}"
  target_resource_id         = module.api_management.apim_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  enabled_log {
    category = "GatewayLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-${local.name_prefix}"
  target_resource_id         = module.key_vault.key_vault_id
  log_analytics_workspace_id = module.observability.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
