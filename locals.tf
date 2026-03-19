locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = merge(var.tags, {
    project     = var.project
    environment = var.environment
    managed_by  = "terraform"
  })

  # Subnet CIDRs within the VNet address space
  subnets = {
    function          = "10.0.1.0/24"
    private_endpoints = "10.0.2.0/24"
    apim              = "10.0.3.0/27" # APIM Developer tier requires a dedicated subnet
    smoke_test        = "10.0.4.0/24" # Isolated subnet for smoke test function
  }
}
