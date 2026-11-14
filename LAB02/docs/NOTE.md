# Lab 02 Notes

## What this lab builds

`main.tf` has grown from a single resource group into three resources that together provision a storage account with a container in it:

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-${var.application_name}-${var.environment_name}"
  location = var.primary_location
}

resource "random_string" "suffix" {
  length  = 10
  upper   = false
  special = false
}

resource "azurerm_storage_account" "main" {
  name                     = "st${random_string.suffix.result}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "GRS"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.main.id
  container_access_type = "private"
}
```

The resource group name/location were originally hardcoded (`rg-terraform-lab02` / `westus3`); the focus of this lab was (and still is) getting the `azurerm` provider authenticated against an actual Azure subscription. The config has since grown to also cover naming with variables + random suffixes and provisioning real storage resources — same variable pattern as [Lab 01](../../LAB01/docs/NOTE.md), now applied to Azure resources instead of plain outputs.

### Naming and the storage account/container

- Storage account **names must be globally unique across all of Azure**, lowercase letters/numbers only, 3–24 characters — that's why `random_string.suffix` (10 chars, lowercase, no special characters) is appended: `st${random_string.suffix.result}`.
- `azurerm_storage_container.tfstate` creates a blob container named `tfstate` inside the storage account, referenced via `storage_account_id`. `container_access_type = "private"` means blobs aren't publicly readable — access needs an authenticated request (CLI auth, a SAS token, or an RBAC role on the account).
- A container named `tfstate` is the conventional home for Terraform remote state blobs. [Lab 03](../../LAB03/docs/NOTE.md) and [Lab 04](../../LAB04/docs/NOTE.md) both declare `backend "azurerm" {}` and point at a `tfstate` container at init time — this storage account is the natural backend target for that pattern, even though this lab's own state is still local.

### Variables used here

`variables.tf` declares three required `string` inputs, same shape as [Lab 01](../../LAB01/docs/NOTE.md): `application_name`, `environment_name`, `primary_location`. Values are split across two different `.tfvars` files instead of one `-var-file` per environment:

| File | Contents | How it's loaded |
|---|---|---|
| `terraform.tfvars` | `application_name`, `primary_location` | Automatically — Terraform always loads a file literally named `terraform.tfvars` if present. |
| `env/dev.tfvars` | `environment_name` | Explicitly, via `-var-file="env/dev.tfvars"`. |

```sh
terraform plan -var-file="env/dev.tfvars"
```

The idea: values that don't change per environment (`application_name`, `primary_location`) live in the auto-loaded file; the one that does change per environment (`environment_name`) is passed explicitly, so switching environments only means swapping one flag.

## Provider requirements

`versions.tf` pins the provider and configures it:

```hcl
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=5.0.0"
    }
  }
}

provider "azurerm" {
  features {}
}
```

`=5.0.0` is an exact pin: only that version is acceptable, unlike the `~>` pessimistic operator used for the `random` provider in [Lab 01](../../LAB01/docs/NOTE.md). `terraform init` records the resolved version and checksums in `.terraform.lock.hcl`; commit that file so everyone gets the identical provider build.

The empty `features {}` block is required by the `azurerm` provider even when there's nothing to configure inside it — omitting it is a validation error.

## Authenticating to Azure

The `azurerm` provider needs to know **which subscription** to act on and **which identity** to act as. Terraform itself doesn't manage Azure credentials — it defers to the same mechanisms the Azure CLI uses.

### Option 1: Azure CLI login (used in this lab)

```sh
az login
az account set --subscription "<subscription-id>"
```

With this in place, `provider "azurerm" { features {} }` is enough — Terraform picks up the active CLI session automatically. No subscription ID needs to live in the `.tf` files or the environment.

Check what Terraform will actually use:

```sh
az account show --query "{subscriptionId:id, tenantId:tenantId}"
```

### Option 2: Set the subscription explicitly

Either hardcode it in the provider block:

```hcl
provider "azurerm" {
  features {}
  subscription_id = "<subscription-id>"
}
```

or export it as an environment variable instead of editing committed `.tf` files:

```sh
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

Hardcoding the ID in `main.tf`/`versions.tf` means it gets committed to git — prefer the environment variable, or a `.tfvars` file (already `.gitignore`d in this repo), over editing the provider block directly.

### Option 3: Service principal (for CI / non-interactive use)

`az login` is interactive and tied to a human. Automation (CI pipelines, scheduled jobs) authenticates as a service principal via environment variables instead:

```sh
export ARM_CLIENT_ID="<app-id>"
export ARM_CLIENT_SECRET="<client-secret>"
export ARM_TENANT_ID="<tenant-id>"
export ARM_SUBSCRIPTION_ID="<subscription-id>"
```

| Env var              | What it is                                   |
|----------------------|-----------------------------------------------|
| `ARM_CLIENT_ID`      | App (client) ID of the service principal.    |
| `ARM_CLIENT_SECRET`  | Its secret — never commit this.              |
| `ARM_TENANT_ID`      | Azure AD tenant the principal belongs to.    |
| `ARM_SUBSCRIPTION_ID`| Subscription Terraform should operate on.    |

These are read automatically by the `azurerm` provider — no changes needed in the provider block itself.

### Precedence

Terraform checks, roughly in this order: explicit arguments in the `provider` block, then `ARM_*` environment variables, then the Azure CLI's active session. Keep secrets (client secret, subscription ID if you'd rather not commit it) out of the `.tf` files and in the environment or `.tfvars` instead.

## Useful commands

| Command                       | What it does                                                   |
|--------------------------------|------------------------------------------------------------------|
| `az login`                     | Interactive login; sets the active CLI session Terraform reads. |
| `az account show`              | Prints the subscription/tenant the CLI (and Terraform) will use. |
| `az account set --subscription`| Switches the active subscription without logging in again.      |
| `terraform init`               | Downloads the `azurerm` provider and sets up the working directory. |
| `terraform plan`               | Shows what Terraform would create/change, without applying.      |
| `terraform apply`              | Creates the resource group against the authenticated subscription. |
| `terraform destroy`            | Removes the resource group.                                      |

## Things to know

- `terraform.tfstate` now contains the real Azure subscription ID and resource IDs — it's already covered by this repo's `.gitignore` (`*.tfstate`), so verify with `git status --ignored` rather than assuming.
- `outputs.tf` exists but is currently empty — a natural next step is outputting the storage account name and container ID, since later labs will need to reference them for their remote backend config.
- `primary_location` defaults to `westus3` via `terraform.tfvars`; `az account list-locations -o table` lists valid values if changing it.
- `account_replication_type = "GRS"` (geo-redundant storage) is a reasonable choice for a storage account meant to hold Terraform state — it survives a regional outage, unlike `LRS` (locally redundant).

<!-- MODIFY AFTER THIS LINE -->
