# CDN / cache (provider v5)
#
# Cache rules plus individual zone settings (v5's cloudflare_zone_setting
# replaces the v4 cloudflare_zone_settings_override that had to be removed
# from this project because of v4 provider bugs).

# --- Cache rules ---------------------------------------------------------------

resource "cloudflare_ruleset" "cache_rules" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # Never cache API traffic — dynamic product/order data
      enabled     = true
      description = "Bypass cache for /api/*"
      expression  = "(http.request.uri.path matches \"^/api/\")"
      action      = "set_cache_settings"

      action_parameters = {
        cache = false
      }
    },
    {
      # Cache the admin panel shell for 5 minutes at the edge
      enabled     = true
      description = "Cache admin panel HTML"
      expression  = "(http.host eq \"admin.${var.zone_name}\" and http.request.uri.path eq \"/\")"
      action      = "set_cache_settings"

      action_parameters = {
        cache = true
        edge_ttl = {
          mode    = "override_origin"
          default = 300
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
