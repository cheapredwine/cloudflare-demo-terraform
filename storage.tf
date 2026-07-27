resource "cloudflare_r2_bucket" "uploads" {
  account_id = var.account_id
  name       = "demo-platform-uploads"
}

resource "cloudflare_workers_kv_namespace" "sessions" {
  account_id = var.account_id
  title      = "demo-sessions"
}

resource "cloudflare_workers_kv_namespace" "cache" {
  account_id = var.account_id
  title      = "demo-cache"
}

resource "cloudflare_d1_database" "products" {
  account_id = var.account_id
  name       = "demo-products"
}

resource "cloudflare_queue" "orders" {
  account_id = var.account_id
  name       = "demo-order-processing"
}
