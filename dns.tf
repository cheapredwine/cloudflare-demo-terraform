resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.zone_name
  content = "203.0.113.10"
  type    = "A"
  proxied = true
}

resource "cloudflare_record" "api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  content = "100::"
  type    = "AAAA"
  proxied = true
}

resource "cloudflare_record" "admin" {
  zone_id = data.cloudflare_zone.main.id
  name    = "admin"
  content = "100::"
  type    = "AAAA"
  proxied = true
}
