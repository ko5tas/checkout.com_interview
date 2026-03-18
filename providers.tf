provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }

  subscription_id = var.subscription_id
}

provider "tls" {}

provider "random" {}

# Remote state backend.
# The key is passed via -backend-config="key=checkout-${ENV}.tfstate" at init time,
# giving each environment its own state file in the same container.
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-uksouth"
    storage_account_name = "sttfstatede4c37db"
    container_name       = "tfstate"
    use_oidc             = true
  }
}
