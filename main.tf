# Cloudflare Modern API Platform Demo
# Based on JSherron account setup with API gateway pattern

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Configure the Cloudflare Provider
provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Variables
variable "cloudflare_api_token" {
  description = "Cloudflare API token"
  type        = string
  sensitive   = true
}

variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "zone_name" {
  description = "Primary zone for the demo"
  type        = string
  default     = "demo-platform.example"
}

# Main zone - reference existing zone
data "cloudflare_zone" "main" {
  account_id = var.account_id
  name       = var.zone_name
}

# DNS Records
resource "cloudflare_record" "root" {
  zone_id = data.cloudflare_zone.main.id
  name    = var.zone_name
  content = "203.0.113.10"
  type    = "A"
  proxied = true
}


resource "cloudflare_record" "api" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "api"
  content         = "100::"
  type            = "AAAA"
  proxied         = true
}

resource "cloudflare_record" "admin" {
  zone_id         = data.cloudflare_zone.main.id
  name            = "admin"
  content         = "100::"
  type            = "AAAA"
  proxied         = true
}



# R2 Bucket for file uploads
resource "cloudflare_r2_bucket" "uploads" {
  account_id = var.account_id
  name       = "demo-platform-uploads"
}

# Empty R2 bucket before destroy (Cloudflare won't delete non-empty buckets)
resource "null_resource" "empty_r2_on_destroy" {
  depends_on = [cloudflare_r2_bucket.uploads]

  triggers = {
    account_id  = var.account_id
    bucket_name = cloudflare_r2_bucket.uploads.name
    api_token   = var.cloudflare_api_token
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      python3 -c "
import urllib.request, urllib.error, json, sys

account_id  = '${self.triggers.account_id}'
bucket_name = '${self.triggers.bucket_name}'
token       = '${self.triggers.api_token}'
base        = f'https://api.cloudflare.com/client/v4/accounts/{account_id}/r2/buckets/{bucket_name}'
headers     = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}

def api(method, path='', body=None):
    req = urllib.request.Request(base + path, method=method,
          data=json.dumps(body).encode() if body else None, headers=headers)
    try:
        return json.loads(urllib.request.urlopen(req).read())
    except urllib.error.HTTPError as e:
        return json.loads(e.read())

resp = api('GET', '/objects')
objects = resp.get('result', []) if isinstance(resp.get('result'), list) else []
print(f'Emptying R2 bucket: {bucket_name} ({len(objects)} objects)')
for obj in objects:
    key = obj['key']
    r = api('DELETE', f'/objects/{urllib.request.quote(key, safe=\"\")}')
    print(f'  deleted: {key}')
print('Done.')
"
    EOT
  }
}

# KV Namespace for sessions
resource "cloudflare_workers_kv_namespace" "sessions" {
  account_id = var.account_id
  title      = "demo-sessions"
}

# KV Namespace for cache
resource "cloudflare_workers_kv_namespace" "cache" {
  account_id = var.account_id
  title      = "demo-cache"
}

# D1 Database
resource "cloudflare_d1_database" "products" {
  account_id = var.account_id
  name       = "demo-products"
}

# Queue for async processing
resource "cloudflare_queue" "orders" {
  account_id = var.account_id
  name       = "demo-order-processing"
}

# API Gateway Worker
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

# Products API Worker
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

# Order Processing Worker
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

# Admin Panel Worker
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

# Queue Consumer Registration
# Cloudflare queue consumers are configured separately from queue bindings.
# Ensure demo-order-processor is attached as consumer for demo-order-processing.
resource "null_resource" "queue_consumer" {
  depends_on = [
    cloudflare_queue.orders,
    cloudflare_workers_script.order_processor,
  ]

  triggers = {
    queue_name      = cloudflare_queue.orders.name
    consumer_script = cloudflare_workers_script.order_processor.name
    script_hash     = filemd5("${path.module}/workers/order-processor.js")
  }

  provisioner "local-exec" {
    command = <<-EOT
      wrangler queues consumer worker remove ${self.triggers.queue_name} ${self.triggers.consumer_script} >/dev/null 2>&1 || true
      wrangler queues consumer worker add ${self.triggers.queue_name} ${self.triggers.consumer_script}
    EOT

    environment = {
      CLOUDFLARE_API_TOKEN  = var.cloudflare_api_token
      CLOUDFLARE_ACCOUNT_ID = var.account_id
    }
  }
}

# Routes
resource "cloudflare_workers_route" "api_gateway_route" {
  zone_id     = data.cloudflare_zone.main.id
  pattern     = "api.${var.zone_name}/*"
  script_name = cloudflare_workers_script.api_gateway.name
}

resource "cloudflare_workers_route" "admin_route" {
  zone_id     = data.cloudflare_zone.main.id
  pattern     = "admin.${var.zone_name}/*"
  script_name = cloudflare_workers_script.admin_panel.name
}

# SSL and cache settings managed via Cloudflare dashboard
# cloudflare_zone_settings_override and cloudflare_ruleset removed
# to avoid provider bugs and permission issues

# D1 Schema Migration
# Runs wrangler to apply db/schema.sql on every deploy (idempotent via IF NOT EXISTS)
resource "null_resource" "d1_schema" {
  depends_on = [cloudflare_d1_database.products]

  triggers = {
    schema_hash = filemd5("${path.module}/db/schema.sql")
    database_id = cloudflare_d1_database.products.id
  }

  provisioner "local-exec" {
    command = "wrangler d1 execute demo-products --file=${path.module}/db/schema.sql --remote"
    environment = {
      CLOUDFLARE_API_TOKEN = var.cloudflare_api_token
      CLOUDFLARE_ACCOUNT_ID = var.account_id
    }
  }
}

# Outputs
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
