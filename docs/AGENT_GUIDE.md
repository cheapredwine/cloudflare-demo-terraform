# Cloudflare Demo Platform — Agent Guide

Technical reference for AI agents working with this infrastructure.

## Platform State

| Resource | Name | Details |
|----------|------|---------|
| Zone | `jsherron.com` | Pre-existing, Terraform `data` source — not managed |
| API Gateway | `demo-api-gateway` | `api.jsherron.com/*` |
| Admin Panel | `demo-admin-panel` | `admin.jsherron.com/*` |
| Products API | `demo-products-api` | No public route — service binding only |
| Order Processor | `demo-order-processor` | No public route — queue consumer |
| D1 | `demo-products` | Tables: products, orders, order_items |
| KV | `demo-sessions` | Session tokens, 24h TTL |
| KV | `demo-cache` | Product list cache, 10min TTL |
| R2 | `demo-platform-uploads` | File uploads |
| Queue | `demo-order-processing` | Order async processing |

## Architecture Patterns

### Request Routing (API Gateway)

The gateway uses `path.startsWith()` matching with `await` on all async handlers:

```javascript
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    const corsHeaders = { 'Access-Control-Allow-Origin': '*', ... };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      if (path.startsWith('/api/products')) {
        return await handleProducts(request, env, corsHeaders);
      } else if (path.startsWith('/api/orders')) {
        return await handleOrders(request, env, corsHeaders);
      }
      // ...
      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      return new Response(JSON.stringify({
        error: 'Internal server error',
        message: error.message
      }), { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
    }
  }
};
```

**Important:** Always `await` async handler calls inside `try/catch`. Without `await`, promise rejections become unhandled and Cloudflare returns error 1101 instead of the catch block's 500.

### Service Binding (Gateway → Products API)

The gateway proxies `/api/products*` to the products worker via service binding. The path is rewritten (`/api/products` → `/products`) and the host header stripped:

```javascript
async function handleProducts(request, env, corsHeaders) {
  const url = new URL(request.url);
  const rewrittenPath = url.pathname.replace(/^\/api/, '');
  const proxiedUrl = `https://products-api.internal${rewrittenPath}${url.search}`;

  const hasBody = !['GET', 'HEAD'].includes(request.method);
  const forwardHeaders = new Headers(request.headers);
  forwardHeaders.delete('host');

  const proxiedRequest = new Request(proxiedUrl, {
    method: request.method,
    headers: forwardHeaders,
    body: hasBody ? request.body : null,
  });

  const response = await env.PRODUCTS_API.fetch(proxiedRequest);

  const newHeaders = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders)) {
    newHeaders.set(key, value);
  }
  return new Response(response.body, { status: response.status, headers: newHeaders });
}
```

### KV Cache-aside (Products API)

```javascript
async function getProducts(env, corsHeaders) {
  const cached = await env.CACHE.get('products:all');
  if (cached) {
    return new Response(cached, {
      headers: { ...corsHeaders, 'Content-Type': 'application/json', 'X-Products-Cache': 'HIT' }
    });
  }

  const result = await env.DB.prepare(
    'SELECT id, name, description, price, category, stock, created_at, updated_at FROM products ORDER BY name'
  ).all();

  const response = JSON.stringify({ products: result.results || [], count: result.results?.length || 0 });
  await env.CACHE.put('products:all', response, { expirationTtl: 600 });

  return new Response(response, {
    headers: { ...corsHeaders, 'Content-Type': 'application/json', 'X-Products-Cache': 'MISS' }
  });
}
```

Cache key: `products:all`. Invalidated on any product create/update/delete/seed via `env.CACHE.delete('products:all')`.

Note: `X-Cache` is stripped by Cloudflare. The custom header `X-Products-Cache` is used instead.

### Queue Processing (Order Processor)

```javascript
export default {
  async queue(batch, env, ctx) {
    for (const message of batch.messages) {
      try {
        await processOrder(message.body, env);
        message.ack();
      } catch (error) {
        console.error('Order processing failed:', error);
        message.retry();
      }
    }
  }
};
```

The order processor has no `fetch` handler for orders — it only processes queue messages. It writes to D1 (`orders`, `order_items` tables) and decrements stock. If stock is insufficient, it throws and the message is retried.

### D1 Patterns

```javascript
// Prepared statement with binding
const result = await env.DB.prepare(
  'INSERT INTO products (name, price, category, stock, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)'
).bind(name, price, category, stock, now, now).run();

// Last inserted ID
const newId = result.meta.last_row_id;

// Query single row
const row = await env.DB.prepare('SELECT * FROM products WHERE id = ?').bind(id).first();

// Query all rows
const { results } = await env.DB.prepare('SELECT * FROM products ORDER BY name').all();
```

### R2 Upload

```javascript
// Pass file (Blob) directly — file.stream() and file.arrayBuffer() are not reliable in this context
await env.UPLOADS.put(filename, file, {
  httpMetadata: { contentType: file.type },
  customMetadata: { uploadedAt: new Date().toISOString() }
});
```

### Handling Missing Content-Type on Upload

```javascript
let formData;
try {
  formData = await request.formData();
} catch {
  return new Response(JSON.stringify({ error: 'No file provided' }), {
    status: 400,
    headers: { 'Content-Type': 'application/json' }
  });
}
```

---

## Terraform Reference

### Zone (data source, not resource)

```hcl
# jsherron.com already exists — reference only
data "cloudflare_zone" "main" {
  account_id = var.account_id
  name       = var.zone_name
}

# All zone_id references use data source
zone_id = data.cloudflare_zone.main.id
```

### Worker Script with All Binding Types

```hcl
resource "cloudflare_workers_script" "api_gateway" {
  account_id = var.account_id
  name       = "demo-api-gateway"
  content    = file("${path.module}/workers/api-gateway.js")
  module     = true   # required for ES module format (export default)

  d1_database_binding {
    name        = "DB"
    database_id = cloudflare_d1_database.products.id
  }

  kv_namespace_binding {
    name         = "SESSIONS"
    namespace_id = cloudflare_workers_kv_namespace.sessions.id
  }

  r2_bucket_binding {
    name        = "UPLOADS"
    bucket_name = cloudflare_r2_bucket.uploads.name
  }

  # Queue binding uses 'binding' and 'queue', not 'name' and 'queue_name'
  queue_binding {
    binding = "ORDER_QUEUE"
    queue   = cloudflare_queue.orders.name
  }

  # Service binding to private worker
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
```

### Queue Resource

```hcl
resource "cloudflare_queue" "orders" {
  account_id = var.account_id
  name       = "demo-order-processing"   # attribute is 'name', not 'queue_name'
}
```

### Queue Consumer Registration

```hcl
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
  }
}
```

### Cache Rules (replacing Page Rules)

```hcl
resource "cloudflare_ruleset" "cache_rules" {
  zone_id     = data.cloudflare_zone.main.id
  name        = "Cache Rules"
  kind        = "zone"
  phase       = "http_request_cache_settings"

  rules {
    expression = "(http.host eq \"api.${var.zone_name}\" and starts_with(http.request.uri.path, \"/products\"))"
    action     = "set_cache_settings"
    enabled    = true

    action_parameters {
      cache = true
      edge_ttl {
        mode    = "override_origin"
        default = 300
      }
      browser_ttl {
        mode    = "override_origin"
        default = 300
      }
    }
  }
}
```

Note: Page Rules (`cloudflare_page_rule`) do not support account-owned tokens (error 1011). Use `cloudflare_ruleset` instead.

### D1 Schema Migration

```hcl
resource "null_resource" "d1_schema" {
  depends_on = [cloudflare_d1_database.products]

  triggers = {
    schema_hash = filemd5("${path.module}/db/schema.sql")
    database_id = cloudflare_d1_database.products.id
  }

  provisioner "local-exec" {
    command = "wrangler d1 execute demo-products --file=${path.module}/db/schema.sql --remote"
    environment = {
      CLOUDFLARE_API_TOKEN  = var.cloudflare_api_token
      CLOUDFLARE_ACCOUNT_ID = var.account_id
    }
  }
}
```

---

## Database Schema

```sql
CREATE TABLE IF NOT EXISTS products (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  description TEXT,
  price       DECIMAL(10,2) NOT NULL,
  category    TEXT DEFAULT 'general',
  stock       INTEGER DEFAULT 0,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS orders (
  id           TEXT PRIMARY KEY,        -- UUID
  customer_id  TEXT NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  status       TEXT DEFAULT 'pending',  -- pending → processing → completed
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS order_items (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id   TEXT NOT NULL,
  product_id INTEGER NOT NULL,
  quantity   INTEGER NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id)   REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
);
```

---

## Troubleshooting

### Error 1101 (Worker Uncaught Exception)
Caused by unawaited async calls inside try/catch. Ensure all route handlers are called with `await`:
```javascript
return await handleProducts(request, env, corsHeaders);  // correct
return handleProducts(request, env, corsHeaders);         // wrong — catch won't fire
```

### `env.BINDING` is undefined
The binding is either:
- Missing from the Terraform resource for that worker
- In the wrong worker's resource block
- Not yet applied (`terraform apply` needed)

Check with:
```bash
terraform state show cloudflare_workers_script.api_gateway | grep -A3 "binding"
```

### Queue Binding Attribute Names
Provider v4 uses `binding` and `queue`, not `name` and `queue_name`:
```hcl
queue_binding {
  binding = "ORDER_QUEUE"   # not 'name'
  queue   = "queue-name"    # not 'queue_name'
}
```

### Deployment State Detection

```bash
# List all managed resources
terraform state list

# Check if zone data source is loaded
terraform state show data.cloudflare_zone.main

# Check specific worker bindings
terraform state show cloudflare_workers_script.api_gateway
```

### Diagnostics

```bash
# Check DNS
dig api.jsherron.com
dig admin.jsherron.com

# Test worker routing
curl -s https://api.jsherron.com/api/products | jq .
curl -s -u admin:demo123 https://admin.jsherron.com/api/stats | jq .

# Real-time worker logs
wrangler tail demo-api-gateway
wrangler tail demo-products-api

# Run full test suite
make test
```

---

## Extension Patterns

### Adding a New API Endpoint

1. Add route in `workers/api-gateway.js`:
```javascript
} else if (path.startsWith('/api/newfeature')) {
  return await handleNewFeature(request, env, corsHeaders);
}
```

2. Implement handler returning JSON error responses (not plain text):
```javascript
async function handleNewFeature(request, env, corsHeaders) {
  // ...
  return new Response(JSON.stringify({ error: 'Not found' }), {
    status: 404,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}
```

3. Add test case to `scripts/tests/test.sh`.

### Adding a New KV Namespace

```hcl
resource "cloudflare_workers_kv_namespace" "analytics" {
  account_id = var.account_id
  title      = "demo-analytics"
}

# In the worker script resource:
kv_namespace_binding {
  name         = "ANALYTICS"
  namespace_id = cloudflare_workers_kv_namespace.analytics.id
}
```
