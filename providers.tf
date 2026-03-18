provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }

  subscription_id = var.subscription_id
}

provider "tls" {}

provider "random" {}

# Remote state backend configuration.
# Uncomment after running scripts/bootstrap-state.sh to provision the backend.
#
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "rg-tfstate-uksouth"
#     storage_account_name = "sttfstate<unique>"
#     container_name       = "tfstate"
#     key                  = "checkout-internal-api.terraform.tfstate"
#     use_oidc             = true  # For GitHub Actions OIDC auth
#   }
# }
