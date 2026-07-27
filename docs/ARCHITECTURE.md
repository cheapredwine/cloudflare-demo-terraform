# Architecture Overview

## System Diagram

See `docs/architecture.png` for the full visual diagram.

```
                        Client
                     (curl / browser)
                           │
                        HTTPS
                           │
               ┌───────────────────────┐
               │   Cloudflare Edge     │
               │                       │
               │  DNS                  │
               │  api.jsherron.com     │
               │  admin.jsherron.com   │
               │                       │
               │  Cache Rules          │
               │  /api/products* 5min  │
               │                       │
               │  Worker Routes        │
               │  api.*  → gateway     │
               │  admin.* → admin      │
               └───────────────────────┘
                     │           │
          ┌──────────┘           └──────────┐
          ▼                                 ▼
  ┌───────────────┐                ┌───────────────┐
  │  API Gateway  │                │  Admin Panel  │
  │ demo-api-     │                │ demo-admin-   │
  │ gateway       │                │ panel         │
  │               │                │               │
  │ Auth · Routing│                │ Basic Auth    │
  │ Upload · Orders│               │ Stats · Setup │
  └───────────────┘                └───────────────┘
          │                                │
          │ service binding                │
          ▼                                │
  ┌───────────────┐                        │
  │  Products API │ (no public route)      │
  │ demo-products │                        │
  │ -api          │                        │
  │               │                        │
  │ CRUD · Seed   │                        │
  │ KV Cache      │                        │
  └───────────────┘                        │
          │                                │
          │   send() ──────────────────────┼──┐
          │                                │  ▼
          │                         ┌───────────────┐
          │                         │ Order Processor│
          │                         │ demo-order-   │
          │                         │ processor     │
          │                         │               │
          │                         │ Queue Consumer│
          │                         │ D1 Write      │
          │                         └───────────────┘
          │                                │
          └────────────┬───────────────────┘
                       │
          ┌────────────┼────────────────────┐
          ▼            ▼           ▼        ▼
    ┌──────────┐ ┌──────────┐ ┌──────┐ ┌────────┐
    │    D1    │ │    KV    │ │  R2  │ │ Queue  │
    │ demo-    │ │ sessions │ │upload│ │ demo-  │
    │ products │ │ cache    │ │      │ │ order- │
    │          │ │ 10m TTL  │ │      │ │ proc.  │
    └──────────┘ └──────────┘ └──────┘ └────────┘
```

---

## Components

### Workers (Compute)

| Worker | Route | Purpose |
|--------|-------|---------|
| `demo-api-gateway` | `api.jsherron.com/*` | Entry point — CORS, auth, routing, upload, orders |
| `demo-admin-panel` | `admin.jsherron.com/*` | Admin UI — stats, product/order browser, DB setup |
| `demo-products-api` | none (service binding only) | Products CRUD — proxied from gateway via service binding |
| `demo-order-processor` | none (queue consumer) | Async — consumes queue, writes orders to D1, decrements stock |

### Storage

| Resource | Terraform Name | Purpose |
|----------|----------------|---------|
| D1 Database | `demo-products` | Products, orders, order_items tables |
| KV Namespace | `demo-sessions` | Session tokens (24h TTL) |
| KV Namespace | `demo-cache` | Product list cache (10min TTL) |
| R2 Bucket | `demo-platform-uploads` | Uploaded files |
| Queue | `demo-order-processing` | Async order delivery to processor |

### Network

| Resource | Details |
|----------|---------|
| Zone | `jsherron.com` — referenced as data source (pre-existing) |
| DNS A | `jsherron.com → 203.0.113.10` (proxied) |
| DNS AAAA | `api.jsherron.com → 100::` (proxied, Anycast) |
| DNS AAAA | `admin.jsherron.com → 100::` (proxied, Anycast) |
| Cache Rules | `/api/products*` 5min edge TTL; previously Page Rules |
| SSL | Strict mode, TLS 1.2+, Always HTTPS, Hotlink Protection |

---

## Data Flows

### Product List Request (cache miss → hit)
```
Client → api.jsherron.com → Cache Rules check
  → API Gateway Worker → service binding → Products API Worker
  → KV get("products:all") → MISS
  → D1 SELECT → results
  → KV put("products:all", results, 600s)
  → Response (X-Products-Cache: MISS)

Second request:
  → Products API Worker → KV get("products:all") → HIT
  → Response (X-Products-Cache: HIT)
```

### Order Submission (async)
```
Client → POST /api/orders → API Gateway
  → validate fields
  → generate UUID order_id
  → Queue.send({ order_id, customer_id, items, total })
  → return { order_id, status: "queued" }

  [async] Queue → Order Processor Worker
    → D1 INSERT orders
    → D1 INSERT order_items
    → D1 UPDATE products SET stock = stock - quantity
    → D1 UPDATE orders SET status = "completed"
```

### File Upload
```
Client → POST /api/upload (multipart/form-data)
  → API Gateway
  → R2.put(uuid-filename, fileBlob, { httpMetadata })
  → return { filename, size, type, url }
```

### Admin Request
```
Client → admin.jsherron.com/*
  → Admin Panel Worker
  → HTTP Basic Auth check (admin/demo123)
  → D1 queries for stats/products/orders
  → HTML dashboard or JSON response
```

---

## Key Patterns

### Service Binding (private service-to-service)
`demo-products-api` has no public Worker route. It is only reachable via a service binding from `demo-api-gateway`. The gateway rewrites `/api/products*` → `/products*` and calls `env.PRODUCTS_API.fetch(request)` internally. This keeps the products service private to the platform.

### KV Cache-aside
Products API uses a cache-aside pattern: check KV first, on miss query D1 and populate KV. Any mutation (create/update/delete/seed) deletes the cache key, ensuring consistency.

### Queue-based Decoupling
Orders are accepted synchronously and queued immediately. The gateway returns a response to the client without waiting for D1 writes or stock updates. The order processor worker handles the heavy work asynchronously. Terraform applies a queue consumer registration step so `demo-order-processor` stays attached to `demo-order-processing`.

### Zone as Data Source
`jsherron.com` is a pre-existing zone referenced via Terraform `data` source, not created by Terraform. Running `terraform destroy` will not delete the zone.

---

## Security

- **TLS:** Strict mode — Cloudflare to origin encrypted, TLS 1.2 minimum
- **Always HTTPS:** HTTP redirected to HTTPS at the edge
- **Admin auth:** HTTP Basic Auth (`admin`/`demo123`) — demo only, not for production
- **Session auth:** UUID tokens stored in KV with 24h expiry — demo only (accepts any credentials)
- **CORS:** Open (`*`) on all API gateway responses — demo only
- **Hotlink protection:** Enabled at zone level
