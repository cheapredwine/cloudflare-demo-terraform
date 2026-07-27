data "cloudflare_zone" "main" {
  account_id = var.account_id
  name       = var.zone_name
}
