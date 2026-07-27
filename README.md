# Cloudflare Demo Platform

A complete e-commerce platform demo built with Cloudflare's edge computing stack. This Terraform configuration creates a production-ready setup showcasing:

- **Multi-Zone Architecture** with API gateway pattern
- **Edge Computing** with Workers for all business logic
- **Distributed Storage** using D1, KV, R2, and Queues
- **Security & Performance** with WAF rules and caching
- **Real-time Features** and async processing

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
- **WAF Protection** - SQL injection blocking
- **Rate Limiting** - API endpoint protection
- **Bot Management** - Automated threat detection
- **Edge Caching** - Sub-second response times

## Quick Start (Demo Workflow)

This repo is designed for demos. Deploy, run demos, tear down.

PowerShell equivalents exist for every user-facing shell script (`*.sh` and matching `*.ps1`). Keep both versions updated together.

### Step 1: Configure
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit with your API token, account ID, and zone
```

### Step 2: Deploy Platform
```bash
./run-demo.sh deploy
```

Deploy now auto-registers Queue consumer (`demo-order-processor`) and fails fast if consumer is missing.

After deploy completes, access the admin panel:
- **URL:** `https://admin.your-domain.com`
- **Username:** `admin`
- **Password:** `demo123`

Click "Load Sample Data" to get started.

### Step 3: Run Demos

**Platform demos** (API, admin panel, workers):
```bash
./run-demo.sh test          # Verify endpoints + queue consumer health
./run-demo.sh deploy --demo # Run sample API calls
./test.sh                   # Full integration validation (async order persistence)
```

```powershell
./run-demo.ps1 test
./run-demo.ps1 deploy --demo
./test.ps1
```

Use `./run-demo.sh test` for fast smoke checks. Use `./test.sh` for deeper API + admin integration coverage.

**Terraform demos** (infrastructure as code concepts):
```bash
./terraform-demo.sh state-inspect   # Show state and outputs
./terraform-demo.sh drift-detect    # Detect manual dashboard changes
./terraform-demo.sh idempotency     # Apply twice, 0 changes
./terraform-demo.sh targeted        # Deploy single resource
./terraform-demo.sh plan-file       # Save and apply exact plan
./terraform-demo.sh refresh-only    # Detect drift without changing
./terraform-demo.sh taint-replace   # Force recreation
./terraform-demo.sh var-override staging.example.com  # Override variables
./terraform-demo.sh graph           # Dependency graph
./terraform-demo.sh workspaces      # Multiple environments
```

```powershell
./terraform-demo.ps1 state-inspect
./terraform-demo.ps1 all
```

Run all Terraform demos:
```bash
./terraform-demo.sh all
```

### Step 4: Teardown
```bash
./run-demo.sh destroy
```

**Total runtime:** ~5-10 minutes for full deploy + demos + destroy.

---

## Prerequisites
- [Terraform](https://www.terraform.io/) installed
- [Cloudflare account](https://cloudflare.com) with zone access
- API token with: Zone:Edit, DNS:Edit, Zone Settings:Edit, Workers Scripts:Edit, D1:Edit, R2:Edit, KV:Edit, Queues:Edit

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
Workers support environment variables through `terraform.tfvars`:

```hcl
# Add to variables.tf
variable "stripe_secret_key" {
  description = "Stripe secret key"
  type        = string
  sensitive   = true
}

# Add to worker bindings
plain_text_binding {
  name  = "STRIPE_SECRET_KEY"
  text  = var.stripe_secret_key
}
```

### Adding New Workers
1. Create worker file in `workers/`
2. Add resource in `main.tf`
3. Configure bindings and routes

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
