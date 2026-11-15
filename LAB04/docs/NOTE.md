# Lab 04 — Key Vault with RBAC Authorization

## What this lab builds

The full `main.tf`, in order:

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}

resource "random_string" "keyvault_suffix" {
  length  = 6
  upper   = false
  special = false
}

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                       = "kv-${var.application_name}-${var.environment_name}-${random_string.keyvault_suffix.result}"
  location                   = azurerm_resource_group.main.location
  resource_group_name        = azurerm_resource_group.main.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
}

resource "azurerm_role_assignment" "terraform_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

- Same resource group pattern as [Lab 02](../../LAB02/docs/NOTE.md)/[Lab 03](../../LAB03/docs/NOTE.md): name built from `application_name`/`environment_name`.
- `random_string.keyvault_suffix` exists for the same reason as Lab 02's storage account suffix — **Key Vault names must be globally unique across Azure**, so a hardcoded name would collide with anyone else's vault. 6 characters is Key Vault's historical convention here, shorter than the 10-character suffix used for storage accounts since vault names allow up to 24 characters total and the rest of the name (`kv-<app>-<env>-`) is already fairly long.

## What I Learned

This lab builds an Azure Key Vault and shows that creating a Key Vault does not automatically give anyone permission to read or write secrets inside it. Access to vault *data* (secrets, keys, certificates) is a separate concern from creating the vault *resource*, and under RBAC authorization that access has to be granted explicitly with its own resource.

## Key Concepts

- `rbac_authorization_enabled = true` on `azurerm_key_vault` switches the vault's data-plane access model from the legacy **Access Policies** model to **Azure RBAC**. Once this is set, access policy blocks are ignored entirely — RBAC role assignments are the only way in.
- `azurerm_role_assignment` grants a role to a principal over a scope. Here the scope is `azurerm_key_vault.main.id`, so the role only applies to this one vault (not the whole resource group or subscription).
- `role_definition_name = "Key Vault Administrator"` is a built-in Azure role with full data-plane rights over keys, secrets, and certificates (but not management-plane rights like deleting the vault itself — that comes from a role on the resource group/subscription).
- `data.azurerm_client_config.current` shows up twice for two different purposes:
  - `.tenant_id` — tells the vault which Azure AD tenant to trust for authentication.
  - `.object_id` — identifies *who* is currently running Terraform, so that identity is the one the role gets assigned to.
- Referencing `azurerm_key_vault.main.id` inside the role assignment creates an **implicit dependency** — Terraform knows to create the vault before the role assignment, no `depends_on` needed.

## Important Notes

- Without the `azurerm_role_assignment`, `terraform apply` would succeed and the vault would exist, but any attempt to read/write a secret (even by the account that ran `apply`) would fail with a 403 — being the creator of a resource is not the same as having data-plane access to it under RBAC.
- Granting the role to `data.azurerm_client_config.current.object_id` ties access to whoever's credentials are active when `apply` runs. That's convenient for a lab, but in a real environment it's worth assigning roles to a stable AAD group or service principal instead — otherwise access silently changes whenever the person/credentials running Terraform change.
- "Key Vault Administrator" is a broad role. Azure also has narrower built-in roles like "Key Vault Secrets User" (read-only secrets) or "Key Vault Crypto Officer" (keys only) — worth knowing these exist for least-privilege scenarios, even though this lab uses the broad one.

## Example

```hcl
resource "azurerm_role_assignment" "terraform_user" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}
```

## Remote backend and the `.debug-*.sh` scripts

Same setup as [Lab 03](../../LAB03/docs/NOTE.md): `versions.tf` declares an empty `backend "azurerm" {}`, and each `.debug-<env>.sh` script fills it in at `terraform init` time with `-backend-config` flags, then runs Terraform and tears down the local `.terraform` cache. `environment_name` is also supplied by the script (`TF_VAR_environment_name`) rather than a `.tfvars` file, which is why `env/dev.tfvars` is empty here — only `primary_location` comes from the committed `terraform.tfvars`.

<!-- MODIFY AFTER THIS LINE -->

## Update — Sending Key Vault diagnostics to Lab 03's Log Analytics workspace

```hcl
data "azurerm_log_analytics_workspace" "observability" {
  name                = "log-observability-dev"
  resource_group_name = "rg-observability-dev"
}

resource "azurerm_monitor_diagnostic_setting" "main" {
  name               = "diag-${var.application_name}-${var.environment_name}-${random_string.keyvault_suffix.result}"
  target_resource_id = azurerm_key_vault.main.id

  log_analytics_workspace_id = data.azurerm_log_analytics_workspace.observability.id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
```

### What I Learned

This connects two previously separate labs: [Lab 03](../../LAB03/docs/NOTE.md)'s Log Analytics workspace now receives audit logs and metrics from this lab's Key Vault. It's my first example of one Terraform config reading infrastructure that was created by a *completely different* Terraform config (different directory, different state file), just by knowing its resource group and name.

### Key Concepts

- `azurerm_monitor_diagnostic_setting` is the generic Azure mechanism for routing a resource's platform logs/metrics somewhere — a Log Analytics workspace, a storage account, or an Event Hub. It's a separate resource from the thing it's monitoring (here, the Key Vault), and it points at the target via `target_resource_id`.
- `enabled_log { category = "AuditEvent" }` turns on Key Vault's audit log category — every vault data-plane operation (secret read/write, key use, etc.) gets logged.
- `enabled_metric { category = "AllMetrics" }` turns on all of the vault's platform metrics (e.g. API call counts/latency).
- The `data "azurerm_log_analytics_workspace"` block reads the Lab 03 workspace by its known name and resource group. Because Lab 03's resource names are deterministic (`log-${application_name}-${environment_name}`, with `application_name = "observability"` and `environment_name = "dev"`), I can hardcode `"log-observability-dev"` here without needing `terraform_remote_state` or any other explicit link between the two configs.

### Important Notes

- This only works because Lab 03 has already been applied — the data source does a live lookup against Azure, not against Lab 03's state file. If the workspace doesn't exist yet (or its name/resource group ever changes), `terraform plan` on this lab fails with a "not found" error. There's no Terraform-level dependency tracking across separate configs like this — the ordering is a manual, undocumented assumption.
- The workspace name/resource group are hardcoded strings rather than variables. That's fine for a lab, but in a real setup I'd want these as variables (or looked up via `terraform_remote_state`/a data source keyed off tags) so a naming change in Lab 03 doesn't silently break Lab 04.
- Reusing `random_string.keyvault_suffix` in the diagnostic setting's name is just a style choice for uniqueness within this config — diagnostic setting names only need to be unique per target resource, not globally, so this wasn't strictly necessary the way it was for the Key Vault's own name.
