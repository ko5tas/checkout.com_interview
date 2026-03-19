output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "function_app_name" {
  description = "Name of the Function App"
  value       = module.function_app.function_app_name
}

output "apim_gateway_url" {
  description = "API Management gateway URL (internal)"
  value       = module.api_management.gateway_url
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.key_vault.key_vault_name
}

output "smoke_test_function_name" {
  description = "Name of the smoke test Function App"
  value       = module.smoke_test.function_app_name
}

output "smoke_test_resource_group_name" {
  description = "Name of the smoke test resource group"
  value       = module.smoke_test.resource_group_name
}

output "log_analytics_workspace_id" {
  description = "Log Analytics Workspace ID"
  value       = module.observability.log_analytics_workspace_id
}
