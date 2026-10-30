# Load balancing (provider v5)
#
# Health monitor -> origin pool -> zone load balancer with failover,
# pointing at the demo origin IPs used by the DNS records.

resource "cloudflare_load_balancer_monitor" "http" {
  account_id     = var.account_id
  description    = "Demo platform origin health"
  type           = "http"
  method         = "GET"
  path           = "/health"
  expected_codes = "200"
  interval       = 60
  timeout        = 5
  retries        = 2
  allow_insecure = false
}

resource "cloudflare_load_balancer_pool" "primary" {
  account_id  = var.account_id
  name        = "demo-platform-primary"
  description = "Primary demo origins"

  monitor = cloudflare_load_balancer_monitor.http.id

  origins = [
    {
      name    = "origin-primary"
      address = "203.0.113.10"
      enabled = true
    }
  ]

  minimum_origins = 1
}

resource "cloudflare_load_balancer" "app" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "app.${var.zone_name}"
  description     = "Demo platform load balancer"
  enabled         = true
  proxied         = true
  steering_policy = "off"

  default_pools    = [cloudflare_load_balancer_pool.primary.id]
  fallback_pool    = cloudflare_load_balancer_pool.primary.id
  session_affinity = "none"
}

output "load_balancer_hostname" {
  value = cloudflare_load_balancer.app.name
}
