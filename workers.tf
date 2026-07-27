resource "cloudflare_workers_script" "api_gateway" {
  account_id = var.account_id
  name       = "demo-api-gateway"
  content    = file("${path.module}/workers/api-gateway.js")
  module     = true

  kv_namespace_binding {
    name         = "SESSIONS"
    namespace_id = cloudflare_workers_kv_namespace.sessions.id
  }

  r2_bucket_binding {
    name        = "UPLOADS"
    bucket_name = cloudflare_r2_bucket.uploads.name
  }

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.products.id
  }

  queue_binding {
    binding = "ORDER_QUEUE"
    queue   = cloudflare_queue.orders.name
  }

  service_binding {
    name        = "PRODUCTS_API"
    service     = cloudflare_workers_script.products_api.name
    environment = "production"
  }

  plain_text_binding {
    name = "ZONE_NAME"
    text = var.zone_name
  }
}

resource "cloudflare_workers_script" "products_api" {
  account_id = var.account_id
  name       = "demo-products-api"
  content    = file("${path.module}/workers/products-api.js")
  module     = true

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.products.id
  }

  kv_namespace_binding {
    name         = "CACHE"
    namespace_id = cloudflare_workers_kv_namespace.cache.id
  }
}

resource "cloudflare_workers_script" "order_processor" {
  account_id = var.account_id
  name       = "demo-order-processor"
  content    = file("${path.module}/workers/order-processor.js")
  module     = true

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.products.id
  }

  queue_binding {
    binding = "ORDER_QUEUE"
    queue   = cloudflare_queue.orders.name
  }
}

resource "cloudflare_workers_script" "admin_panel" {
  account_id = var.account_id
  name       = "demo-admin-panel"
  content    = file("${path.module}/workers/admin-panel.js")
  module     = true

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.products.id
  }

  kv_namespace_binding {
    name         = "SESSIONS"
    namespace_id = cloudflare_workers_kv_namespace.sessions.id
  }

  plain_text_binding {
    name = "ZONE_NAME"
    text = var.zone_name
  }
}
