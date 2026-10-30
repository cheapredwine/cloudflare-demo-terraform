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

After deploy, visit admin panel → click "Load Sample Data".

## File Layout

```
providers.tf             # Terraform + provider config (Cloudflare provider v5)
variables.tf             # Input variables
zone.tf                  # Existing zone data source (v5 filter shape)
dns.tf                   # DNS records (cloudflare_dns_record + moved blocks)
storage.tf               # D1, KV, R2, Queue resources
workers.tf               # cloudflare_worker + cloudflare_worker_version (v5 pattern)
routes.tf                # Worker routes
queue-consumer.tf        # cloudflare_queue_consumer (first-class v5 resource)
migrations.tf            # terraform_data: D1 schema apply + R2 destroy-time cleanup
ai-gateway.tf            # AI Gateway resource
waf.tf                   # Managed WAF, custom WAF, rate limiting, redirects rulesets
cdn.tf                   # Cache rules + zone settings (cache_level, min_tls_version)
load_balancer.tf         # Health monitor, origin pool, zone load balancer
outputs.tf               # Terraform outputs
tests/main.tftest.hcl    # 16 mocked terraform test cases (make verify)
scripts/empty-r2.py      # R2 destroy-time bucket emptying (token via env only)
workers/
  api-gateway.js         # Request routing, CORS, service bindings to products_api
  products-api.js        # CRUD, KV cache, seed endpoint, /products/summary (AI)
  order-processor.js     # Queue batch handler, D1 writes, stock management
  admin-panel.js         # HTML dashboard, basic auth (admin/demo123)
db/schema.sql            # D1 schema (products, orders, order_items)
scripts/lifecycle/       # Lifecycle scripts (run-demo.sh/ps1)
scripts/tests/           # Integration scripts (test.sh/ps1)
scripts/demos/           # Demo scripts (terraform-demo, latency, analytics)
Makefile                 # Primary entrypoints (make deploy/test/verify/destroy/etc.)
terraform.tfvars         # Account credentials (gitignored)
```

## Key Decisions

1. **Provider v5 (OpenAPI-generated)** - Migrated from v4.52 to v5.28. Notable v5 shapes: `cloudflare_record` → `cloudflare_dns_record`; Workers use `cloudflare_worker` + `cloudflare_worker_version` (deploy=true sends 100% of traffic); `cloudflare_queue` uses `queue_name`; nested objects are attributes (`= {}` / `= []`), not blocks; zone data source uses `filter`; AI Gateway's name is its `id`.

2. **State continuity** - `moved` blocks in dns.tf and routes.tf map v4 state (cloudflare_record.*, cloudflare_workers_script.*) to the v5 resources. First apply after upgrade must show those as renames, not destroys.

3. **Service binding pattern** - API Gateway uses `env.PRODUCTS_API.fetch()` to call products worker internally. Rewrites `/api/products` → `/products` before proxying. Strips host header to avoid errors.

4. **Cache invalidation** - Products API clears `products:all` KV key on any write (create/update/delete/seed). First GET after write shows `X-Products-Cache: MISS`, subsequent show `HIT`.

5. **R2 cleanup at destroy** - `terraform_data.r2_cleanup` destroy-time provisioner runs `scripts/empty-r2.py` (the API refuses to delete non-empty buckets; v5 has no force-destroy). Terraform forbids non-self references in destroy provisioners, so the token comes from the calling shell's `CLOUDFLARE_API_TOKEN` (run-demo.sh exports it from terraform.tfvars). Never stored in state/triggers.

6. **D1 schema migration** - `terraform_data.d1_schema` runs `wrangler d1 execute` with `IF NOT EXISTS` (idempotent), triggering on schema file hash change. Token passed via provisioner environment only.

7. **Queue consumer** - First-class `cloudflare_queue_consumer` resource replaces the old wrangler-based null_resource.

8. **AI Gateway wiring** - `cloudflare_ai_gateway` (id = "demo-ai-gateway") with cache TTL/retries/logging; products-api has a `type = "ai"` Workers AI binding plus `AI_GATEWAY_ID` plain-text binding, and `/api/products/summary` calls `env.AI.run(..., { gateway: { id } })`.

9. **Zone settings** - v5's one-resource-per-setting `cloudflare_zone_setting` replaces the removed v4 `cloudflare_zone_settings_override` (cache_level=aggressive, min_tls_version=1.2).

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

Shell and PowerShell versions are maintained in parallel (`*.sh` and matching `*.ps1`). Update both files whenever script behavior changes.
Canonical scripts live under `scripts/`. Preferred CLI entrypoints use `make`.

### run-demo.sh — Platform Lifecycle
Manages deploy, test, reset, destroy. Use for deploy and teardown.

```bash
make deploy                  # Deploy platform (terraform init + apply + smoke checks)
make deploy-demo             # Deploy + run sample API calls
make smoke                   # Verify endpoints responding
make reset                   # Clear DB, reload sample data (keeps infra)
make destroy                 # Tear down everything (with confirmation)
make fresh                   # Destroy + redeploy
./scripts/lifecycle/run-demo.ps1 deploy # PowerShell equivalent
```

### terraform-demo.sh — Terraform Concepts
Showcases Terraform features. Assumes infrastructure is deployed.

```bash
./scripts/demos/terraform-demo.sh idempotency     # Apply twice, 0 changes second time
./scripts/demos/terraform-demo.sh drift-detect    # Manual dashboard change → detect → reconcile
./scripts/demos/terraform-demo.sh state-inspect   # List resources, show state, outputs
./scripts/demos/terraform-demo.sh targeted        # Deploy single resource with -target
./scripts/demos/terraform-demo.sh plan-file       # Save plan, review, apply exact plan
./scripts/demos/terraform-demo.sh refresh-only    # Detect drift without changing
./scripts/demos/terraform-demo.sh taint-replace   # Force recreation of resource
./scripts/demos/terraform-demo.sh var-override staging.example.com # CLI variable override
./scripts/demos/terraform-demo.sh graph           # Generate dependency graph
./scripts/demos/terraform-demo.sh workspaces      # Create staging workspace
make tf-all                                       # Run all demos sequentially (~10 min)
./scripts/demos/terraform-demo.ps1 all            # PowerShell equivalent
```

### test.sh — Integration Validation
Runs end-to-end API + admin validation, including queue consumer health and async order persistence checks.

```bash
make test                              # Full integration verification after deploy/changes
./scripts/tests/test.ps1              # PowerShell equivalent
```

## Recommended Demo Workflow

Deploy → Platform Demos → Terraform Demos → Teardown

```bash
# 1. Deploy platform
make deploy

# 2. Platform demos
make smoke                  # Verify endpoints
make deploy-demo            # Run sample API calls

# 3. Terraform demos
./scripts/demos/terraform-demo.sh state-inspect
./scripts/demos/terraform-demo.sh drift-detect    # Requires manual dashboard change
./scripts/demos/terraform-demo.sh idempotency
./scripts/demos/terraform-demo.sh plan-file
./scripts/demos/terraform-demo.sh refresh-only

# 4. Teardown
make destroy
```

**Total runtime:** ~5-10 minutes for full cycle.

**Note:** `terraform-demo.sh` does NOT auto-teardown. Always end with `make destroy`.

## Environment Setup

Requires `terraform.tfvars`:
```hcl
cloudflare_api_token = "token"
account_id          = "id"
zone_name           = "domain.com"
```

Or set `TF_VAR_cloudflare_api_token` env var and only put `account_id` + `zone_name` in tfvars.

**Token permissions needed:**
- Zone:Edit, DNS:Edit, Zone Settings:Edit, Zone WAF:Edit, Load Balancing:Edit (zone), Workers Routes:Edit
- Workers Scripts:Edit
- Account → R2:Edit, Workers KV:Edit, D1:Edit, Queues:Edit, AI:Edit (AI Gateway), Load Balancing:Edit (account: monitors/pools)

*Note: Account-level permissions (R2, KV, D1, Queues, AI, LB pools/monitors) must be under "Account resources", not "Zone resources".*

## Common Issues

- **R2 destroy fails** - Bucket not empty. The `terraform_data.r2_cleanup` destroy provisioner handles it, but needs `CLOUDFLARE_API_TOKEN` in the calling shell (`make destroy` / run-demo.sh handle this).
- **Worker routes 404** - Ensure DNS records exist and are proxied (orange cloud).
- **D1 schema not applied** - Requires `wrangler` CLI installed and authenticated.
- **Cache shows MISS always** - Check that KV namespace is bound correctly.
- **v5 apply shows destroys for DNS/Workers** - The `moved` blocks should prevent this; if you see destroys instead of renames, re-check `moved` block source addresses against your state (`terraform state list`).
- **AI summary returns 503** - Workers AI not enabled on the account, or the account lacks AI:Edit on the token.

## Cost

~$3-5/month for Pro/Free plan (Workers free tier, D1 free tier, KV free tier, R2 free tier). Zone cost depends on plan.

## Next Session Notes

- Migrated to Cloudflare provider v5 (v5.28.1), Terraform CLI 1.17
- `make verify` = fmt + validate + 16 mocked terraform tests (offline)
- New: managed/custom/rate-limit WAF, cache rules + zone settings, load balancer, AI Gateway + Workers AI summary endpoint
- First real `terraform apply` must show the moved blocks as renames (DNS records + 4 workers); verify with `terraform plan` before applying
- Zone: jsherron.com
- Account: (test account)
- Run `make deploy` to deploy infrastructure
