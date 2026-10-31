# CDN: cache rules and zone settings
#
# Terraform concepts:
#   - `cloudflare_ruleset` again, this time in the cache phase
#     (http_request_cache_settings).
#   - One resource per setting: v5's `cloudflare_zone_setting` manages exactly
#     one zone setting, so each setting is its own small, reviewable block.
#     It replaces v4's all-in-one `cloudflare_zone_settings_override`.
#
# Cache rules apply to traffic that goes to an origin: here, the root hostname
# (dns.tf). They don't cache what api.<zone> and admin.<zone> return, because
# those responses come from Workers, which run in front of the cache.

# --- Cache rules ---------------------------------------------------------------

resource "cloudflare_ruleset" "cache_rules" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # Never cache API paths on the origin: dynamic data
      ref         = "bypass_cache_api"
      enabled     = true
      description = "Bypass cache for /api/*"
      expression  = "starts_with(http.request.uri.path, \"/api/\")"
      action      = "set_cache_settings"

      action_parameters = {
        cache = false
      }
    },
    {
      # Cache static files from the origin for 1 day at the edge, whatever
      # Cache-Control the origin sends
      ref         = "cache_static_assets"
      enabled     = true
      description = "Cache static assets on the root hostname for 1 day"
      expression  = "(http.host eq \"${var.zone_name}\" and http.request.uri.path.extension in {\"css\" \"js\" \"png\" \"jpg\" \"svg\" \"woff2\"})"
      action      = "set_cache_settings"

      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 86400
        }
      }
    }
  ]
}

# --- Zone settings (one resource per setting in v5) ----------------------------

resource "cloudflare_zone_setting" "cache_level" {
  zone_id    = data.cloudflare_zone.main.id
  setting_id = "cache_level"
  value      = "aggressive"
}

resource "cloudflare_zone_setting" "min_tls_version" {
  zone_id    = data.cloudflare_zone.main.id
  setting_id = "min_tls_version"
  value      = "1.2"
}
