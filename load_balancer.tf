# Load balancing: two pools in active/passive failover
#
# Terraform concepts:
#   - A boolean input variable (`var.primary_origin_enabled`) that changes
#     live behavior: flip it with -var and the plan shows one attribute change.
#   - Account-level and zone-level resources referencing each other by ID.
#   - A `precondition`: a lifecycle check on one resource that fails the plan
#     with a clear message when an assumption about the inputs is wrong.
#
# Active/passive failover: one health monitor probes two origin pools; the
# load balancer sends traffic to the first healthy pool in default_pools
# order (steering_policy = "off"), and to fallback_pool if every pool is down.
#
# Demo failover live:  terraform apply -var primary_origin_enabled=false
# The primary pool's only origin is disabled, so the pool counts as down and
# app.<zone> is served by the secondary pool. (Disabling is immediate; it
# doesn't wait for open connections to finish.)
#
# With the default RFC 5737 documentation IPs, the health checks fail on
# BOTH pools, so the failover is only visible once origin_ipv4 and
# secondary_origin_ipv4 point at real servers with a /health endpoint.
# Monitors and pools are account-level; the load balancer itself is zone-level.

resource "cloudflare_load_balancer_monitor" "http" {
  account_id       = var.account_id
  description      = "Demo platform origin health"
  type             = "http"
  method           = "GET"
  path             = "/health"
  expected_codes   = "200"
  interval         = 60
  timeout          = 5
  retries          = 2
  consecutive_down = 2
  consecutive_up   = 2
  allow_insecure   = false

  # Probe with the public hostname so name-based origins answer correctly.
  header = {
    Host = ["app.${var.zone_name}"]
  }
}

resource "cloudflare_load_balancer_pool" "primary" {
  account_id  = var.account_id
  name        = "demo-platform-primary"
  description = "Primary origin (active)"
  monitor     = cloudflare_load_balancer_monitor.http.id

  origins = [
    {
      name    = "origin-primary"
      address = var.origin_ipv4
      enabled = var.primary_origin_enabled
    }
  ]

  minimum_origins = 1
}

resource "cloudflare_load_balancer_pool" "secondary" {
  account_id  = var.account_id
  name        = "demo-platform-secondary"
  description = "Secondary origin (passive failover)"
  monitor     = cloudflare_load_balancer_monitor.http.id

  origins = [
    {
      name    = "origin-secondary"
      address = var.secondary_origin_ipv4
      enabled = true
    }
  ]

  minimum_origins = 1
}

resource "cloudflare_load_balancer" "app" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "app.${var.zone_name}"
  description     = "Demo platform load balancer (active/passive failover)"
  enabled         = true
  proxied         = true
  steering_policy = "off" # failover in default_pools order

  default_pools = [
    cloudflare_load_balancer_pool.primary.id,
    cloudflare_load_balancer_pool.secondary.id,
  ]
  fallback_pool    = cloudflare_load_balancer_pool.secondary.id
  session_affinity = "none"

  lifecycle {
    # Failover between two pools that point at the same server proves nothing.
    precondition {
      condition     = var.origin_ipv4 != var.secondary_origin_ipv4
      error_message = "origin_ipv4 and secondary_origin_ipv4 are the same address, so failover would land on the same server."
    }
  }
}

output "load_balancer_hostname" {
  description = "Hostname served by the demo load balancer"
  value       = cloudflare_load_balancer.app.name
}
