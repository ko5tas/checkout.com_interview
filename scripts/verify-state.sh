#!/usr/bin/env bash
#
# Pre-deploy state verification: ensures Azure resources and Terraform state
# are in sync before running terraform apply. Prevents the most common
# deployment failure: stale state causing "already exists" or "404" errors.
#
# Usage:
#   STATE_RG=rg-tfstate-westeurope STATE_SA=sttfstate964b29c3 \
#   STATE_KEY=checkout-dev.tfstate TARGET_RG=rg-checkout-dev \
#   ./scripts/verify-state.sh
#
set -euo pipefail

STATE_RG="${STATE_RG:?STATE_RG is required}"
STATE_SA="${STATE_SA:?STATE_SA is required}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
STATE_KEY="${STATE_KEY:?STATE_KEY is required}"
TARGET_RG="${TARGET_RG:?TARGET_RG is required}"

echo "=== Terraform Pre-Deploy State Verification ==="
echo "  State backend: ${STATE_SA}/${STATE_CONTAINER}/${STATE_KEY}"
echo "  Target RG:     ${TARGET_RG}"
echo ""

# 1. Check state backend exists
if ! az group exists --name "${STATE_RG}" 2>/dev/null | grep -q true; then
  echo "FATAL: State backend RG '${STATE_RG}' does not exist."
  echo "ACTION: Run scripts/bootstrap-state.sh first."
  exit 1
fi

echo "✓ State backend RG '${STATE_RG}' exists"

# 2. Check state blob status
STATE_SIZE=$(az storage blob show \
  --account-name "${STATE_SA}" \
  --container-name "${STATE_CONTAINER}" \
  --name "${STATE_KEY}" \
  --query "properties.contentLength" \
  --output tsv 2>/dev/null || echo "0")

if [[ "${STATE_SIZE}" -gt 0 ]]; then
  echo "✓ State blob exists (${STATE_SIZE} bytes)"
else
  echo "○ State blob is empty or missing"
fi

# 3. Check target resource group
RG_EXISTS=$(az group exists --name "${TARGET_RG}" 2>/dev/null)

if [[ "${RG_EXISTS}" == "true" ]]; then
  echo "✓ Target RG '${TARGET_RG}' exists in Azure"
else
  echo "○ Target RG '${TARGET_RG}' does not exist in Azure"
fi

# 4. Decision matrix
echo ""
if [[ "${RG_EXISTS}" == "true" && "${STATE_SIZE}" == "0" ]]; then
  echo "⚠ CONFLICT: Azure RG exists but state is empty/missing."
  echo "  This means resources were created but state was lost."
  echo "  Deleting orphaned RG '${TARGET_RG}'..."
  az group delete --name "${TARGET_RG}" --yes --no-wait
  echo "  Waiting for RG deletion (this may take 10+ minutes for APIM)..."
  while az group exists --name "${TARGET_RG}" 2>/dev/null | grep -q true; do
    sleep 30
    echo "  Still waiting..."
  done
  echo "  ✓ RG deleted. Safe to apply."

elif [[ "${RG_EXISTS}" == "false" && "${STATE_SIZE}" -gt 0 ]]; then
  echo "⚠ CONFLICT: State blob has content but Azure RG is gone."
  echo "  This means resources were destroyed but state wasn't cleaned."
  echo "  Deleting stale state blob..."
  az storage blob delete \
    --account-name "${STATE_SA}" \
    --container-name "${STATE_CONTAINER}" \
    --name "${STATE_KEY}" \
    --auth-mode key \
    --output none 2>/dev/null || \
  az storage blob delete \
    --account-name "${STATE_SA}" \
    --container-name "${STATE_CONTAINER}" \
    --name "${STATE_KEY}" \
    --auth-mode login \
    --output none
  echo "  ✓ State blob deleted. Safe to apply."

elif [[ "${RG_EXISTS}" == "false" && "${STATE_SIZE}" == "0" ]]; then
  echo "✓ Clean slate — no RG, no state. Safe to apply."

else
  echo "✓ RG and state both exist. Normal apply."
fi

# 5. Purge soft-deleted Key Vaults that match our naming pattern.
# Azure Key Vault soft-delete retains names for 7-90 days, blocking
# re-creation with the same name. Purge any matching vaults preemptively.
echo ""
echo "--- Checking for soft-deleted Key Vaults ---"
NAME_PREFIX="${TARGET_RG#rg-}"  # e.g., rg-checkout-dev → checkout-dev
DELETED_KVS=$(az keyvault list-deleted \
  --query "[?contains(name,'${NAME_PREFIX}')].name" \
  -o tsv 2>/dev/null || true)

if [[ -n "${DELETED_KVS}" ]]; then
  echo "⚠ Found soft-deleted Key Vaults matching '${NAME_PREFIX}':"
  for KV in ${DELETED_KVS}; do
    echo "  Purging ${KV}..."
    az keyvault purge --name "${KV}" --no-wait 2>/dev/null || true
  done
  echo "  ✓ Purge initiated (runs in background)."
else
  echo "✓ No soft-deleted Key Vaults to purge."
fi

echo ""
echo "=== Verification Complete ==="
