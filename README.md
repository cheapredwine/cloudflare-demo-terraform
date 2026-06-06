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
- **Page Rules** for optimal caching

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

## Quick Start

### 1. Prerequisites
- [Terraform](https://www.terraform.io/) installed
- [Cloudflare account](https://cloudflare.com) with Enterprise or Pro plan
- API token with these permissions:
  - Zone:Edit
  - DNS:Edit
  - Zone Settings:Edit
  - Page Rules:Edit
  - Workers Scripts:Edit
  - D1:Edit
  - R2:Edit

### 2. Configuration
```bash
git clone <this-repo>
cd cloudflare-demo-terraform

# Copy and edit configuration
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Update `terraform.tfvars`:
```hcl
cloudflare_api_token = "your-api-token"
account_id          = "your-account-id"
zone_name           = "your-domain.com"
```

### 3. Deploy
```bash
terraform init
terraform plan
terraform apply
```

### 4. Initialize
After deployment, visit your admin panel to set up the database:

1. Go to `https://admin.your-domain.com`
2. Login with: `admin` / `demo123`
3. Click "Initialize Database"
4. Click "Load Sample Data"

## API Endpoints

### Products API
```bash
# Get all products
curl https://api.your-domain.com/products

# Create product
curl -X POST https://api.your-domain.com/products \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Product", "price": 19.99, "stock": 100}'

# Get specific product
curl https://api.your-domain.com/products/1
```

### Orders API
```bash
# Create order
curl -X POST https://api.your-domain.com/orders \
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
curl -X POST https://api.your-domain.com/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "password"}'

# Get user info
curl https://api.your-domain.com/auth/me \
  -H "Authorization: Bearer <session-id>"
```

### File Upload
```bash
# Upload file
curl -X POST https://api.your-domain.com/upload \
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