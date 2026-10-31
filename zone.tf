# The demo zone
#
# Terraform concept: a DATA SOURCE (`data "..."`). It reads something that
# already exists and that Terraform does not manage. Destroy never touches it.
# Everything zone-scoped references `data.cloudflare_zone.main.id`.

# `filter` describes which zone to find. Filtering by account as well as name
# keeps the lookup unambiguous if the token can see more than one account.
data "cloudflare_zone" "main" {
  filter = {
    name    = var.zone_name
    account = { id = var.account_id }
  }
}
