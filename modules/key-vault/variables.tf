variable "name_prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
}

variable "tenant_id" {
  description = "Azure AD tenant ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for the private endpoint"
  type        = string
}

variable "vnet_id" {
  description = "VNet ID for private DNS zone link"
  type        = string
}

variable "allowed_subnet_ids" {
  description = "Subnet IDs allowed to access Key Vault via network ACLs"
  type        = list(string)
  default     = []
}

# access_policies removed — Key Vault now uses Azure RBAC (enable_rbac_authorization = true).
# Role assignments are managed via azurerm_role_assignment in the calling module.

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
