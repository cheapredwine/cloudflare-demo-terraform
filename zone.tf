# The demo zone
#
# Terraform concept: a DATA SOURCE (`data "..."`). It reads something that
# already exists and that Terraform does not manage. Destroy never touches it.
# Everything zone-scoped references `data.cloudflare_zone.main.id`.

# `account` is read-only on this data source; the zone name is globally unique
# and `filter` scopes the lookup.
data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}
