# Worker routes
#
# Terraform concept: referencing another resource's attribute.
# `cloudflare_worker.api_gateway.name` passes the Worker's name AND makes
# Terraform create the Worker before the route that points at it.

resource "cloudflare_workers_route" "api_gateway_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "api.${var.zone_name}/*"
  script  = cloudflare_worker.api_gateway.name
}

resource "cloudflare_workers_route" "admin_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "admin.${var.zone_name}/*"
  script  = cloudflare_worker.admin_panel.name
}
