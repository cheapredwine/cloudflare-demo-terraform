# CDN: cache rules and zone settings
#
# Terraform concepts:
#   - `cloudflare_ruleset` again, this time in the cache phase
#     (http_request_cache_settings).
#   - One resource per setting: v5's `cloudflare_zone_setting` manages exactly
#     one zone setting, so each setting is its own small, reviewable block.
#     It replaces v4's all-in-one `cloudflare_zone_settings_override`.

# --- Cache rules ---------------------------------------------------------------

resource "cloudflare_ruleset" "cache_rules" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo cache rules"
  kind    = "zone"
  phase   = "http_request_cache_settings"

  rules = [
    {
      # Never cache API traffic — dynamic product/order data
      ref         = "bypass_cache_api"
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
      ref         = "cache_admin_shell"
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
