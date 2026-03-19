resource "random_string" "kv_suffix" {
  length  = 4
  special = false
  upper   = false
}

resource "azurerm_key_vault" "main" {
  # Key Vault names must be globally unique, 3-24 chars, alphanumeric + hyphens
  name                       = "kv-${var.name_prefix}-${random_string.kv_suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  purge_protection_enabled   = true
  soft_delete_retention_days = 7

  # Use Azure RBAC instead of vault-local access policies.
  # This centralises all authN/authZ through Entra ID, enabling:
  # - Conditional Access policies
  # - Privileged Identity Management (PIM) for JIT access
  # - Unified audit logs in Entra ID sign-in/audit blades
  # - Management Group policy enforcement across subscriptions
  enable_rbac_authorization = true

  public_network_access_enabled = true

  network_acls {
    default_action             = "Allow"
    bypass                     = "AzureServices"
    virtual_network_subnet_ids = var.allowed_subnet_ids
  }

  tags = var.tags
}

# --- Private Endpoint ---

resource "azurerm_private_endpoint" "key_vault" {
  name                = "pe-kv-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-kv-${var.name_prefix}"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "kv-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

# --- Private DNS Zone ---

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "link-kv-${var.name_prefix}"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = var.vnet_id
}
