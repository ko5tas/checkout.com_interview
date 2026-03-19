# AzureRM Terraform Provider: Known Issues & Prevention Guide

## Purpose

The azurerm Terraform provider has well-documented behavioural quirks that cause deploy failures, wasted cycles, and real cost (each failed APIM cycle costs ~$1.50 + 45 min). This skill captures every issue encountered in production use so engineers can prevent rather than react.

## Issue Registry

### Category 1: Resource Update Bugs

#### 1.1 Missing Resource Identity After Update
- **Provider versions:** azurerm 4.x
- **Affected resources:** `azurerm_linux_function_app`, `azurerm_windows_function_app`, `azurerm_linux_web_app`
- **Trigger:** Adding `virtual_network_subnet_id` to an existing (already-created) function app
- **Error:** `Missing Resource Identity After Update: The Terraform provider unexpectedly returned no resource identity`
- **Root cause:** ARM API returns an inconsistent response body when VNet integration is toggled on a running app
- **Workarounds:**
  1. Re-run `terraform apply` (usually succeeds on retry — the update actually applied)
  2. `terraform taint` the resource and recreate
  3. **Best:** Always include `virtual_network_subnet_id` in the initial resource definition — never add it later
- **GitHub issue:** https://github.com/hashicorp/terraform-provider-azurerm/issues/

#### 1.2 Plan Diff on Unchanged Resources
- **Affected resources:** `azurerm_linux_function_app` (app_settings), `azurerm_api_management`
- **Trigger:** Azure adds hidden app settings (e.g., `WEBSITE_NODE_DEFAULT_VERSION`) that weren't in Terraform config
- **Symptom:** Perpetual plan diff showing changes when nothing changed
- **Fix:** Use `lifecycle { ignore_changes = [app_settings["WEBSITE_NODE_DEFAULT_VERSION"]] }` or add the setting explicitly

### Category 2: Naming & Attribute Renames

#### 2.1 Attribute Renames in Major Versions
The azurerm provider frequently renames attributes between major versions. Common renames:

| Old (v3.x) | New (v4.x+) | Resource |
|-----------|------------|---------|
| `enable_rbac_authorization` | `rbac_authorization_enabled` | `azurerm_key_vault` |
| `queue_properties` (inline) | `azurerm_storage_account_queue_properties` (separate resource) | `azurerm_storage_account` |
| `allow_blob_public_access` | `allow_nested_items_to_be_public` | `azurerm_storage_account` |
| `network_rules_default_action` | `network_rules { default_action }` | Various |

**Prevention:** Always check the [azurerm changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md) when upgrading provider versions.

### Category 3: Azure Auto-Created Resources

#### 3.1 Smart Detection Alert Rules (Application Insights)
- **Trigger:** Creating `azurerm_application_insights`
- **Side effect:** Azure auto-creates ~5 Smart Detection alert rules and action groups inside the resource group
- **Problem:** `terraform destroy` fails because these unmanaged resources block RG deletion
- **Fix:**
  ```hcl
  provider "azurerm" {
    features {
      resource_group {
        prevent_deletion_if_contains_resources = false
      }
    }
  }
  ```

#### 3.2 NetworkWatcher
- **Trigger:** Creating any networking resource (VNet, subnet, NSG) in a region
- **Side effect:** Azure auto-creates `NetworkWatcher_{region}` in `NetworkWatcherRG`
- **Problem:** Not managed by Terraform; persists after destroy; confuses resource audits
- **Fix:** Manual deletion via portal/CLI, or import into Terraform state

#### 3.3 APIM Hidden Resources
- **Trigger:** Creating `azurerm_api_management`
- **Side effect:** Azure creates internal caches, managed identities, and policy fragments
- **Problem:** Slow deletion (30-45 min), blocks RG destroy

### Category 4: Soft-Delete & Purge Protection

#### 4.1 Key Vault Soft Delete
- **Trigger:** Destroying a Key Vault, then recreating with the same name
- **Error:** `A vault with the same name already exists in deleted state`
- **Fix:**
  ```hcl
  provider "azurerm" {
    features {
      key_vault {
        purge_soft_delete_on_destroy    = true
        recover_soft_deleted_key_vaults = true
      }
    }
  }
  ```

#### 4.2 Storage Account Soft Delete
- **Trigger:** Storage accounts with blob versioning or soft-delete enabled
- **Problem:** Deleted blobs/containers retain data for retention period, occupying the name
- **Fix:** Set appropriate retention days and wait, or use unique naming with `random_string`

### Category 5: Quota & Subscription Issues

#### 5.1 Dynamic VM Quota on Free Trial
- **Trigger:** Creating Consumption plan (Y1) Function App on Free Trial subscription
- **Error:** `Dynamic VMs quota: 0` or `401 Unauthorized`
- **Root cause:** Free Trial doesn't allocate Dynamic VM quota
- **Fix:** Upgrade to Pay-As-You-Go (takes 24-48h to propagate)

#### 5.2 Region-Specific Quota Availability
- **Trigger:** Deploying to a region with exhausted quotas
- **Symptom:** Quota increase requests blocked during Free Trial → PAYG transition
- **Fix:** Deploy to a region with available quota (e.g., `westeurope`, `northeurope`)

## Provider Configuration Template

Always start with this provider config to prevent the most common issues:

```hcl
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
    api_management {
      purge_soft_delete_on_destroy = true
      recover_soft_deleted         = true
    }
  }
}
```

## Pre-Change Checklist

Before modifying any Terraform resource:

1. **Adding an attribute to an existing resource?**
   - Check if the attribute can cause "Missing Resource Identity" errors
   - If so, taint and recreate the resource instead of updating in place

2. **Using an attribute name?**
   - Verify against the provider version's changelog for renames
   - Run `terraform plan` locally before pushing

3. **Creating resources that Azure auto-populates?**
   - App Insights → Smart Detection rules
   - Networking → NetworkWatcher
   - APIM → internal caches
   - Ensure `prevent_deletion_if_contains_resources = false`

4. **Destroying/recreating Key Vault or APIM?**
   - Ensure soft-delete purge is configured
   - Wait for DNS propagation if using custom domains

5. **Changing storage account properties?**
   - Use separate resource blocks (not inline deprecated blocks)
   - Check for soft-delete retention conflicts

## Cost Impact of Not Following This Guide

| Issue | Cost per Occurrence | Typical Occurrences |
|-------|-------------------|-------------------|
| Failed APIM deploy cycle | ~$1.50 + 45 min | 2-3 per project setup |
| Failed destroy + manual cleanup | ~$0.50 + 30 min | 1-2 per project |
| Quota migration (region change) | ~$3.00 + 2 hours | Once per project |
| Total preventable cost | **~$7-15 per project** | — |

The real cost is engineer time: 4-8 hours of debugging that this guide eliminates.

## References

- [azurerm Provider Changelog](https://github.com/hashicorp/terraform-provider-azurerm/blob/main/CHANGELOG.md)
- [azurerm Provider Issues](https://github.com/hashicorp/terraform-provider-azurerm/issues)
- [Azure Resource Manager Known Issues](https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/overview)
- [Key Vault Soft Delete](https://learn.microsoft.com/en-us/azure/key-vault/general/soft-delete-overview)
