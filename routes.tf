# Worker routes
#
# Terraform concept: referencing another resource's attribute.
# `cloudflare_worker.api_gateway.name` passes the Worker's name AND makes
# Terraform create the Worker before the route that points at it.
#
# Terraform concept: `depends_on`, for a dependency references can't show.
# The route only names the Worker, but traffic should reach it only after
#   - its code is deployed (cloudflare_worker_version), and
#   - the D1 tables exist (terraform_data.d1_schema in migrations.tf), since
#     both Workers query them on their first request.
# Nothing in a route refers to either, so `depends_on` adds those edges.

resource "cloudflare_workers_route" "api_gateway_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "api.${var.zone_name}/*"
  script  = cloudflare_worker.api_gateway.name

  depends_on = [cloudflare_worker_version.api_gateway, terraform_data.d1_schema]
}

resource "cloudflare_workers_route" "admin_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "admin.${var.zone_name}/*"
  script  = cloudflare_worker.admin_panel.name

  depends_on = [cloudflare_worker_version.admin_panel, terraform_data.d1_schema]
}
