output "apim_id" {
  description = "Resource ID of the API Management instance"
  value       = azurerm_api_management.main.id
}

output "apim_name" {
  description = "Name of the API Management instance"
  value       = azurerm_api_management.main.name
}

output "gateway_url" {
  description = "Gateway URL of the API Management instance"
  value       = azurerm_api_management.main.gateway_url
}

output "private_ip_addresses" {
  description = "Private IP addresses of APIM (internal VNet mode)"
  value       = azurerm_api_management.main.private_ip_addresses
}

output "ready" {
  description = "Signals that APIM and its internal async processes have stabilised. Depend on this before creating external resources that target APIM (e.g., diagnostic settings)."
  value       = time_sleep.wait_for_apim_internals.id
}
