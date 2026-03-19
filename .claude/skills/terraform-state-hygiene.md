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

### Critical Rule: Verify-State Runs in Plan Job ONLY

The verification script **must only run in the Plan job**, never in the Apply job. If it runs in Apply, it may modify state between plan and apply, causing:

```
Error: Saved plan does not match the given state
```

This happens because:
1. Plan job runs verify-state → cleans stale state → creates plan against clean state
2. Apply job runs verify-state → modifies state again → saved plan is now invalid

**Correct placement:**

```yaml
# ✅ Plan job — runs verify-state BEFORE terraform init
plan:
  steps:
    - name: Verify State Alignment
      run: bash scripts/verify-state.sh
    - name: Terraform Init
      run: terraform init
    - name: Terraform Plan
      run: terraform plan -out=tfplan

# ✅ Apply job — NO verify-state, just init + apply saved plan
apply:
  needs: plan
  steps:
    # State verification runs in the Plan job only — running it here
    # would invalidate the saved plan if state changes between jobs.
    - name: Terraform Init
      run: terraform init
    - name: Download plan
      uses: actions/download-artifact@v8
    - name: Terraform Apply
      run: terraform apply tfplan
```

### State Backend Deletion by Scheduled/Budget Workflows

Another discovered failure mode: nightly destroy or budget-guard workflows may delete the state backend storage account itself. When the next deploy runs, `terraform init` fails with:

```
Error: Failed to get existing workspaces: storage.AccountsClient#ListKeys:
StatusCode=404 -- Original Error: Resource group 'rg-tfstate-uksouth' could not be found.
```

**Prevention:** The verify script checks the state backend RG exists as its first step and fails fast with a clear message to re-bootstrap. Scheduled destroy workflows should NEVER delete the state backend unless explicitly configured to do so.

## Decision Matrix

| Azure RG | State Blob | Plan Saved? | Diagnosis | Automated Fix |
|----------|-----------|-------------|-----------|---------------|
| Exists | Empty/missing | No | Orphaned Azure resources | Delete RG, wait, re-plan |
| Missing | Has content | No | Stale state file | Delete state blob, re-plan |
| Missing | Missing | No | Clean slate | Plan + apply directly |
| Exists | Has content | No | Normal | Plan + apply directly |
| Exists | Has content | Yes (stale) | State changed after plan | Discard plan, re-plan |
| State backend gone | Any | Any | Backend destroyed | Re-bootstrap, then plan |

## Azure-Specific Gotchas

1. **APIM takes 30-45 min to delete** — `az group delete` returns immediately with `--no-wait`, but the RG isn't actually gone. Always wait: `az group wait --name <rg> --deleted`
2. **Key Vault soft-delete** — deleted KVs still occupy the name for 7-90 days. Use `purge_soft_delete_on_destroy = true` or `az keyvault purge --name <kv>`
3. **Azure auto-creates hidden resources** — Smart Detection alerts, NetworkWatcher, action groups. These block RG deletion unless `prevent_deletion_if_contains_resources = false`
4. **Storage blob deletion needs auth** — use `--auth-mode key` or `--auth-mode login` explicitly
5. **Saved plan invalidation** — any state modification between plan and apply (including verify-state cleanup) causes `Saved plan does not match the given state`. Only run state-modifying steps in the Plan job.
6. **State backend is a shared resource** — never delete the state backend RG/storage account in environment-specific cleanup. Multiple environments may share the same backend. Only delete when ALL environments are destroyed.
7. **azurerm provider deprecations** — `enable_rbac_authorization` was renamed to `rbac_authorization_enabled` in azurerm 4.x (removed in 5.0). Always check provider changelogs before upgrades.

## Anti-Pattern Gallery

### Anti-Pattern 1: Verify-State in Both Plan and Apply Jobs
**Symptom:** `Saved plan does not match the given state`
**Root cause:** Verify-state modifies state in Apply job after plan was created
**Fix:** Only run verify-state in Plan job

### Anti-Pattern 2: Nightly Destroy Deletes State Backend
**Symptom:** `Failed to get existing workspaces: storage.AccountsClient#ListKeys: StatusCode=404`
**Root cause:** Budget-guard or schedule workflow deleted state backend storage
**Fix:** State backend deletion must be a separate, explicit decision — never automatic

### Anti-Pattern 3: Retry Apply After Partial Failure Without Cleaning
**Symptom:** `a resource with the ID "..." already exists`
**Root cause:** Partial apply created resources in Azure, state was cleaned but resources weren't
**Fix:** Always clean BOTH Azure resources AND state blob before retrying

### Anti-Pattern 4: Manual RG Deletion Without State Cleanup
**Symptom:** `404 Not Found` errors during next apply
**Root cause:** Resources deleted from Azure but state still references them
**Fix:** Use `terraform destroy` (not `az group delete`) OR clean state blob after manual deletion

### Anti-Pattern 5: Re-deploying After Key Vault Destruction
**Symptom:** `A vault with the same name already exists in deleted state`
**Root cause:** Key Vault soft-delete retains the name for 7-90 days
**Fix:** Set `purge_soft_delete_on_destroy = true` in provider config, or `az keyvault purge --name <kv>`

## Cost Impact

Each wasted apply/destroy cycle costs:
- APIM Developer: ~$1.50 (45 min provisioning × $0.067/hr × 2 for create+destroy)
- Private Endpoints: ~$0.25 (5 endpoints × $0.01/hr)
- Engineer time: 30-60 min of debugging
- CI runner minutes: ~50 min per cycle

**Real-world example from this project:** 5 failed deploy cycles before success = ~$7.50 in APIM costs + ~4 hours of engineer time + ~250 CI runner minutes. The verify-state script and proper CI placement prevent all of these.

## References

- [Terraform State Management](https://developer.hashicorp.com/terraform/language/state)
- [Azure Resource Group Deletion](https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/delete-resource-group)
- [Key Vault Soft Delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
- [Terraform Plan/Apply Workflow](https://developer.hashicorp.com/terraform/tutorials/automation/automate-terraform)
- [azurerm Provider Changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md)
