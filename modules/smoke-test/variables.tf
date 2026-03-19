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

variable "subnet_id" {
  description = "Subnet ID for VNet integration (smoke test subnet)"
  type        = string
}

variable "target_function_hostname" {
  description = "Hostname of the main function app to test (e.g., func-checkout-dev.azurewebsites.net)"
  type        = string
}

variable "key_vault_id" {
  description = "Key Vault resource ID for RBAC"
  type        = string
}

variable "key_vault_uri" {
  description = "Key Vault URI for SDK access"
  type        = string
}

variable "app_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  type        = string
  sensitive   = true
}

variable "app_insights_connection_string" {
  description = "Application Insights connection string"
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
