# Azure Cost Optimisation for Terraform Deployments

## Context

Hard-won lessons from deploying Azure infrastructure with Terraform under budget constraints (~$200 free trial credits). These patterns prevent the most common ways engineers accidentally exhaust cloud budgets.

## Budget Blower Reference: Azure Resources by Cost Risk

### Tier 1 — Critical (>$500/month, can exhaust free credits in days)
- **Azure Firewall Premium**: ~$1,300/month ($1.84/hr) — use NSGs (free) in dev/test
- **Azure Firewall Standard**: ~$912/month ($1.25/hr) — use Azure Firewall Basic ($288/mo) or NSGs
- **ExpressRoute Standard**: ~$900+/month — use VPN Gateway Basic ($27/mo) or skip entirely
- **APIM Premium**: ~$2,000/month — use Developer ($50) or Consumption (free 1M calls)

### Tier 2 — Significant ($100-500/month, accumulates quickly)
- **Azure Firewall Basic**: ~$288/month ($0.395/hr) — still expensive for dev/test; NSGs are free
- **Application Gateway v2**: ~$180/month — can be stopped/deallocated ($0 when stopped)
- **Azure SQL General Purpose**: ~$370+/month — use Basic tier ($5/mo)
- **Private Endpoints**: ~$7.50 each — multiplies fast (5 endpoints = $37.50/mo)

### Tier 3 — Moderate ($20-100/month, acceptable with awareness)
- **APIM Developer**: ~$50/month — 30-45 min provisioning time; failed applies waste money
- **NAT Gateway**: ~$32/month + data charges — remove in dev; default SNAT is free
- **VPN Gateway Basic**: ~$27/month — acceptable for dev connectivity needs

### Tier 4 — Negligible (free tier / <$5/month)
- **Function App Consumption (Y1)**: ~$0 (1M free executions)
- **Storage Account (LRS)**: ~$1/month
- **Key Vault**: ~$0.03/10K ops
- **Log Analytics / App Insights**: free up to 5GB/month
- **NSGs**: free
- **Azure Budgets/Cost Management**: free

## Anti-Pattern: Wasteful Deploy Cycles

The most expensive mistake in Terraform + Azure is the **failed partial apply loop**:

```
apply (partial) → fix → destroy (fails: orphaned resources) →
fix provider → destroy (succeeds) → apply (stale state: 404s) →
clean state → apply (orphaned RG: already exists) → delete RG → apply
```

Each cycle with APIM takes ~45 minutes and burns ~$1.50 per attempt.

### Prevention Strategies

1. **Pre-flight everything**: `terraform validate` + `terraform plan` in CI, gated before `apply`
2. **Targeted applies**: `terraform apply -target=module.networking` first, then cheaper modules, then expensive ones last
3. **Idempotent provider config from day one**:
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
     }
   }
   ```
4. **State hygiene**: After failed partial apply + manual cleanup, always `terraform state list` before re-applying
5. **Cost-aware retry limits**: Max N retries on deploy workflows, then alert — don't loop

## Shift-Left Cost Estimation

### Infracost (recommended, free tier available)
- Analyses `terraform plan` and posts PR comments with monthly cost estimates
- Supports 1,100+ Terraform resources across Azure/AWS/GCP
- GitHub Action: `infracost/actions/setup@v3`
- Engineers see "+$912/month" on a PR adding `azurerm_firewall` before it reaches main

### HCP Terraform Cost Estimation
- Built into HCP Terraform Team and Business tiers (not free tier)
- Estimates monthly costs for many Azure resources using public price lists

## Architectural Patterns

1. **Feature flags for expensive resources**: `enable_apim = false` variable to skip APIM in dev
2. **Module isolation**: Expensive resources in separate state files for targeted operations
3. **Consumption over Dedicated**: Functions Consumption, APIM Consumption — 10-100x cheaper
4. **Stop vs Destroy**: Application Gateway, VMs can be stopped ($0) without full destroy/recreate
5. **Nightly schedules**: Auto-destroy dev environments during off-hours (this project: 02:00-09:00)
6. **Budget alerts at multiple thresholds**: 25%, 50%, 80%, 100% with automated actions at each tier

## Azure-Specific Gotchas

- **Azure auto-creates resources** inside your resource groups (Smart Detection alerts, NetworkWatcher) — these block Terraform destroy unless `prevent_deletion_if_contains_resources = false`
- **APIM Developer takes 30-45 min to provision** — a failed apply after APIM is created wastes the full provisioning time on the next cycle
- **NAT Gateway charges start immediately** on creation, even with no subnets or public IPs attached
- **Free trial → PAYG upgrade** takes 24-48 hours to propagate internally; quota requests blocked during this period
- **Key Vault soft-delete** means destroyed vaults still exist for 7-90 days; re-deploying with the same name fails unless `recover_soft_deleted_key_vaults = true`
- **Application Insights creates hidden resources** (Smart Detection rules, action groups) not managed by Terraform

## Tagging Strategy for Cost Attribution

Every resource should have:
```hcl
tags = {
  environment  = "dev"         # For environment-scoped cost queries
  cost_center  = "platform"    # For department billing
  owner        = "team-name"   # For accountability
  managed_by   = "terraform"   # Distinguish from manual/ARM resources
  destroy_ok   = "true"        # Safe to auto-destroy in scheduled cleanup
}
```

## References

- [Azure Well-Architected Framework — Cost Optimisation](https://learn.microsoft.com/en-us/azure/well-architected/pillars)
- [APIM Cost Optimisation](https://learn.microsoft.com/en-us/azure/well-architected/service-guides/api-management/cost-optimization)
- [Azure Firewall Pricing](https://azure.microsoft.com/en-us/pricing/details/azure-firewall/)
- [Infracost](https://www.infracost.io/)
- [HCP Terraform Cost Estimation](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/cost-estimation)
- [NAT Gateway Pricing](https://azure.microsoft.com/en-us/pricing/details/azure-nat-gateway/)
- [Application Gateway Pricing](https://azure.microsoft.com/en-us/pricing/details/application-gateway/)
