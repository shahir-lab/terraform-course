
resource "random_string" "suffix" {
  length  = 6
  upper   = false
  special = false
}

locals {
  environment_prefix = "${var.application_name}-${var.environment_name}-${random_string.suffix.result}"

  regional_stamp = {
    foo = {
      region         = "westus"
      min_node_count = 1
      max_node_count = 3
    },
    bar = {
      region         = "eastus"
      min_node_count = 2
      max_node_count = 4
    }
  }
}

module "regional_stamp" {
  source = "./modules/regional-stamp"

  for_each = local.regional_stamp

  region         = each.value.region
  min_node_count = each.value.min_node_count
  max_node_count = each.value.max_node_count
  name           = each.key
}


