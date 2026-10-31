# WAF: managed rules, custom rules, rate limiting, redirects
#
# Terraform concepts:
#   - One resource, many uses: every block here is `cloudflare_ruleset`. The
#     `phase` decides what kind of ruleset it is (managed WAF, custom WAF,
#     rate limiting, redirects). One ruleset per phase per zone.
#   - Nested attributes: v5 writes `rules = [{ ... }]` (a list of objects),
#     not repeated `rules { }` blocks as in v4.
#   - `ref` on every rule: a stable name Terraform uses to match rules across
#     edits, so changing one rule doesn't recreate the others with new IDs.

# --- Managed WAF ruleset -----------------------------------------------------
# Managed phase (http_request_firewall_managed): a host-scoped exception for
# OWASP 949110, then the Cloudflare Managed Ruleset and OWASP Core Ruleset.
# IDs are the official published ones (docs /terraform/additional-configurations/
# waf-managed-rulesets/). Exception rules must precede their execute rules.

resource "cloudflare_ruleset" "waf_managed" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo managed WAF"
  kind    = "zone"
  phase   = "http_request_firewall_managed"

  rules = [
    {
      # Exception: skip OWASP 949110 "Inbound Anomaly Score Exceeded"
      # (rule 6179ae15870a4bb7b2d480d4843b323c) for the admin panel only,
      # where admin form posts trip the anomaly scorer. Scoped by host: the
      # admin panel is served at admin.<zone> (all paths), not at /admin.
      # The other OWASP rules still score these requests; only the final
      # "block when the score is too high" rule is skipped.
      ref         = "skip_owasp_anomaly_score_admin"
      description = "Exception: skip OWASP anomaly-score block on admin.<zone>"
      expression  = "(http.host eq \"admin.${var.zone_name}\")"
      action      = "skip"

      action_parameters = {
        rules = {
          # OWASP Core Ruleset -> rule 949110
          "4814384a9e5d4991b9815dcfc25d2f1f" = ["6179ae15870a4bb7b2d480d4843b323c"]
        }
      }
    },
    {
      # Execute Cloudflare Managed Ruleset
      ref         = "execute_cloudflare_managed_ruleset"
      description = "Execute Cloudflare Managed Ruleset"
      expression  = "true"
      action      = "execute"

      action_parameters = {
        id = "efb7b8c949ac4650a09736fc376e9aee"
      }
    },
    {
      # Execute Cloudflare OWASP Core Ruleset (default PL1, Medium threshold)
      ref         = "execute_cloudflare_owasp_core_ruleset"
      description = "Execute Cloudflare OWASP Core Ruleset"
      expression  = "true"
      action      = "execute"

      action_parameters = {
        id = "4814384a9e5d4991b9815dcfc25d2f1f"
      }
    }
  ]
}

# --- Custom WAF ruleset -------------------------------------------------------

resource "cloudflare_ruleset" "waf_custom" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo custom WAF"
  kind    = "zone"
  phase   = "http_request_firewall_custom"

  rules = [
    {
      ref         = "block_path_scanning"
      enabled     = true
      description = "Block path scanning"
      expression  = "(http.request.uri.path contains \"/wp-admin\" or http.request.uri.path contains \"/.env\" or http.request.uri.path contains \"/.git\")"
      action      = "block"
    },
    {
      ref         = "challenge_empty_user_agent"
      enabled     = true
      description = "Challenge empty User-Agent"
      expression  = "(http.user_agent eq \"\")"
      action      = "managed_challenge"
    },
    {
      ref         = "challenge_admin_non_allowlisted"
      enabled     = true
      description = "Admin panel: challenge non-corporate IPs"
      expression  = "(http.host eq \"admin.${var.zone_name}\" and not ip.src in {${var.admin_allowlist_cidr}})"
      action      = "managed_challenge"
    }
  ]
}

# --- Rate limiting ruleset ----------------------------------------------------

resource "cloudflare_ruleset" "waf_rate_limit" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo rate limiting"
  kind    = "zone"
  phase   = "http_ratelimit"

  rules = [
    {
      # Per-IP limit on the public API: 50 requests / 10s, then block for 10s.
      # Chosen to work on every plan: Free allows only a 10s period and 10s
      # block, and only URI path in the expression. Raise them on paid plans.
      ref         = "rate_limit_api_per_ip"
      enabled     = true
      description = "Per-IP rate limit on /api/*"
      expression  = "starts_with(http.request.uri.path, \"/api/\")"
      action      = "block"

      ratelimit = {
        # Counters are kept per data center (cf.colo.id is required by the
        # API), then per client IP.
        characteristics     = ["cf.colo.id", "ip.src"]
        period              = 10
        requests_per_period = 50
        mitigation_timeout  = 10
      }
    }
  ]
}

# --- Dynamic redirects (kept from the v4 config) ------------------------------

resource "cloudflare_ruleset" "redirects" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo redirect rules"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      # /old-shop -> /api/products
      ref         = "redirect_old_shop"
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
    # Rule 2: Redirect HTTP to HTTPS
    # Uncomment to send every plain-HTTP request to HTTPS. Cloudflare's
    # "Always Use HTTPS" zone setting does the same job. (min_tls_version in
    # cdn.tf is different: it sets the oldest TLS version allowed on HTTPS
    # connections, and does nothing for plain HTTP.) Kept as a demo toggle.
    # {
    #   ref         = "force_https"
    #   enabled     = true
    #   description = "Force HTTPS"
    #   expression  = "(not ssl)"
    #   action      = "redirect"
    #
    #   action_parameters = {
    #     from_value = {
    #       status_code = 301
    #       target_url = {
    #         expression = "concat(\"https://\", http.host, http.request.uri.path)"
    #       }
    #       preserve_query_string = true
    #     }
    #   }
    # }
  ]
}
