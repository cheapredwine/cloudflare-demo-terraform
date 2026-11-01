# Workers
#
# Terraform concepts in this file:
#   - Resource references: `cloudflare_d1_database.products.id` both passes a
#     value and tells Terraform to create the database before the Worker.
#   - A local value (`local.compatibility_date`) to avoid repeating a setting.
#   - A sensitive variable flowing into a secret binding (admin panel).
#   - `depends_on` where the real dependency is on deployed code (see
#     api_gateway's service binding).
#
# Provider v5 splits a Worker into two resources:
#   cloudflare_worker          the Worker itself (name, logging settings)
#   cloudflare_worker_version  its code + bindings; deploy = true sends
#                              100% of traffic to this version on apply
#
# Destroying a cloudflare_worker_version only removes it from state (the API
# can't delete a single version); destroying the cloudflare_worker deletes
# the Worker and all its versions. So `-replace` on a version uploads a new
# version and leaves the old one in the Worker's version history.
#
# Each Worker below is written out in full on purpose: repetitive, but you can
# read any one block and see everything that Worker gets.

locals {
  # One compatibility date for every Worker. Bump it deliberately and re-test.
  compatibility_date = "2025-09-01"
}

# --- API gateway: public entry point at api.<zone> ------------------------------

resource "cloudflare_worker" "api_gateway" {
  account_id = var.account_id
  name       = "demo-api-gateway"
  # Workers Logs in the dashboard. Logs are set explicitly rather than left
  # to the API's defaults, so the plan shows exactly what you get.
  observability = {
    enabled = true
    logs    = { enabled = true, invocation_logs = true }
  }
}

resource "cloudflare_worker_version" "api_gateway" {
  account_id         = var.account_id
  worker_id          = cloudflare_worker.api_gateway.id
  compatibility_date = local.compatibility_date
  main_module        = "api-gateway.js"
  deploy             = true

  modules = [{
    name         = "api-gateway.js"
    content_file = "${path.module}/workers/api-gateway.js"
    content_type = "application/javascript+module"
  }]

  # Each binding becomes `env.<NAME>` inside the Worker. Every binding here
  # is one the Worker's code reads (config-checks fails on an unused one).
  bindings = [
    { type = "kv_namespace", name = "SESSIONS", namespace_id = cloudflare_workers_kv_namespace.sessions.id },
    { type = "r2_bucket", name = "UPLOADS", bucket_name = cloudflare_r2_bucket.uploads.name },
    { type = "queue", name = "ORDER_QUEUE", queue_name = cloudflare_queue.orders.queue_name },
    # The binding names the products-api Worker; depends_on below makes sure
    # its code is deployed first, so the gateway never calls an empty Worker.
    { type = "service", name = "PRODUCTS_API", service = cloudflare_worker.products_api.name },
    { type = "plain_text", name = "ZONE_NAME", text = var.zone_name },
  ]

  depends_on = [cloudflare_worker_version.products_api]
}

# --- Products API: private, reached only through the gateway's service binding -

resource "cloudflare_worker" "products_api" {
  account_id = var.account_id
  name       = "demo-products-api"
  observability = {
    enabled = true
    logs    = { enabled = true, invocation_logs = true }
  }
}

resource "cloudflare_worker_version" "products_api" {
  account_id         = var.account_id
  worker_id          = cloudflare_worker.products_api.id
  compatibility_date = local.compatibility_date
  main_module        = "products-api.js"
  deploy             = true

  modules = [{
    name         = "products-api.js"
    content_file = "${path.module}/workers/products-api.js"
    content_type = "application/javascript+module"
  }]

  bindings = [
    { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
    { type = "kv_namespace", name = "CACHE", namespace_id = cloudflare_workers_kv_namespace.cache.id },
    { type = "ai", name = "AI" }, # Workers AI, called through the AI Gateway below
    { type = "plain_text", name = "AI_GATEWAY_ID", text = cloudflare_ai_gateway.demo.id },
  ]
}

# --- Order processor: consumes the orders queue (see queue-consumer.tf) ---------

resource "cloudflare_worker" "order_processor" {
  account_id = var.account_id
  name       = "demo-order-processor"
  observability = {
    enabled = true
    logs    = { enabled = true, invocation_logs = true }
  }
}

resource "cloudflare_worker_version" "order_processor" {
  account_id         = var.account_id
  worker_id          = cloudflare_worker.order_processor.id
  compatibility_date = local.compatibility_date
  main_module        = "order-processor.js"
  deploy             = true

  modules = [{
    name         = "order-processor.js"
    content_file = "${path.module}/workers/order-processor.js"
    content_type = "application/javascript+module"
  }]

  # No queue binding: this Worker consumes the queue through its queue()
  # handler, which cloudflare_queue_consumer (queue-consumer.tf) attaches.
  # A queue binding is for sending, and only the gateway sends.
  bindings = [
    { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
    # The same KV namespace the products API caches into: after an order
    # changes stock, this Worker deletes the cached list so it's rebuilt.
    { type = "kv_namespace", name = "CACHE", namespace_id = cloudflare_workers_kv_namespace.cache.id },
  ]
}

# --- Admin panel: admin.<zone>, Basic auth ---------------------------------------

resource "cloudflare_worker" "admin_panel" {
  account_id = var.account_id
  name       = "demo-admin-panel"
  observability = {
    enabled = true
    logs    = { enabled = true, invocation_logs = true }
  }
}

resource "cloudflare_worker_version" "admin_panel" {
  account_id         = var.account_id
  worker_id          = cloudflare_worker.admin_panel.id
  compatibility_date = local.compatibility_date
  main_module        = "admin-panel.js"
  deploy             = true

  modules = [{
    name         = "admin-panel.js"
    content_file = "${path.module}/workers/admin-panel.js"
    content_type = "application/javascript+module"
  }]

  bindings = [
    { type = "d1", name = "DB", id = cloudflare_d1_database.products.id },
    # Shared with the products API: POST /reset clears its cached list.
    { type = "kv_namespace", name = "CACHE", namespace_id = cloudflare_workers_kv_namespace.cache.id },
    { type = "plain_text", name = "ZONE_NAME", text = var.zone_name },
    # secret_text: encrypted at Cloudflare and never readable back from the API.
    # var.admin_password is `sensitive`, so Terraform hides it in plan output,
    # but terraform.tfstate still holds it in plain text: protect your state.
    { type = "secret_text", name = "ADMIN_PASSWORD", text = var.admin_password },
  ]
}
