# The demo zone
#
# Terraform concept: a DATA SOURCE (`data "..."`). It reads something that
# already exists and that Terraform does not manage. Destroy never touches it.
# Everything zone-scoped references `data.cloudflare_zone.main.id`.
#
# Terraform concept: a `check` block. It runs after every plan and apply and
# prints a WARNING when its assertion is false, without stopping anything.
# Use it for "this should be true about the world" (a `validation` checks
# inputs; a `precondition` stops the plan, see load_balancer.tf).

# `filter` describes which zone to find. Filtering by account as well as name
# keeps the lookup unambiguous if the token can see more than one account.
data "cloudflare_zone" "main" {
  filter = {
    name    = var.zone_name
    account = { id = var.account_id }
  }
}

# A zone that isn't "active" yet (nameservers not switched to Cloudflare)
# accepts the config, but no traffic reaches the rules and Workers.
check "zone_is_active" {
  assert {
    condition     = data.cloudflare_zone.main.status == "active"
    error_message = "Zone ${var.zone_name} is ${data.cloudflare_zone.main.status}, not active: point its nameservers at Cloudflare or nothing here receives traffic."
  }
}
