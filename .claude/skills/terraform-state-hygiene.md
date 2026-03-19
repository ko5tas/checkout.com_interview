# Terraform State Hygiene: Preventing Stale State Failures

## Problem

Terraform deployments fail catastrophically when Azure resource state and Terraform state file are out of sync. This happens most often after:
- A partial `terraform apply` that creates some resources then fails
- A manual resource group deletion without cleaning the state blob
- A budget-guard or scheduled destroy that cleans Azure but not state (or vice versa)
- Re-bootstrapping the state backend without cleaning orphaned Azure resources

Each failed cycle wastes 30-60 minutes (APIM provisioning alone is 30-45 min) and burns real money.

## Root Cause

Terraform assumes its state file is the source of truth. When reality diverges:
- **Resources exist in Azure but not in state** → `"already exists"` errors on apply
- **Resources exist in state but not in Azure** → `404 Not Found` errors on apply
- **State backend is gone** → `"Failed to get existing workspaces"` on init

## Pre-Deploy Verification Script

Run this BEFORE every `terraform apply` — in CI or locally:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
STATE_RG="${STATE_RG:-rg-tfstate-uksouth}"
STATE_SA="${STATE_SA:-sttfstatede4c37db}"
STATE_CONTAINER="${STATE_CONTAINER:-tfstate}"
STATE_KEY="${STATE_KEY:-checkout-dev.tfstate}"
TARGET_RG="${TARGET_RG:-rg-checkout-dev}"

echo "=== Terraform Pre-Deploy State Verification ==="

# 1. Check state backend exists
if ! az group exists --name "$STATE_RG" 2>/dev/null | grep -q true; then
  echo "FATAL: State backend RG '$STATE_RG' does not exist."
  echo "ACTION: Run scripts/bootstrap-state.sh first."
  exit 1
fi

# 2. Check state blob status
STATE_SIZE=$(az storage blob show \
  --account-name "$STATE_SA" \
  --container-name "$STATE_CONTAINER" \
  --name "$STATE_KEY" \
  --query "properties.contentLength" \
  --output tsv 2>/dev/null || echo "0")

# 3. Check target resource group
RG_EXISTS=$(az group exists --name "$TARGET_RG" 2>/dev/null)

# 4. Decision matrix
if [[ "$RG_EXISTS" == "true" && "$STATE_SIZE" == "0" ]]; then
  echo "CONFLICT: Azure RG exists but state is empty."
  echo "ACTION: Deleting orphaned RG '$TARGET_RG'..."
  az group delete --name "$TARGET_RG" --yes --no-wait
  echo "Waiting for RG deletion..."
  az group wait --name "$TARGET_RG" --deleted --timeout 600 2>/dev/null || true
  echo "RG deleted. Safe to apply."

elif [[ "$RG_EXISTS" == "false" && "$STATE_SIZE" -gt 0 ]]; then
  echo "CONFLICT: State blob has content but Azure RG is gone."
  echo "ACTION: Deleting stale state blob..."
  az storage blob delete \
    --account-name "$STATE_SA" \
    --container-name "$STATE_CONTAINER" \
    --name "$STATE_KEY" \
    --auth-mode key
  echo "State blob deleted. Safe to apply."

elif [[ "$RG_EXISTS" == "false" && "$STATE_SIZE" == "0" ]]; then
  echo "OK: Clean slate — no RG, no state. Safe to apply."

elif [[ "$RG_EXISTS" == "true" && "$STATE_SIZE" -gt 0 ]]; then
  echo "OK: RG and state both exist. Normal apply."

fi

echo "=== Verification Complete ==="
```

## CI Integration

Add this as a step in the deploy workflow BEFORE `terraform init`:

```yaml
- name: Verify state alignment
  env:
    STATE_RG: rg-tfstate-uksouth
    STATE_SA: sttfstatede4c37db
    STATE_KEY: checkout-${{ inputs.environment }}.tfstate
    TARGET_RG: rg-checkout-${{ inputs.environment }}
  run: bash scripts/verify-state.sh
```

## Decision Matrix

| Azure RG | State Blob | Diagnosis | Automated Fix |
|----------|-----------|-----------|---------------|
| Exists | Empty/missing | Orphaned Azure resources | Delete RG, wait, apply |
| Missing | Has content | Stale state file | Delete state blob, apply |
| Missing | Missing | Clean slate | Apply directly |
| Exists | Has content | Normal | Apply directly |
| State backend gone | Any | Backend destroyed | Re-bootstrap, then apply |

## Azure-Specific Gotchas

1. **APIM takes 30-45 min to delete** — `az group delete` returns immediately with `--no-wait`, but the RG isn't actually gone. Always wait: `az group wait --name <rg> --deleted`
2. **Key Vault soft-delete** — deleted KVs still occupy the name for 7-90 days. Use `purge_soft_delete_on_destroy = true` or `az keyvault purge --name <kv>`
3. **Azure auto-creates hidden resources** — Smart Detection alerts, NetworkWatcher, action groups. These block RG deletion unless `prevent_deletion_if_contains_resources = false`
4. **Storage blob deletion needs auth** — use `--auth-mode key` or `--auth-mode login` explicitly

## Cost Impact

Each wasted apply/destroy cycle costs:
- APIM Developer: ~$1.50 (45 min provisioning × $0.067/hr × 2 for create+destroy)
- Private Endpoints: ~$0.25 (5 endpoints × $0.01/hr)
- Engineer time: 30-60 min of debugging
- CI runner minutes: ~50 min per cycle

Over a project lifetime, this adds up significantly. Prevention is always cheaper.

## References

- [Terraform State Management](https://developer.hashicorp.com/terraform/language/state)
- [Azure Resource Group Deletion](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/delete-resource-group)
- [Key Vault Soft Delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
