output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value = {
    function          = azurerm_subnet.function.id
    private_endpoints = azurerm_subnet.private_endpoints.id
    apim              = azurerm_subnet.apim.id
  }
}

output "nsg_ids" {
  description = "Map of NSG name to NSG ID"
  value = {
    function          = azurerm_network_security_group.function.id
    private_endpoints = azurerm_network_security_group.private_endpoints.id
  }
}
