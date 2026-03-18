---
name: terraform-module-structure
description: Conventions for Terraform module structure — file layout, naming, variables, outputs, and production repo strategy
---

# Terraform Module Structure Conventions

## File Layout (per module)

```
modules/<module-name>/
├── main.tf          # Resources
├── variables.tf     # Input variables with descriptions and validation
├── outputs.tf       # Output values with descriptions
└── tests/
    └── <module>.tftest.hcl  # Native Terraform tests
```

## Naming Conventions

- Module directories: kebab-case (`function-app`, `api-management`)
- Resources: `azurerm_<type>.<logical_name>` — use meaningful names, not `this`
- Resource names: `"<abbreviation>-${var.name_prefix}"` (e.g., `vnet-checkout-dev`)
- Azure abbreviations: `vnet`, `snet`, `nsg`, `kv`, `st`, `func`, `apim`, `log`, `appi`, `pe`, `ag`

## Variable Conventions

- Always include `description`
- Use `validation` blocks for constrained values
- Sensitive values marked with `sensitive = true`
- Common inputs: `name_prefix`, `location`, `resource_group_name`, `tags`

## Production: Separate Repos

Each module gets its own repo: `terraform-azurerm-<name>` under a dedicated GitHub org.

Consumed via: `source = "git::https://github.com/org/terraform-azurerm-networking.git?ref=v1.2.0"`

Benefits: decoupled dev, versioned via tags, separate CI, clean git history.

## Root Module Composition

```hcl
module "networking" {
  source = "./modules/networking"  # or git:: for production
  name_prefix = local.name_prefix
  # ... pass only what the module needs
}
```

Avoid circular dependencies — if module A needs output from B and B needs output from A, move the connecting resource to the root module.
