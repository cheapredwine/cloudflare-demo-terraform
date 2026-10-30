# DNS records (provider v5: cloudflare_record was renamed to cloudflare_dns_record)

resource "cloudflare_dns_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.zone_name
  content = "203.0.113.10"
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  content = "100::"
  type    = "AAAA"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "admin" {
  zone_id = data.cloudflare_zone.main.id
  name    = "admin"
  content = "100::"
  type    = "AAAA"
  proxied = true
  ttl     = 1
}

# Preserve state continuity from the v4 provider
moved {
  from = cloudflare_record.root
  to   = cloudflare_dns_record.root
}

moved {
  from = cloudflare_record.api
  to   = cloudflare_dns_record.api
}

moved {
  from = cloudflare_record.admin
  to   = cloudflare_dns_record.admin
}
