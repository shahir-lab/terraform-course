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


## Input variables

Variables let you parameterize a configuration instead of hardcoding values. Each variable is declared with a `variable` block (type `variable`, local name is the variable's identifier), then referenced elsewhere as `var.<name>`.

```hcl
variable "application_name" {
  type = string
}

variable "environment_name" {
  type    = string
  default = "dev"
}
```

You can set values at runtime with the `-var` flag on `plan`/`apply`:

```sh
terraform plan -var "application_name=shahirsblog" -var "environment_name=dev"
```

Other ways to set a variable's value (in order of precedence, highest last):

| Method                          | Example                                       |
|---------------------------------|-----------------------------------------------|
| Default in the `variable` block | `default = "dev"`                             |
| Environment variable            | `TF_VAR_application_name=shahirsblog`         |
| `.tfvars` file                  | `terraform apply -var-file="prod.tfvars"`     |
| `-var` flag on the CLI          | `terraform apply -var "environment_name=dev"` |
