# Worker routes (provider v5 attribute: script, was script_name)

resource "cloudflare_workers_route" "api_gateway_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "api.${var.zone_name}/*"
  script  = cloudflare_worker.workers["api_gateway"].name
}

resource "cloudflare_workers_route" "admin_route" {
  zone_id = data.cloudflare_zone.main.id
  pattern = "admin.${var.zone_name}/*"
  script  = cloudflare_worker.workers["admin_panel"].name
}

moved {
  from = cloudflare_workers_script.api_gateway
  to   = cloudflare_worker.workers["api_gateway"]
}

moved {
  from = cloudflare_workers_script.products_api
  to   = cloudflare_worker.workers["products_api"]
}

moved {
  from = cloudflare_workers_script.order_processor
  to   = cloudflare_worker.workers["order_processor"]
}

moved {
  from = cloudflare_workers_script.admin_panel
  to   = cloudflare_worker.workers["admin_panel"]
}
