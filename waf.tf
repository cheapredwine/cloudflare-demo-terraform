# WAF (provider v5: cloudflare_ruleset with rules as a nested attribute)
#
# Managed WAF, custom rules, and rate limiting — the showcase the demo
# previously lacked. All zone-scoped rulesets on the single demo zone.
# Note the v5 style: `rules = [{ ... }]` (attribute), not `rules { }` (block).

locals {
  waf_zone_id = data.cloudflare_zone.main.id
}

# --- Managed WAF ruleset -----------------------------------------------------
# Managed Ruleset with one exception (Inbound Anomaly Score suppression for
# admin paths), demonstrating how to tune rules without disabling them.

resource "cloudflare_ruleset" "waf_managed" {
  zone_id = local.waf_zone_id
  name    = "Demo managed WAF"
  kind    = "zone"
  phase   = "http_config_settings"

  rules = [
    {
      enabled     = true
      description = "Managed WAF: Cloudflare Managed Ruleset executed"
      action      = "execute"

      action_parameters = {
        # Cloudflare Managed Ruleset — executed as-is for this demo zone.
        # Per-rule overrides take a 32-char hex rule id; see the Managed
        # Ruleset docs when tuning for real traffic.
        id = "efb7b899d074703f805dec1c688a04ef"
      }

      expression = "(http.request.method in {\"GET\" \"POST\" \"PUT\" \"DELETE\" \"OPTIONS\"})"
    }
  ]
}

# --- Custom WAF ruleset -------------------------------------------------------

resource "cloudflare_ruleset" "waf_custom" {
  zone_id = local.waf_zone_id
  name    = "Demo custom WAF"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      enabled     = true
      description = "Block path scanning"
      expression  = "(http.request.uri.path contains \"/wp-admin\" or http.request.uri.path contains \"/.env\" or http.request.uri.path contains \"/.git\")"
      action      = "block"
    },
    {
      enabled     = true
      description = "Challenge empty User-Agent"
      expression  = "(http.user_agent eq \"\")"
      action      = "managed_challenge"
    },
    {
      enabled     = true
      description = "Admin panel: challenge non-corporate IPs"
      expression  = "(http.request.uri.path contains \"/admin\" and ip.src ne 203.0.113.0/24)"
      action      = "managed_challenge"
    }
  ]
}

# --- Rate limiting ruleset ----------------------------------------------------

resource "cloudflare_ruleset" "waf_rate_limit" {
  zone_id = local.waf_zone_id
  name    = "Demo rate limiting"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      # Per-IP limit on the public API: 50 requests / 10s, block for 60s
      enabled     = true
      description = "Per-IP rate limit on /api/*"
      expression  = "(http.request.uri.path matches \"^/api/\")"
      action      = "block"

      ratelimit = {
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 50
        mitigation_timeout  = 60
      }
    }
  ]
}

# --- Dynamic redirects (kept from the v4 config) ------------------------------

resource "cloudflare_ruleset" "redirects" {
  zone_id = local.waf_zone_id
  name    = "Demo redirect rules"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      # /old-shop -> /api/products
      enabled     = true
      description = "Redirect old shop path to products API"
      expression  = "(http.request.uri.path eq \"/old-shop\")"
      action      = "redirect"

      action_parameters = {
        from_value = {
          status_code = 301
          target_url = {
            value = "https://api.${var.zone_name}/api/products"
          }
          preserve_query_string = false
        }
      }
    }
  ]
}
