# Lab 02 Notes

## What this lab builds

A single `azurerm_resource_group` resource, declared in `main.tf`:

```hcl
resource "azurerm_resource_group" "main" {
  name     = "rg-terraform-lab02"
  location = "westus3"
}
```

The focus of this lab isn't the resource itself but getting the `azurerm` provider authenticated against an actual Azure subscription.

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
- `variables.tf` and `outputs.tf` exist but are currently empty — natural next step is parameterizing `name`/`location` as variables and outputting the resource group's `id`, following the pattern from Lab 01.
- Location (`westus3`) is hardcoded; `az account list-locations -o table` lists valid values if changing it.

<!-- MODIFY AFTER THIS LINE -->
