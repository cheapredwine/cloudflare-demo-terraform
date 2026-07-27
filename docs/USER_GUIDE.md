# Cloudflare Demo Platform — User Guide

## Live URLs

| Endpoint | URL |
|----------|-----|
| API Gateway | https://api.jsherron.com |
| Admin Panel | https://admin.jsherron.com |

Admin credentials: `admin` / `demo123`

---

## Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) installed
- [Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/) installed
- Cloudflare account with an existing zone
- API token (see token permissions below)

### Token Permissions Required

| Resource | Permission |
|----------|------------|
| Account > Workers Scripts | Edit |
| Account > Workers KV Storage | Edit |
| Account > Workers R2 Storage | Edit |
| Account > D1 | Edit |
| Account > Queues | Edit |
| Zone > Zone Settings | Edit |
| Zone > DNS | Edit |
| Zone > Workers Routes | Edit |
| Zone > Cache Rules | Edit |

### Setup

```bash
git clone https://github.com/cheapredwine/cloudflare-demo-terraform
cd cloudflare-demo-terraform

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

`terraform.tfvars`:
```hcl
cloudflare_api_token = "your-api-token"
account_id           = "your-account-id"
zone_name            = "yourdomain.com"
```

### Deploy

```bash
./run-demo.sh deploy
```

This runs `terraform init && apply`, waits for DNS, and tests endpoints. The D1 schema is applied automatically via `wrangler d1 execute` during `terraform apply` — no manual database initialization is required.

Deploy also auto-attaches `demo-order-processor` as consumer for `demo-order-processing`.

### Initialize Demo Data

After deploy, seed the product catalog:

```bash
# Via script
./run-demo.sh reset

# Or via API directly
curl -X POST https://api.jsherron.com/api/products/seed
```

Or use the admin panel: visit https://admin.jsherron.com → click **Load Sample Data**.

---

## Demo Scripts

| Script | Purpose |
|--------|---------|
| `./run-demo.sh deploy` | Deploy all infrastructure |
| `./run-demo.sh reset` | Re-seed data, keep infrastructure |
| `./run-demo.sh test` | Endpoint health checks + queue consumer check |
| `./run-demo.sh destroy` | Tear down all Terraform-managed resources |
| `./run-demo.sh fresh` | Destroy + redeploy |
| `./run-demo.sh deploy --demo` | Deploy then run a demo API flow |
| `./test.sh` | Full 45-test production integration suite |
| `./demo-latency.sh` | Cache HIT vs MISS latency comparison |
| `./demo-analytics.sh` | Generate traffic + print dashboard links |

---

## Demo Scenarios

### Scenario 1: Full Platform Demo (15 min)

**"A complete e-commerce backend running entirely at the edge."**

**1. Architecture (3 min)**
- Open `docs/architecture.png`
- 4 Workers, D1, KV, R2, Queue — all Cloudflare-native
- No servers, no VMs, no containers

**2. Admin Panel (2 min)**
- Visit https://admin.jsherron.com (admin / demo123)
- Show live stats, product catalog, order history

**3. API Demo (5 min)**
```bash
# Seed sample products
curl -X POST https://api.jsherron.com/api/products/seed | jq .

# List products
curl https://api.jsherron.com/api/products | jq .

# Create an order (async via queue)
curl -X POST https://api.jsherron.com/api/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"demo","items":[{"product_id":1,"quantity":1,"unit_price":24.99}],"total":24.99}' | jq .

# Upload a file to R2
curl -X POST https://api.jsherron.com/api/upload -F "file=@README.md" | jq .

# Auth flow
SESSION=$(curl -s -X POST https://api.jsherron.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"demo@example.com","password":"demo"}' | jq -r .session_id)
curl https://api.jsherron.com/api/auth/me -H "Authorization: Bearer $SESSION" | jq .
```

**4. Cache Demo (3 min)**
```bash
./demo-latency.sh
```
Shows average MISS latency (D1 query) vs HIT latency (KV), with speedup ratio.

**5. Analytics (2 min)**
```bash
./demo-analytics.sh
```
Generates ~75 requests across all workers, prints direct links to Workers Analytics dashboard.

---

### Scenario 2: Developer Deep-Dive (10 min)

**"Modern edge-native development."**

1. **Code walkthrough** — `workers/api-gateway.js`: routing, CORS, service binding call
2. **Service binding** — show `demo-products-api` has no public route; proxied privately
3. **Queue pattern** — `workers/order-processor.js`: queue consumer, stock decrement
4. **Terraform** — `main.tf`: all infra as code, one file, one apply
5. **Live deploy** — run `./run-demo.sh deploy` and show output

---

### Scenario 3: Operations Demo (8 min)

**"Zero infrastructure management."**

1. Show `terraform plan -destroy` — list of what gets cleaned up
2. Run `./test.sh` — 45 automated production tests
3. Open Cloudflare Dashboard → Workers & Pages → show analytics, logs, CPU time
4. Reset between demos: `./run-demo.sh reset` (seconds, not minutes)

---

## API Reference

### Products

```bash
# List (10min KV cache, X-Products-Cache: HIT/MISS)
curl https://api.jsherron.com/api/products

# Get single
curl https://api.jsherron.com/api/products/1

# Create
curl -X POST https://api.jsherron.com/api/products \
  -H "Content-Type: application/json" \
  -d '{"name":"Widget","price":29.99,"category":"electronics","stock":50}'

# Update
curl -X PUT https://api.jsherron.com/api/products/1 \
  -H "Content-Type: application/json" \
  -d '{"price":24.99,"stock":75}'

# Delete
curl -X DELETE https://api.jsherron.com/api/products/1

# Seed 5 sample products
curl -X POST https://api.jsherron.com/api/products/seed
```

### Orders

```bash
# Create order (queued for async processing)
curl -X POST https://api.jsherron.com/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "cust_123",
    "items": [{"product_id": 1, "quantity": 2, "unit_price": 24.99}],
    "total": 49.98
  }'
```

### Auth

```bash
# Login (accepts any email/password — demo only)
curl -X POST https://api.jsherron.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"any"}'

# Get session user
curl https://api.jsherron.com/api/auth/me \
  -H "Authorization: Bearer <session-id>"
```

### Upload

```bash
curl -X POST https://api.jsherron.com/api/upload \
  -F "file=@yourfile.jpg"
```

### Admin Panel API

```bash
# Stats
curl -u admin:demo123 https://admin.jsherron.com/api/stats

# Products (last 10)
curl -u admin:demo123 https://admin.jsherron.com/api/products

# Orders (last 10)
curl -u admin:demo123 https://admin.jsherron.com/api/orders

# Initialize/reset DB schema
curl -X POST -u admin:demo123 https://admin.jsherron.com/setup
```

---

## Troubleshooting

**"terraform.tfvars not found"**
```bash
cp terraform.tfvars.example terraform.tfvars
# Fill in cloudflare_api_token, account_id, zone_name
```

**"Authentication error" on apply**
Check your token has all required permissions (see Quick Start above).

**"jsherron.com already exists" on apply**
Normal — the zone is pre-existing and referenced as a data source. The error means a previous session tried to create it. Run `terraform apply` again; it will skip zone creation.

**API returns `error code: 1101`**
Worker threw an uncaught exception. Check Workers logs:
```bash
wrangler tail demo-api-gateway
```

**"Database not initialized" in admin panel**
Run `terraform apply` — the D1 schema is applied automatically. Or manually:
```bash
curl -X POST -u admin:demo123 https://admin.jsherron.com/setup
```

**"No sample data"**
```bash
curl -X POST https://api.jsherron.com/api/products/seed
```

**Logs and debugging**
```bash
# Real-time worker logs
wrangler tail demo-api-gateway
wrangler tail demo-products-api
wrangler tail demo-admin-panel
wrangler tail demo-order-processor

# Dashboard
# Workers & Pages → [worker name] → Logs tab
```

---

## Teardown

Before destroying, review what will be deleted:

```bash
terraform plan -destroy
```

This removes: D1 database (all data), KV namespaces, R2 bucket, Queue, all 4 Workers, Worker routes, Cache Rules, and DNS records for `api.*`, `admin.*`. The `jsherron.com` zone itself is NOT deleted (it's a data source).

```bash
./run-demo.sh destroy
```

---

## Cost Notes

The zone (`jsherron.com`) is pre-existing — no zone cost is added by this demo. Incremental costs during demo use:

| Component | Free tier | Overage |
|-----------|-----------|---------|
| Workers | 100K req/day | $0.50/million |
| D1 | 5M reads, 100K writes/day | $0.001/million reads |
| KV | 100K reads/day | $0.50/million reads |
| R2 | 10GB storage, 1M ops/month | $0.015/GB |
| Queues | 1M ops/month | $0.40/million |

A single demo session generates well under free tier limits. Keep the environment running between demos (`./run-demo.sh reset`) rather than destroying and redeploying to minimize apply time.
