output "zone_id" {
  description = "Demo zone ID"
  value       = data.cloudflare_zone.main.id
}

output "nameservers" {
  description = "Cloudflare nameservers assigned to the zone"
  value       = data.cloudflare_zone.main.name_servers
}

output "api_gateway_url" {
  description = "Public URL of the API gateway Worker"
  value       = "https://api.${var.zone_name}"
}

output "admin_panel_url" {
  description = "Public URL of the admin panel Worker"
  value       = "https://admin.${var.zone_name}"
}

output "d1_database_id" {
  description = "D1 products database ID"
  value       = cloudflare_d1_database.products.id
}

output "kv_namespace_sessions" {
  description = "KV namespace ID for sessions"
  value       = cloudflare_workers_kv_namespace.sessions.id
}

output "r2_bucket_name" {
  description = "R2 uploads bucket name"
  value       = cloudflare_r2_bucket.uploads.name
}
