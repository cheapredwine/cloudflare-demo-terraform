# Cloudflare Demo Platform - Agent Guide

## Project Overview

Terraform-based e-commerce demo on Cloudflare's edge stack. Deploys 4 Workers, D1 DB, 2 KV namespaces, R2 bucket, and Queue to a single zone.

## Architecture

- **API Gateway Worker** (`api-gateway.js`) - Routes to products/orders/upload/auth via service bindings
- **Products API Worker** (`products-api.js`) - CRUD + KV caching + seed endpoint
- **Order Processor Worker** (`order-processor.js`) - Queue consumer, writes to D1, decrements stock
- **Admin Panel Worker** (`admin-panel.js`) - Basic auth dashboard with DB init + seed buttons

**Storage:**
- D1: `demo-products` (products, orders, order_items tables)
- KV: `demo-sessions` (auth), `demo-cache` (product list cache, 10 min TTL)
- R2: `demo-platform-uploads` (file uploads)
- Queue: `demo-order-processing` (async order workflow)

**DNS:**
- `api.{zone}` → API Gateway
- `admin.{zone}` → Admin Panel

## Admin Access

- **URL:** `https://admin.{zone}`
- **Username:** `admin`
- **Password:** `demo123`

After deploy, visit admin panel → click "Initialize Database" → click "Load Sample Data".

## File Layout

```
main.tf                  # All resources (deprecated resources fixed to cloudflare_workers_*)
workers/
  api-gateway.js         # Request routing, CORS, service bindings to products_api
  products-api.js        # CRUD, KV cache, seed endpoint
  order-processor.js     # Queue batch handler, D1 writes, stock management
  admin-panel.js         # HTML dashboard, basic auth (admin/demo123)
db/schema.sql            # D1 schema (products, orders, order_items)
run-demo.sh              # Deploy/test/reset/destroy management script
terraform-demo.sh        # Terraform feature demos (idempotency, drift, state, etc.)
terraform.tfvars         # Account credentials (gitignored)
```

## Key Decisions

1. **Deprecated resources fixed** - Replaced `cloudflare_worker_script` with `cloudflare_workers_script` and `cloudflare_worker_route` with `cloudflare_workers_route` to eliminate deprecation warnings.

2. **Service binding pattern** - API Gateway uses `env.PRODUCTS_API.fetch()` to call products worker internally. Rewrites `/api/products` → `/products` before proxying. Strips host header to avoid errors.

3. **Cache invalidation** - Products API clears `products:all` KV key on any write (create/update/delete/seed). First GET after write shows `X-Products-Cache: MISS`, subsequent show `HIT`.

4. **R2 bucket cleanup** - `null_resource.empty_r2_on_destroy` runs Python script to delete all objects before bucket destruction. Cloudflare refuses to delete non-empty R2 buckets.

5. **D1 schema migration** - `null_resource.d1_schema` runs `wrangler d1 execute` with `IF NOT EXISTS` so it's idempotent. Triggers on schema file hash change.

## API Endpoints

```bash
# Products
curl https://api.{zone}/api/products              # GET (cached)
curl -X POST https://api.{zone}/api/products \
  -H "Content-Type: application/json" \
  -d '{"name":"X","price":9.99,"stock":10}'
curl https://api.{zone}/api/products/1            # GET single
curl -X POST https://api.{zone}/api/products/seed # Load 5 sample products

# Orders (queued async)
curl -X POST https://api.{zone}/api/orders \
  -H "Content-Type: application/json" \
  -d '{"customer_id":"demo","items":[{"product_id":1,"quantity":1,"unit_price":9.99}],"total":9.99}'

# Auth
curl -X POST https://api.{zone}/api/auth/login \
  -d '{"email":"a@b.com","password":"pass"}'
curl https://api.{zone}/api/auth/me \
  -H "Authorization: Bearer <session-id>"

# Upload
curl -X POST https://api.{zone}/api/upload -F "file=@image.jpg"
```

## Terraform Commands

```bash
terraform init -upgrade          # Update providers
terraform plan                    # Preview changes
terraform apply                   # Deploy
terraform apply -auto-approve     # Deploy without prompt
terraform destroy                 # Remove all resources
terraform state list              # List managed resources
terraform output                  # Show URLs and IDs
terraform output -json            # Machine-readable outputs
terraform workspace list          # Show workspaces
```

## Demo Scripts

### run-demo.sh — Platform Lifecycle
Manages deploy, test, reset, destroy. Use for deploy and teardown.

```bash
./run-demo.sh deploy         # Deploy platform (terraform init + apply + test)
./run-demo.sh deploy --demo  # Deploy + run sample API calls
./run-demo.sh test           # Verify endpoints responding
./run-demo.sh reset          # Clear DB, reload sample data (keeps infra)
./run-demo.sh destroy        # Tear down everything (with confirmation)
./run-demo.sh fresh          # Destroy + redeploy
```

### terraform-demo.sh — Terraform Concepts
Showcases Terraform features. Assumes infrastructure is deployed.

```bash
./terraform-demo.sh idempotency     # Apply twice, 0 changes second time
./terraform-demo.sh drift-detect    # Manual dashboard change → detect → reconcile
./terraform-demo.sh state-inspect   # List resources, show state, outputs
./terraform-demo.sh targeted        # Deploy single resource with -target
./terraform-demo.sh plan-file       # Save plan, review, apply exact plan
./terraform-demo.sh refresh-only    # Detect drift without changing
./terraform-demo.sh taint-replace   # Force recreation of resource
./terraform-demo.sh var-override staging.example.com # CLI variable override
./terraform-demo.sh graph           # Generate dependency graph
./terraform-demo.sh workspaces      # Create staging workspace
./terraform-demo.sh all             # Run all demos sequentially (~10 min)
```

### test.sh — Integration Validation
Runs end-to-end API + admin validation, including queue consumer health and async order persistence checks.

```bash
./test.sh                   # Full integration verification after deploy/changes
```

## Recommended Demo Workflow

Deploy → Platform Demos → Terraform Demos → Teardown

```bash
# 1. Deploy platform
./run-demo.sh deploy

# 2. Platform demos
./run-demo.sh test          # Verify endpoints
./run-demo.sh deploy --demo # Run sample API calls

# 3. Terraform demos
./terraform-demo.sh state-inspect
./terraform-demo.sh drift-detect    # Requires manual dashboard change
./terraform-demo.sh idempotency
./terraform-demo.sh plan-file
./terraform-demo.sh refresh-only

# 4. Teardown
./run-demo.sh destroy
```

**Total runtime:** ~5-10 minutes for full cycle.

**Note:** `terraform-demo.sh` does NOT auto-teardown. Always end with `./run-demo.sh destroy`.

## Environment Setup

Requires `terraform.tfvars`:
```hcl
cloudflare_api_token = "token"
account_id          = "id"
zone_name           = "domain.com"
```

Or set `TF_VAR_cloudflare_api_token` env var and only put `account_id` + `zone_name` in tfvars.

**Token permissions needed:**
- Zone:Edit, DNS:Edit, Zone Settings:Edit
- Workers Scripts:Edit, Workers Routes:Edit
- Account → R2:Edit
- Account → Workers KV:Edit
- Account → D1:Edit
- Account → Queues:Edit

*Note: Account-level permissions (R2, KV, D1, Queues) must be under "Account resources", not "Zone resources".*

## Common Issues

- **R2 destroy fails** - Bucket not empty. The `null_resource.empty_r2_on_destroy` handles this automatically.
- **Worker routes 404** - Ensure DNS records exist and are proxied (orange cloud).
- **D1 schema not applied** - Requires `wrangler` CLI installed and authenticated.
- **Cache shows MISS always** - Check that KV namespace is bound correctly.

## Cost

~$3-5/month for Pro/Free plan (Workers free tier, D1 free tier, KV free tier, R2 free tier). Zone cost depends on plan.

## Next Session Notes

- All deprecated resources fixed, no warnings
- Zone: jsherron.com (ID: 6bcf8859da225392d8fae3351eb5de3e)
- Account: 1ddebf6f9507d3fc9052158be9d42dee
- Terraform provider v4.52.8
- Run `./run-demo.sh deploy` to deploy infrastructure
