output "function_app_name" {
  description = "Name of the smoke test function app"
  value       = azurerm_linux_function_app.smoke_test.name
}

output "function_app_id" {
  description = "ID of the smoke test function app"
  value       = azurerm_linux_function_app.smoke_test.id
}

output "storage_account_name" {
  description = "Name of the smoke test storage account"
  value       = azurerm_storage_account.smoke_test.name
}
