# DNS records
#
# Terraform concepts:
#   - Resources with input variables: `var.origin_ipv4` is set in tfvars.
#   - A local value naming a magic constant (`100::`) so it reads as intent.
# (Upgrading from v4's cloudflare_record? See upgrade-from-v4.tf.)

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
