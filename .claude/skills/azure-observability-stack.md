---
name: azure-observability-stack
description: Log Analytics + Application Insights + metric alerts + diagnostic settings pattern for Azure infrastructure
---

# Azure Observability Stack

## Components

1. **Log Analytics Workspace** — centralised log store (`PerGB2018` SKU, 30-day retention)
2. **Application Insights** — connected to Log Analytics (workspace-based, not classic)
3. **Monitor Action Group** — email receivers for alerts
4. **Metric Alerts** — e.g., Http5xx > 0 on Function App
5. **Diagnostic Settings** — streams resource logs to Log Analytics

## Setup Pattern

```hcl
resource "azurerm_log_analytics_workspace" "main" {
  sku               = "PerGB2018"
  retention_in_days = var.log_retention_days  # 30 for dev, 90 for prod
}

resource "azurerm_application_insights" "main" {
  workspace_id     = azurerm_log_analytics_workspace.main.id
  application_type = "other"  # Use "other" for non-.NET apps
}
```

## Diagnostic Settings (per resource)

```hcl
resource "azurerm_monitor_diagnostic_setting" "resource" {
  target_resource_id         = azurerm_xxx.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log { category = "..." }    # Resource-specific log category
  enabled_metric { category = "AllMetrics" }  # Use enabled_metric, not metric (deprecated in v4+)
}
```

Key log categories:
- Function App: `FunctionAppLogs`
- APIM: `GatewayLogs`
- Key Vault: `AuditEvent`

## Circular Dependency Warning

If your observability module needs `function_app_id` for alerts, but function-app needs `app_insights_connection_string`, you have a circular dependency. Solution: put metric alerts in the **root module**, not the observability module.

## Key Insight

Use `enabled_metric` not `metric` — the latter is deprecated in azurerm v4.x and will be removed in v5.
