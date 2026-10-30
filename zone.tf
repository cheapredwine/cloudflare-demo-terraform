# Existing demo zone (provider v5 data source shape: nested objects as
# attributes, not blocks)

# `account` is read-only on this data source; the zone name is globally unique
# and `filter` scopes the lookup.
data "cloudflare_zone" "main" {
  filter = {
    name = var.zone_name
  }
}
