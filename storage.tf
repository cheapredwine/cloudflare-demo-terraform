# Storage: R2 bucket, KV namespaces, D1 database, queue
#
# Terraform concept: independent resources. None references another, so
# Terraform creates them in parallel. The Workers in workers.tf reference
# their IDs, and those references make Terraform create these first.

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
  # In v5 the queue's name is `queue_name`
  queue_name = "demo-order-processing"
}
