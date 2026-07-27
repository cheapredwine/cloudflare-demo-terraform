resource "cloudflare_workers_route" "api_gateway_route" {
  zone_id     = data.cloudflare_zone.main.id
  pattern     = "api.${var.zone_name}/*"
  script_name = cloudflare_workers_script.api_gateway.name
}

resource "cloudflare_workers_route" "admin_route" {
  zone_id     = data.cloudflare_zone.main.id
  pattern     = "admin.${var.zone_name}/*"
  script_name = cloudflare_workers_script.admin_panel.name
}

# SSL and cache settings managed via Cloudflare dashboard.
# cloudflare_zone_settings_override and cloudflare_ruleset were removed
# to avoid provider bugs and permission issues.
