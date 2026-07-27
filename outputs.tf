output "zone_id" {
  value = data.cloudflare_zone.main.id
}

output "nameservers" {
  value = data.cloudflare_zone.main.name_servers
}

output "api_gateway_url" {
  value = "https://api.${var.zone_name}"
}

output "admin_panel_url" {
  value = "https://admin.${var.zone_name}"
}

output "d1_database_id" {
  value = cloudflare_d1_database.products.id
}

output "kv_namespace_sessions" {
  value = cloudflare_workers_kv_namespace.sessions.id
}

output "r2_bucket_name" {
  value = cloudflare_r2_bucket.uploads.name
}
