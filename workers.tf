# Workers (provider v5 modern pattern: cloudflare_worker + cloudflare_worker_version)
#
# cloudflare_worker is the durable Worker entity; cloudflare_worker_version
# carries code + bindings. deploy = true sends 100% of traffic to the new
# version on apply, replacing the v4 script-upload model.

locals {
  # One compatibility date for every Worker; bump deliberately and re-test.
  worker_compatibility_date = "2025-09-01"

  worker_names = {
    api_gateway     = "demo-api-gateway"
    products_api    = "demo-products-api"
    order_processor = "demo-order-processor"
    admin_panel     = "demo-admin-panel"
  }

  workers = {
    api_gateway = {
      file               = "workers/api-gateway.js"
      compatibility_date = local.worker_compatibility_date
      bindings = [
        { type = "kv_namespace", name = "SESSIONS", namespace_id = cloudflare_workers_kv_namespace.sessions.id },
        { type = "r2_bucket", name = "UPLOADS", bucket_name = cloudflare_r2_bucket.uploads.name },
        { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
        { type = "queue", name = "ORDER_QUEUE", queue_name = cloudflare_queue.orders.queue_name },
        { type = "service", name = "PRODUCTS_API", service = local.worker_names["products_api"], environment = "production" },
        { type = "plain_text", name = "ZONE_NAME", text = var.zone_name },
      ]
    }
    products_api = {
      file               = "workers/products-api.js"
      compatibility_date = local.worker_compatibility_date
      bindings = [
        { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
        { type = "kv_namespace", name = "CACHE", namespace_id = cloudflare_workers_kv_namespace.cache.id },
        { type = "ai", name = "AI" },
        { type = "plain_text", name = "AI_GATEWAY_ID", text = cloudflare_ai_gateway.demo.id },
      ]
    }
    order_processor = {
      file               = "workers/order-processor.js"
      compatibility_date = local.worker_compatibility_date
      bindings = [
        { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
        { type = "queue", name = "ORDER_QUEUE", queue_name = cloudflare_queue.orders.queue_name },
      ]
    }
    admin_panel = {
      file               = "workers/admin-panel.js"
      compatibility_date = local.worker_compatibility_date
      bindings = [
        { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
        { type = "kv_namespace", name = "SESSIONS", namespace_id = cloudflare_workers_kv_namespace.sessions.id },
        { type = "plain_text", name = "ZONE_NAME", text = var.zone_name },
      ]
    }
  }
}

resource "cloudflare_worker" "workers" {
  for_each = local.workers

  account_id = var.account_id
  name       = local.worker_names[each.key]

  # Workers Logs: persist invocation logs so the demo can show request traces
  # in the dashboard (Workers & Pages -> <worker> -> Logs).
  observability = {
    enabled            = true
    head_sampling_rate = 1
  }
}

resource "cloudflare_worker_version" "versions" {
  for_each = local.workers

  account_id         = var.account_id
  worker_id          = cloudflare_worker.workers[each.key].id
  main_module        = basename(each.value.file)
  compatibility_date = each.value.compatibility_date
  deploy             = true

  modules = [
    {
      name         = basename(each.value.file)
      content_file = each.value.file
      content_type = "application/javascript+module"
    }
  ]

  bindings = [
    for b in each.value.bindings : {
      type         = b.type
      name         = b.name
      text         = try(b.text, null)
      namespace_id = try(b.namespace_id, null)
      bucket_name  = try(b.bucket_name, null)
      id           = try(b.id, null)
      queue_name   = try(b.queue_name, null)
      service      = try(b.service, null)
      environment  = try(b.environment, null)
    }
  ]
}
