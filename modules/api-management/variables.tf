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

variable "publisher_name" {
  description = "Publisher name for APIM"
  type        = string
  default     = "Checkout Platform Team"
}

variable "publisher_email" {
  description = "Publisher email for APIM"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID for APIM VNet integration"
  type        = string
}

variable "function_app_hostname" {
  description = "Default hostname of the Function App backend"
  type        = string
}

variable "function_app_id" {
  description = "Resource ID of the Function App"
  type        = string
}

variable "ca_cert_pem" {
  description = "PEM-encoded CA certificate for mTLS validation"
  type        = string
  sensitive   = true
}

variable "allowed_client_cn" {
  description = "Expected CN on client certificates"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
