# DNS records (provider v5: cloudflare_record was renamed to cloudflare_dns_record)

locals {
  # 100:: is the documented discard-prefix placeholder for proxied hostnames
  # served entirely by Workers routes (no origin is ever contacted).
  worker_only_placeholder_ipv6 = "100::"
}

resource "cloudflare_dns_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.zone_name
  content = var.origin_ipv4
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "api" {
  zone_id = data.cloudflare_zone.main.id
  name    = "api"
  content = local.worker_only_placeholder_ipv6
  type    = "AAAA"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "admin" {
  zone_id = data.cloudflare_zone.main.id
  name    = "admin"
  content = local.worker_only_placeholder_ipv6
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
