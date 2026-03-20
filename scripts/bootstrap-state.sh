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

LOCATION="${LOCATION:-westeurope}"
RG_NAME="${RG_NAME:-rg-tfstate-${LOCATION}}"
CONTAINER_NAME="${CONTAINER_NAME:-tfstate}"

echo "=== Terraform State Backend Bootstrap ==="
echo ""

# --- Idempotency: check for existing resources before creating ---

# Check if resource group exists
if az group show --name "${RG_NAME}" --output none 2>/dev/null; then
  echo "Resource group '${RG_NAME}' already exists — reusing."
else
  echo "Creating resource group '${RG_NAME}'..."
  az group create \
    --name "${RG_NAME}" \
    --location "${LOCATION}" \
    --output none
fi

# Check if a state storage account already exists in the resource group
EXISTING_SA=$(az storage account list \
  --resource-group "${RG_NAME}" \
  --query "[?starts_with(name, 'sttfstate')].name | [0]" \
  --output tsv 2>/dev/null || true)

if [[ -n "${EXISTING_SA}" ]]; then
  SA_NAME="${EXISTING_SA}"
  echo "Storage account '${SA_NAME}' already exists — reusing."
else
  # Use a predictable, date-based suffix to avoid hardcoding issues
  SA_NAME="${SA_NAME:-sttfstate$(date +%Y%m)}"
  echo ""
  echo "No existing state storage account found. Will create:"
  echo "  Storage Account:   ${SA_NAME}"
  echo "  Location:          ${LOCATION}"
  echo ""
  read -r -p "Proceed? (y/N) " confirm
  if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi

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
fi

# Check if blob container exists before creating
CONTAINER_EXISTS=$(az storage container exists \
  --name "${CONTAINER_NAME}" \
  --account-name "${SA_NAME}" \
  --auth-mode login \
  --query "exists" \
  --output tsv 2>/dev/null || echo "false")

if [[ "${CONTAINER_EXISTS}" == "true" ]]; then
  echo "Blob container '${CONTAINER_NAME}' already exists — reusing."
else
  echo "Creating blob container '${CONTAINER_NAME}'..."
  az storage container create \
    --name "${CONTAINER_NAME}" \
    --account-name "${SA_NAME}" \
    --auth-mode login \
    --output none
fi

echo ""
echo "=== Bootstrap Complete ==="
echo ""
echo "State backend:"
echo "  Resource Group:    ${RG_NAME}"
echo "  Storage Account:   ${SA_NAME}"
echo "  Container:         ${CONTAINER_NAME}"
echo ""
echo "Update your providers.tf backend block with:"
echo ""
echo "  terraform {"
echo "    backend \"azurerm\" {"
echo "      resource_group_name  = \"${RG_NAME}\""
echo "      storage_account_name = \"${SA_NAME}\""
echo "      container_name       = \"${CONTAINER_NAME}\""
echo "      key                  = \"cko-dev.tfstate\""
echo "      use_oidc             = true"
echo "    }"
echo "  }"
echo ""
echo "Then run: terraform init -backend-config=\"key=cko-<ENV>.tfstate\""
