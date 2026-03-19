---
name: terraform-remote-state-bootstrap
description: Solving the Terraform state backend chicken-and-egg problem with Azure CLI bootstrap scripts
---

# Terraform Remote State Bootstrap (Azure)

## The Problem

Terraform needs a backend to store state, but that backend (Azure Storage Account) must be provisioned before Terraform can run. You can't use Terraform to create its own backend.

## Solution: Azure CLI Bootstrap Script

```bash
#!/usr/bin/env bash
set -euo pipefail

SA_NAME="sttfstate$(openssl rand -hex 4)"  # Globally unique
az group create --name "rg-tfstate-westeurope" --location uksouth
az storage account create \
  --name "${SA_NAME}" \
  --sku Standard_LRS \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false

# Enable versioning for state recovery
az storage account blob-service-properties update \
  --account-name "${SA_NAME}" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30

az storage container create --name tfstate --account-name "${SA_NAME}" --auth-mode login
```

## Authentication Options

| Option | Best For |
|--------|----------|
| `az login` on engineer machine | Initial setup, strict secret policies |
| GitHub OIDC with federated credentials | CI/CD automation |

## Backend Configuration

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-westeurope"
    storage_account_name = "<from bootstrap output>"
    container_name       = "tfstate"
    key                  = "project-name.terraform.tfstate"
    use_oidc             = true  # For GitHub Actions
  }
}
```

## Best Practices

- Enable blob versioning — recover from state corruption
- Enable soft-delete (30 days) — recover from accidental deletion
- Use `Standard_LRS` — state files are small, no need for geo-redundancy
- Storage account name must be globally unique (3-24 chars, lowercase alphanumeric)
- Keep the bootstrap script in `scripts/` and document in README
