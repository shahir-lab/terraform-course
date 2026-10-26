# Lab 01 Notes

## Anatomy of a resource block

Every resource declaration in a `.tf` file is made of 3 parts:

```hcl
resource "random_string" "suffix" {
  #        ^^^^^^^^^^^^^  ^^^^^^
  #        |              |
  #        |              Local name (how you refer to this
  #        |              instance elsewhere in the config,
  #        |              e.g. random_string.suffix.result)
  #        |
  #        Resource type (which provider/resource is being created)

  length  = 6
  upper   = false
  special = false
}
```

| Part               | Example          | What it means                                                   |
|--------------------|------------------|------------------------------------------------------------------|
| **Block type**      | `resource`       | Tells Terraform what kind of block this is (e.g. `resource`, `variable`, `provider`, `output`). |
| **Resource type**   | `random_string`  | The specific resource being created, defined by a provider.     |
| **Local name**      | `suffix`         | A reference name used only within this config to point back to this resource. |

Together, `resource type` + `local name` form the **object reference**: `random_string.suffix`.

## Useful commands

| Command            | What it does                                                        |
|---------------------|----------------------------------------------------------------------|
| `terraform init`    | Downloads providers/modules and sets up the working directory.      |
| `terraform plan`    | Shows what changes Terraform would make, without applying them.     |
| `terraform apply`   | Applies the changes to reach the desired state.                     |
| `terraform destroy` | Removes all resources managed by this configuration.                |


## Local values

A `locals` block defines named expressions that are computed once and reused, referenced as `local.<name>` (note: `local`, singular). They are not inputs: they can't be set from outside the config.

```hcl
locals {
  environment_prefix = "${var.application_name}-${var.environment_name}-${random_string.suffix.result}"
}
```

The prefix was previously hardcoded (`"shahirsblogs-dev"`). It is now built from the input variables via string interpolation (`${...}`), and ends with the `random_string.suffix` result, so `application_name=shahirsblog` and `environment_name=dev` give something like `shahirsblog-dev-a1b2c3`. Referencing the resource also makes the local depend on it, so Terraform creates the suffix first.

## Input variables

Variables let you parameterize a configuration instead of hardcoding values. Each variable is declared with a `variable` block (type `variable`, local name is the variable's identifier), then referenced elsewhere as `var.<name>`.

```hcl
variable "application_name" {

}

variable "environment_name" {

}
```

These are currently declared with no `type` or `default`, so Terraform treats them as untyped and **required**: it prompts for them on `plan`/`apply` unless you pass a value. Adding `type = string` and (optionally) `default = "dev"` is a good next step.

You can set values at runtime with the `-var` flag on `plan`/`apply`:

```sh
terraform plan -var "application_name=shahirsblog" -var "environment_name=dev"
```

Other ways to set a variable's value (in order of precedence, highest last):

| Method                          | Example                                       |
|---------------------------------|-----------------------------------------------|
| Default in the `variable` block | `default = "dev"`                             |
| Environment variable            | `TF_VAR_application_name=shahirsblog`         |
| `terraform.tfvars` / `*.auto.tfvars` | `default.auto.tfvars` (loaded automatically) |
| `-var-file` flag                | `terraform apply -var-file="env/dev.tfvars"`  |
| `-var` flag on the CLI          | `terraform apply -var "environment_name=dev"` |

### Variable files in this lab

Values are supplied from `.tfvars` files instead of `-var` flags:

| File                       | Contents                         | How it is loaded                          |
|----------------------------|----------------------------------|-------------------------------------------|
| `default.auto.tfvars`      | `application_name = "shahir-lab"` | Automatically on every `plan`/`apply`.    |
| `env/dev.tfvars`           | `environment_name = "dev"`       | Explicitly with `-var-file`.              |
| `env/tst.tfvars`           | `environment_name = "tst"`       | Explicitly with `-var-file`.              |
| `env/prd.tfvars`           | `environment_name = "prod"`      | Explicitly with `-var-file`.              |

Pick an environment by passing its file; the shared application name comes from the auto file:

```sh
terraform plan -var-file="env/dev.tfvars"
terraform apply -var-file="env/prd.tfvars"
```

Note that `.gitignore` excludes `*.tfvars`, so these files are local only and are not committed.

## Output values

Outputs expose values from a configuration after `apply`, so you can read them from the CLI or reuse them elsewhere. They are declared with an `output` block and live in `outputs.tf`.

```hcl
output "application_name" {
  value = var.application_name
}

output "environment_name" {
  value = var.environment_name
}

output "environment_prefix" {
  value = local.environment_prefix
}

output "suffix" {
  value = random_string.suffix.result
}
```

| Output               | Source                     | What it shows                          |
|----------------------|----------------------------|----------------------------------------|
| `application_name`   | `var.application_name`     | The application name passed in.        |
| `environment_name`   | `var.environment_name`     | The environment name passed in.        |
| `environment_prefix` | `local.environment_prefix` | The computed environment prefix local. |
| `suffix`             | `random_string.suffix.result` | The generated random suffix.        |

After an apply, print them with:

```sh
terraform output                      # all outputs
terraform output environment_prefix   # a single output
```

## Provider version pinning

Provider requirements live in `versions.tf`, in the `required_providers` block inside `terraform {}`:

```hcl
terraform {
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.3"
    }
  }
}
```

`~> 3.6.3` is the pessimistic constraint operator: it allows patch releases (`3.6.x`, at least `3.6.3`) but not `3.7.0`. `terraform init` records the selected version and checksums in `.terraform.lock.hcl`, which is why the lock file moved from `3.9.1` to `3.6.3`. Commit the lock file so everyone gets the same provider build; use `terraform init -upgrade` to move it forward.


## Environment variables as input

Terraform reads any environment variable named `TF_VAR_<name>` and uses it as the value of the input variable `<name>`. A variable set this way is no longer prompted for on `plan`/`apply`.

```sh
export TF_VAR_application_name=shahirsblog
terraform plan -var-file="env/dev.tfvars"   # no prompt for application_name
```

Things to know:

- The part after `TF_VAR_` must match the variable name exactly, and it is **case-sensitive** (`TF_VAR_application_name`, not `TF_VAR_APPLICATION_NAME`).
- Values are strings. For a `string` variable that is fine; for `list`/`map`/`object` types, pass HCL syntax, e.g. `export TF_VAR_tags='{ team = "platform" }'`.
- This is the usual way to pass secrets (e.g. `TF_VAR_api_key`) so they stay out of committed files and the command line. Pair it with `sensitive = true` on the variable so Terraform redacts it from plan output.
- It sits below `*.tfvars` files and `-var`/`-var-file` in precedence (see the table above), so a `.tfvars` value overrides the environment variable.
- The export only lasts for the current shell session. To clear it: `unset TF_VAR_application_name`.
