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

variable "access_policies" {
  description = "List of access policies for Key Vault"
  type = list(object({
    tenant_id               = string
    object_id               = string
    certificate_permissions = list(string)
    key_permissions         = list(string)
    secret_permissions      = list(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
