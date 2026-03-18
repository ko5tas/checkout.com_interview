variable "ca_common_name" {
  description = "Common Name for the Certificate Authority"
  type        = string
  default     = "Checkout Internal CA"
}

variable "client_common_name" {
  description = "Common Name for the client certificate (used for mTLS CN validation)"
  type        = string
}

variable "ca_validity_hours" {
  description = "Validity period of the CA certificate in hours (default: 10 years)"
  type        = number
  default     = 87600
}

variable "client_validity_hours" {
  description = "Validity period of the client certificate in hours (default: 1 year)"
  type        = number
  default     = 8760
}

variable "key_vault_id" {
  description = "ID of the Key Vault to store certificates"
  type        = string
}
