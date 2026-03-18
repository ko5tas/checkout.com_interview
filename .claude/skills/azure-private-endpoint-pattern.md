---
name: azure-private-endpoint-pattern
description: Reusable pattern for Azure Private Endpoints with DNS zones — covers storage (4 subresources), Key Vault, and other PaaS services
---

# Azure Private Endpoint + Private DNS Zone Pattern

## Pattern

Every Azure PaaS service accessed privately needs three resources:
1. `azurerm_private_endpoint` — connects the service to your VNet subnet
2. `azurerm_private_dns_zone` — provides DNS resolution (e.g., `privatelink.blob.core.windows.net`)
3. `azurerm_private_dns_zone_virtual_network_link` — links the DNS zone to your VNet

## Storage Account (4 subresources)

Azure Functions need all four storage subresources when `WEBSITE_CONTENTOVERVNET = 1`:

```hcl
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
  for_each      = toset(local.storage_subresources)
  name          = "pe-st-${each.key}-${var.name_prefix}"
  subnet_id     = var.pe_subnet_id
  # ... private_service_connection with subresource_names = [each.key]
  # ... private_dns_zone_group referencing the DNS zone
}
```

## Key Vault

DNS zone: `privatelink.vaultcore.azure.net`, subresource: `vault`

## Common Mistakes

- Forgetting one of the 4 storage subresources — Function App will fail silently
- Not linking the DNS zone to the VNet — private endpoint works but DNS resolution fails
- Using the wrong DNS zone name (e.g., `privatelink.blob.core.windows.net` not `blob.core.windows.net`)
- NSG on the private endpoint subnet must allow 443 from VNet
