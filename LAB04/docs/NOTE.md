# Lab 04 — Key Vault with RBAC Authorization

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

<!-- MODIFY AFTER THIS LINE -->
