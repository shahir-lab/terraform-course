# Lab 03 Notes

## What this lab builds

A resource group plus a Log Analytics workspace, following the same `application_name`/`environment_name`/`primary_location` variable pattern as [Lab 02](../../LAB02/docs/NOTE.md):

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.application_name}-${var.environment_name}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}
```

- `azurerm_log_analytics_workspace` is the core resource behind Azure Monitor/observability — metrics, logs, and diagnostic data from other Azure resources get sent here to be queried.
- `sku = "PerGB2018"` is the current pay-as-you-go pricing tier (billed per GB ingested); older fixed-capacity SKUs still exist for backward compatibility but aren't recommended for new workspaces.
- `retention_in_days = 30` is how long ingested data is kept before being purged — 30 days is the free/default minimum; longer retention costs more.
- Unlike `azurerm_storage_account` in Lab 02, this workspace's name doesn't need a random suffix — Log Analytics workspace names only need to be unique within the resource group, not globally across Azure.

## Remote state backend

`versions.tf` adds a `backend "azurerm" {}` block inside `terraform {}` — empty on purpose:

```hcl
terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "=5.0.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6.3" }
  }
  backend "azurerm" {}
}
```

This is a **partial backend configuration**. The backend type (`azurerm`, meaning state is stored as a blob in Azure Storage — the same kind of storage account/container built in [Lab 02](../../LAB02/docs/NOTE.md)) is fixed in code, but the actual resource group, storage account, container, and blob key are supplied later, at `terraform init` time, via `-backend-config` flags instead of being hardcoded.

Why do it this way: hardcoding a specific storage account name in `versions.tf` would tie the whole config to one backend, with no clean way to point `dev`/`tst`/`prd` at different state storage without editing committed code. Partial config keeps the backend *type* in the file (reviewed and committed) while letting the connection details be supplied per environment, outside of version control.

### The `.debug-*.sh` scripts

Each `.debug-<env>.sh` script wires up one environment end-to-end: subscription, input variables, and backend config, then runs Terraform:

```sh
# set subscription
export ARM_SUBSCRIPTION_ID="<subscription-id>"

# set application / environment
export TF_VAR_application_name="observability"
export TF_VAR_environment_name="dev"

# set backend
export BACKEND_RESOURCE_GROUP="rg-terraform-state-dev"
export BACKEND_STORAGE_ACCOUNT="stamnvbcz8np"
export BACKEND_CONTAINER_NAME="tfstate"
export BACKEND_KEY=$TF_VAR_application_name-$TF_VAR_environment_name

# run terraform
terraform init \
    -backend-config="resource_group_name=${BACKEND_RESOURCE_GROUP}" \
    -backend-config="storage_account_name=${BACKEND_STORAGE_ACCOUNT}" \
    -backend-config="container_name=${BACKEND_CONTAINER_NAME}" \
    -backend-config="key=${BACKEND_KEY}"

terraform $*

rm -rf .terraform
```

Things to know:

- `TF_VAR_application_name`/`TF_VAR_environment_name` set the input variables via environment variables (see [Lab 01](../../LAB01/docs/NOTE.md)'s note on `TF_VAR_*`), instead of a `.tfvars` file — that's why `env/dev.tfvars` is empty in this lab; `primary_location` still comes from the committed `terraform.tfvars`.
- `BACKEND_KEY` is built from `application_name-environment_name` (e.g. `observability-dev`). That key is the **blob name** inside the `tfstate` container — each app/environment combination gets its own state blob in the same shared storage account, rather than its own storage account.
- `terraform $*` forwards whatever arguments the script itself was called with (`plan`, `apply`, `destroy`, `-var-file=...`, etc.) straight to Terraform, after `init` has already run with the right backend.
- `rm -rf .terraform` at the end wipes the local provider cache and backend config after every run. Since the backend is remote, nothing is lost — `terraform init` just re-downloads/re-connects next time. The comment in `.debug-tst.sh` calls this out explicitly: this cleanup is only safe *because* state lives in the storage account, not locally.
- Usage looks like `./.debug-dev.sh plan` or `./.debug-dev.sh apply` — the script name picks the environment, the forwarded argument picks the Terraform command.

### Contrast with Terraform workspaces

[Lab 01](../../LAB01/docs/NOTE.md) separates environments with `terraform workspace`, which keeps one backend but swaps *which state file* is active. This lab takes a different approach: one backend configuration per environment, each pointing at its own key (and potentially its own storage account/resource group, e.g. `rg-terraform-state-dev` vs `rg-terraform-state-prd`). Both achieve isolated state per environment; workspaces require less wiring but share more plumbing (one backend, one set of credentials), while separate backend configs isolate environments more strongly — down to using different storage accounts/subscriptions if needed, which matters more for a prod environment than a dev one.

<!-- MODIFY AFTER THIS LINE -->
