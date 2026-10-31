# Cloudflare Demo Platform

> ⚠️ **NOT OFFICIAL CLOUDFLARE.** Not affiliated with or endorsed by Cloudflare, Inc.
> NO WARRANTIES, EXPRESS OR IMPLIED. Effectively untested demo code — read everything
> and dry-run before you run. You assume all risk. See [DISCLAIMER.md](./DISCLAIMER.md).


A complete e-commerce platform demo built with Cloudflare's edge computing stack. This Terraform configuration creates a production-ready setup showcasing:

- **Multi-Zone Architecture** with API gateway pattern
- **Edge Computing** with Workers for all business logic
- **Distributed Storage** using D1, KV, R2, and Queues
- **Security & Performance** with WAF, rate limiting, and cache rules
- **Load Balancing** with health monitors and failover
- **AI Gateway** with a Workers AI catalog summary endpoint
- **Real-time Features** and async processing

Built on the **Cloudflare Terraform provider v5** (OpenAPI-generated, full API coverage) using the modern `cloudflare_worker` + `cloudflare_worker_version` pattern.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Frontend App   │    │   Admin Panel   │    │   File Uploads  │
│ demo-platform.  │    │ admin.demo-     │    │ uploads.demo-   │
│   example       │    │ platform.example│    │ platform.example│
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                    ┌─────────────────┐
                    │   API Gateway   │
                    │ api.demo-       │
                    │ platform.example│
                    └─────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │ Products API│  │Order Processor│  │   Auth API  │
    │  (Worker)   │  │   (Worker)    │  │  (Worker)   │
    └─────────────┘  └─────────────┘  └─────────────┘
              │              │              │
    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
    │     D1      │  │   Queues    │  │     KV      │
    │  Database   │  │ (Async Ops) │  │ (Sessions)  │
    └─────────────┘  └─────────────┘  └─────────────┘
                             │
                    ┌─────────────┐
                    │     R2      │
                    │   Storage   │
                    └─────────────┘
```

## Features

### 🏗️ Infrastructure
- **Cloudflare Zone** with Enterprise features
- **DNS Records** for all services
- **SSL/TLS** with strict security policies
- **Cache Rules** for optimal caching

### ⚡ Edge Computing
- **API Gateway Worker** - Request routing, auth, CORS
- **Products API Worker** - CRUD operations with caching
- **Order Processing Worker** - Async order handling
- **Admin Panel Worker** - Management interface

### 💾 Storage & Data
- **D1 Database** - SQL database for products/orders
- **KV Namespaces** - Session management and caching
- **R2 Buckets** - File uploads and static assets
- **Queues** - Async order processing workflow

### 🔒 Security & Performance
- **Managed WAF** - Cloudflare Managed Ruleset
- **Custom WAF Rules** - path scanner blocking, challenges, IP allowlisting
- **Rate Limiting** - per-IP limits on `/api/*`
- **Edge Caching** - cache rules + aggressive cache level, sub-second response times

### ⚖️ Load Balancing
- **Health Monitor** - HTTP probes against `/health`
- **Origin Pool** - failover-ready pool with minimum origins
- **Zone Load Balancer** - `app.<zone>` with steering policy

### 🤖 AI Gateway
- **AI Gateway** (`demo-ai-gateway`) - caching (1h TTL), retries, request logging
- **Workers AI** - `GET /api/products/summary` generates an LLM catalog summary through the gateway (key-free, Workers AI credits)

## Quick Start (Demo Workflow)

This repo is designed for demos. Deploy, run demos, tear down.

PowerShell equivalents exist for every user-facing shell script (`*.sh` and matching `*.ps1`). Keep both versions updated together.
Canonical script implementations live under `scripts/`.

Terraform is organized by concern across multiple files (`providers.tf`, `dns.tf`, `storage.tf`, `workers.tf`, `routes.tf`, `migrations.tf`, etc.) for readability.

### Step 1: Configure
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit with your API token, account ID, and zone
```

### Step 2: Verify Config (offline)
```bash
make verify   # fmt check + validate + terraform test (mocked, no credentials)
```

### Step 3: Deploy Platform
```bash
make deploy
```

Deploy now auto-registers Queue consumer (`demo-order-processor`) and fails fast if consumer is missing.

After deploy completes, access the admin panel:
- **URL:** `https://admin.your-domain.com`
- **Username:** `admin`
- **Password:** `demo123`

Click "Load Sample Data" to get started.

### Step 4: Run Demos

**Platform demos** (API, admin panel, workers):
```bash
make smoke       # Verify endpoints + queue consumer health
make deploy-demo # Run sample API calls
make test        # Full integration validation (async order persistence)
```

```powershell
./scripts/lifecycle/run-demo.ps1 test
./scripts/lifecycle/run-demo.ps1 deploy --demo
./scripts/tests/test.ps1
```

Use `make smoke` for fast checks. Use `make test` for deeper API + admin integration coverage.

**Terraform demos** (infrastructure as code concepts):
```bash
./scripts/demos/terraform-demo.sh state-inspect   # Show state and outputs
./scripts/demos/terraform-demo.sh drift-detect    # Detect manual dashboard changes
./scripts/demos/terraform-demo.sh idempotency     # Apply twice, 0 changes
./scripts/demos/terraform-demo.sh targeted        # Deploy single resource
./scripts/demos/terraform-demo.sh plan-file       # Save and apply exact plan
./scripts/demos/terraform-demo.sh refresh-only    # Detect drift without changing
./scripts/demos/terraform-demo.sh taint-replace   # Force recreation
./scripts/demos/terraform-demo.sh var-override staging.example.com  # Override variables
./scripts/demos/terraform-demo.sh graph           # Dependency graph
./scripts/demos/terraform-demo.sh workspaces      # Multiple environments
```

```powershell
./scripts/demos/terraform-demo.ps1 state-inspect
./scripts/demos/terraform-demo.ps1 all
```

Run all Terraform demos:
```bash
make tf-all
```

### Step 5: Teardown
```bash
make destroy
```

> The R2 bucket is emptied automatically at destroy time; `make destroy` exports
> `CLOUDFLARE_API_TOKEN` from `terraform.tfvars` for the cleanup step. Running
> raw `terraform destroy` requires that env var to be set yourself.

**Total runtime:** ~5-10 minutes for full deploy + demos + destroy.

---

## Prerequisites
- [Terraform](https://www.terraform.io/) >= 1.9 (tested with 1.17)
- [Cloudflare account](https://cloudflare.com) with zone access
- API token with: Zone:Edit, DNS:Edit, Zone Settings:Edit, Zone WAF:Edit, Workers Scripts:Edit, Workers Routes:Edit, Load Balancers:Edit (zone + account), Account AI:Edit, D1:Edit, R2:Edit, KV:Edit, Queues:Edit

> Note: Account-level permissions (R2, KV, D1, Queues, AI Gateway) must be under
> "Account resources", not "Zone resources".

## Architecture

## API Endpoints

Quick samples below. Full reference in `docs/API.md`.

### Products API
```bash
# Get all products
curl https://api.your-domain.com/api/products

# Create product
curl -X POST https://api.your-domain.com/api/products \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Product", "price": 19.99, "stock": 100}'

# Get specific product
curl https://api.your-domain.com/api/products/1

# AI catalog summary (Workers AI via AI Gateway)
curl https://api.your-domain.com/api/products/summary
```

### Orders API
```bash
# Create order
curl -X POST https://api.your-domain.com/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "customer_id": "cust123",
    "items": [{"product_id": 1, "quantity": 2, "unit_price": 19.99}],
    "total": 39.98
  }'
```

### Authentication
```bash
# Login
curl -X POST https://api.your-domain.com/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# Get user info
curl https://api.your-domain.com/api/auth/me \
  -H "Authorization: Bearer <session-id>"
```

### File Upload
```bash
# Upload file
curl -X POST https://api.your-domain.com/api/upload \
  -F "file=@image.jpg"
```

## Customization

### Environment Variables
Workers support bindings defined in `workers.tf` (v5 `cloudflare_worker_version`
`bindings` attribute). Add a binding to the `workers` local and, for secrets,
use `type = "secret_text"` with a sensitive variable:

```hcl
# Add to variables.tf
variable "stripe_secret_key" {
  description = "Stripe secret key"
  type        = string
  sensitive   = true
}
```

```hcl
# Add to the worker's bindings list in workers.tf
{ type = "secret_text", name = "STRIPE_SECRET_KEY", text = var.stripe_secret_key }
```

### Adding New Workers
1. Create worker file in `workers/`
2. Add an entry to the `workers` local in `workers.tf` (file, compatibility date, bindings)
3. The `cloudflare_worker` and `cloudflare_worker_version` resources pick it up automatically
4. Configure routes in `routes.tf` if the worker needs a zone route

### Testing

Two layers:

- **`make verify`** — lint (shellcheck, shfmt, JS/Python syntax), config-content guards, `terraform fmt -check`, `terraform validate`, and `terraform test` (23 mocked test cases in `tests/main.tftest.hcl` covering DNS, storage, workers/bindings/observability, routes, queue consumer, WAF, stable rule `ref`s, cache, zone settings, load balancing, AI Gateway, outputs, variable overrides, and negative tests proving each input validation fires). No credentials needed. CI runs the identical chain via [.github/workflows/verify.yml](./.github/workflows/verify.yml) on push/PR.
- **`make test`** — the deployed-platform integration suite (`scripts/tests/test.sh`), including the AI summary endpoint check.

### Scaling & Performance
- **D1 Scaling**: Automatic with read replicas
- **KV Scaling**: Global edge replication
- **R2 Scaling**: Unlimited object storage
- **Worker Scaling**: Millions of requests/second

## Monitoring

### Built-in Analytics
- Worker execution metrics
- Request/response analytics
- Error tracking and alerting
- Performance monitoring

### Custom Metrics
Add to any worker:
```javascript
// Track custom events
analytics.writeDataPoint({
  blobs: ["api-request"],
  doubles: [response_time],
  indexes: [endpoint_name]
});
```

## Production Checklist

### Security
- [ ] Update admin credentials
- [ ] Configure proper CORS origins
- [ ] Set up API authentication
- [ ] Enable bot protection
- [ ] Configure rate limits

### Performance
- [ ] Tune cache TTLs
- [ ] Optimize database queries
- [ ] Configure compression
- [ ] Set up edge caching

### Monitoring
- [ ] Set up alerts
- [ ] Configure logging
- [ ] Monitor error rates
- [ ] Track performance metrics

## Cost Estimation

Based on moderate traffic (1M requests/month):

| Service | Usage | Cost |
|---------|-------|------|
| Zone (Enterprise) | 1 zone | $200/month |
| Workers | 1M requests | $0.50/month |
| D1 Database | 100K reads, 10K writes | $1.00/month |
| KV Storage | 1GB, 1M reads | $1.00/month |
| R2 Storage | 10GB, 100K requests | $1.00/month |
| **Total** | | **~$203.50/month** |

## Cleanup

```bash
terraform destroy
```

**Warning**: This will delete all resources including databases and uploaded files.

## Support

This demo showcases Cloudflare's platform capabilities. For production use:

- Review security settings
- Implement proper error handling  
- Add comprehensive monitoring
- Set up CI/CD pipelines
- Configure backups

## License

MIT License - feel free to use this as a starting point for your own projects.

---

Built with ❤️ using [Cloudflare Workers](https://workers.cloudflare.com/) and [Terraform](https://terraform.io/).
