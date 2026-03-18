#!/usr/bin/env bash
#
# Bootstrap Terraform remote state backend.
#
# This script solves the chicken-and-egg problem: Terraform needs a backend
# to store state, but that backend must be provisioned before Terraform runs.
#
# Prerequisites:
#   - Azure CLI installed and authenticated (az login)
#   - Sufficient permissions to create Resource Groups and Storage Accounts
#
# Usage:
#   ./scripts/bootstrap-state.sh
#
# The script will prompt for confirmation before creating resources.
# It uses az login credentials from your shell environment.

set -euo pipefail

LOCATION="${LOCATION:-uksouth}"
RG_NAME="${RG_NAME:-rg-tfstate-${LOCATION}}"
# Storage account names must be globally unique, 3-24 chars, lowercase alphanumeric
SA_NAME="${SA_NAME:-sttfstate$(openssl rand -hex 4)}"
CONTAINER_NAME="${CONTAINER_NAME:-tfstate}"

echo "=== Terraform State Backend Bootstrap ==="
echo ""
echo "This will create:"
echo "  Resource Group:    ${RG_NAME}"
echo "  Storage Account:   ${SA_NAME}"
echo "  Container:         ${CONTAINER_NAME}"
echo "  Location:          ${LOCATION}"
echo ""
read -r -p "Proceed? (y/N) " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo "Creating resource group..."
az group create \
  --name "${RG_NAME}" \
  --location "${LOCATION}" \
  --output none

echo "Creating storage account with versioning and soft-delete..."
az storage account create \
  --name "${SA_NAME}" \
  --resource-group "${RG_NAME}" \
  --location "${LOCATION}" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output none

# Enable blob versioning for state file recovery
az storage account blob-service-properties update \
  --account-name "${SA_NAME}" \
  --resource-group "${RG_NAME}" \
  --enable-versioning true \
  --enable-delete-retention true \
  --delete-retention-days 30 \
  --output none

echo "Creating blob container..."
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${SA_NAME}" \
  --auth-mode login \
  --output none

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "Update your providers.tf backend block with:"
echo ""
echo "  terraform {"
echo "    backend \"azurerm\" {"
echo "      resource_group_name  = \"${RG_NAME}\""
echo "      storage_account_name = \"${SA_NAME}\""
echo "      container_name       = \"${CONTAINER_NAME}\""
echo "      key                  = \"checkout-internal-api.terraform.tfstate\""
echo "      use_oidc             = true"
echo "    }"
echo "  }"
echo ""
echo "Then run: terraform init"
