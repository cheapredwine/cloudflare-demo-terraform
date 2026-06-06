# Cloudflare Demo Platform - User Guide

Complete guide for deploying, managing, and demoing the Cloudflare edge computing platform.

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Demo Scenarios](#demo-scenarios)
- [API Reference](#api-reference)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Cost Management](#cost-management)

## 🚀 Quick Start

### Prerequisites

- [Terraform](https://www.terraform.io/downloads) installed
- Cloudflare account with Enterprise or Pro plan
- Domain you can use for the demo
- API token with these permissions:
  - `Zone:Edit`, `DNS:Edit`, `Zone Settings:Edit`
  - `Workers Scripts:Edit`, `D1:Edit`, `R2:Edit`

### 1. Setup Configuration

```bash
git clone <repository>
cd cloudflare-demo-terraform

# Configure your settings
cp terraform.tfvars.example terraform.tfvars
nano terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
cloudflare_api_token = "your-cloudflare-api-token"
account_id          = "your-account-id"
zone_name           = "demo.your-company.com"
```

### 2. Deploy Platform

```bash
# Full deployment (2-3 minutes)
./run-demo.sh deploy

# Deploy with demo data
./run-demo.sh deploy --demo
```

### 3. Initialize Demo

1. Visit admin panel: `https://admin.demo.your-company.com`
2. Login: `admin` / `demo123`
3. Click **"Initialize Database"**
4. Click **"Load Sample Data"**

✅ **Demo ready!** Platform is live with sample products and ready for testing.

## 🎬 Demo Scenarios

### Scenario 1: Full Platform Demo (15 minutes)

**"Let me show you a complete e-commerce platform running entirely at the edge"**

1. **Deploy Infrastructure** (2 mins)
   ```bash
   ./run-demo.sh deploy
   ```

2. **Show Admin Dashboard** (2 mins)
   - Visit `https://admin.your-domain.com`
   - Initialize database live
   - Load sample data (5 products appear)

3. **Test API Endpoints** (5 mins)
   ```bash
   # Show product catalog
   curl https://api.your-domain.com/products | jq .
   
   # Create order (triggers async processing)
   curl -X POST https://api.your-domain.com/products \
     -H "Content-Type: application/json" \
     -d '{"name":"Demo Product","price":49.99,"stock":100}'
   
   # Process order through queue
   curl -X POST https://api.your-domain.com/orders \
     -H "Content-Type: application/json" \
     -d '{"customer_id":"demo","items":[{"product_id":1,"quantity":2,"unit_price":49.99}],"total":99.98}'
   ```

4. **Show Real-time Features** (3 mins)
   - Upload file to R2: `curl -F "file=@image.jpg" https://api.your-domain.com/upload`
   - Check admin panel - see new order, updated stock
   - Show caching: repeated API calls are instant

5. **Highlight Architecture** (3 mins)
   - All business logic at the edge (0ms latency)
   - Distributed storage (D1, KV, R2, Queues)
   - Auto-scaling to millions of requests
   - Built-in security (WAF, rate limiting)

### Scenario 2: Developer Experience (10 minutes)

**"See how fast developers can build and deploy"**

1. **Code Walkthrough** (3 mins)
   - Show `workers/api-gateway.js` - full API in <200 lines
   - Explain bindings to D1, KV, R2, Queues
   - Point out built-in edge features

2. **Live Deployment** (5 mins)
   ```bash
   ./run-demo.sh deploy
   # Show real-time deployment logs
   ```

3. **Instant Global Scale** (2 mins)
   - Test from multiple locations
   - Show edge analytics
   - Demonstrate zero cold starts

### Scenario 3: Reset Demo (2 minutes)

**For multiple demos in same session:**

```bash
# Between demos - reset data only
./run-demo.sh reset

# Fresh start - full redeploy
./run-demo.sh fresh
```

## 📚 API Reference

### Products API

```bash
# List all products
GET https://api.your-domain.com/products

# Get specific product  
GET https://api.your-domain.com/products/1

# Create product
POST https://api.your-domain.com/products
Content-Type: application/json
{
  "name": "Product Name",
  "description": "Product description",
  "price": 29.99,
  "category": "electronics", 
  "stock": 50
}

# Update product
PUT https://api.your-domain.com/products/1
Content-Type: application/json
{
  "price": 24.99,
  "stock": 75
}

# Delete product
DELETE https://api.your-domain.com/products/1
```

### Orders API

```bash
# Create order (async processing)
POST https://api.your-domain.com/orders
Content-Type: application/json
{
  "customer_id": "cust_123",
  "items": [
    {
      "product_id": 1,
      "quantity": 2,
      "unit_price": 29.99
    }
  ],
  "total": 59.98
}

# Response
{
  "order_id": "uuid-here",
  "status": "queued", 
  "message": "Order received and queued for processing"
}
```

### Authentication API

```bash
# Login
POST https://api.your-domain.com/auth/login
Content-Type: application/json
{
  "email": "user@example.com",
  "password": "password"
}

# Response
{
  "session_id": "uuid-here",
  "user": {
    "id": "user-uuid",
    "email": "user@example.com"
  },
  "expires_at": "2024-12-07T10:30:00Z"
}

# Get user info
GET https://api.your-domain.com/auth/me
Authorization: Bearer session-uuid
```

### File Upload API

```bash
# Upload file to R2
POST https://api.your-domain.com/upload
Content-Type: multipart/form-data

curl -X POST https://api.your-domain.com/upload \
  -F "file=@image.jpg"

# Response
{
  "filename": "uuid-image.jpg",
  "size": 245760,
  "type": "image/jpeg", 
  "url": "https://uploads.your-domain.com/uuid-image.jpg"
}
```

## 🛠️ Management

### Platform Management

```bash
# Deploy fresh platform
./run-demo.sh deploy

# Reset data between demos  
./run-demo.sh reset

# Test existing deployment
./run-demo.sh test

# Complete teardown
./run-demo.sh destroy

# Fresh deployment (destroy + deploy)
./run-demo.sh fresh

# Deploy with demo data
./run-demo.sh deploy --demo
```

### Admin Interface

Visit: `https://admin.your-domain.com`
- **Username:** `admin`  
- **Password:** `demo123`

**Available Actions:**
- Initialize Database (creates SQL schema)
- Load Sample Data (adds 5 demo products)
- View real-time stats
- Browse products and orders
- Monitor platform health

### Data Management

```bash
# Seed sample products
curl -X POST https://api.your-domain.com/products/seed

# Clear cache
curl -X DELETE https://api.your-domain.com/cache

# Reset database (via admin)
curl -X POST https://admin.your-domain.com/setup \
  -u admin:demo123
```

## 🔍 Troubleshooting

### Common Issues

**"terraform.tfvars not found"**
```bash
cp terraform.tfvars.example terraform.tfvars
# Edit with your settings
```

**"API endpoints not responding"** 
```bash
# Test deployment
./run-demo.sh test

# Check DNS propagation (wait 2-3 minutes)
dig api.your-domain.com

# Redeploy if needed
./run-demo.sh fresh
```

**"Database not initialized"**
- Visit admin panel: `https://admin.your-domain.com`
- Click "Initialize Database"
- Or via API: `curl -X POST https://admin.your-domain.com/setup -u admin:demo123`

**"No sample data"**
```bash
curl -X POST https://api.your-domain.com/products/seed
```

### Health Checks

```bash
# Test all endpoints
./run-demo.sh test

# Manual endpoint testing
curl -I https://api.your-domain.com/products
curl -I https://admin.your-domain.com
```

### Logs and Debugging

**Worker Logs:**
- Cloudflare Dashboard → Workers & Pages → Your Worker → Logs
- Real-time tail: `wrangler tail worker-name`

**Common HTTP Codes:**
- `200` - Success
- `401` - Admin panel (auth required) ✅
- `404` - Endpoint not found
- `500` - Check worker logs

## 💰 Cost Management

### Cost Breakdown

| Component | Usage | Monthly Cost |
|-----------|-------|-------------|
| **Enterprise Zone** | 1 zone | $200 |
| **Workers** | 1M requests | $0.50 |
| **D1 Database** | 100K reads, 10K writes | $1.00 |
| **KV Storage** | 1GB, 1M operations | $1.00 |
| **R2 Storage** | 10GB, 100K requests | $1.00 |
| **Queues** | 1M operations | $0.40 |
| **Total** | | **~$203.90** |

### Cost Optimization

**For Frequent Demos:**
- Keep one permanent demo environment
- Use `./run-demo.sh reset` between demos
- Cost: ~$200/month fixed

**For Occasional Demos:**  
- Deploy fresh each time: `./run-demo.sh deploy`
- Destroy after: `./run-demo.sh destroy`
- Cost: ~$0.01 per demo

**For Multiple Concurrent Demos:**
```bash
# Use different domains
zone_name = "demo1.company.com"  # Sales demo
zone_name = "demo2.company.com"  # Engineering demo
zone_name = "demo3.company.com"  # Customer POC
```

### Monitoring Costs

- **Cloudflare Dashboard** → Billing → Usage
- **Set up billing alerts** for unexpected usage
- **Review monthly** - most costs are predictable

## 🎯 Demo Tips

### Before Demo
- [ ] Test deployment: `./run-demo.sh test`
- [ ] Have backup domain ready
- [ ] Prepare talking points
- [ ] Check internet connection

### During Demo
- [ ] Start with big picture (architecture diagram)
- [ ] Show admin panel first (visual impact)
- [ ] Use curl commands for technical audience
- [ ] Highlight real-time aspects (order processing)
- [ ] Emphasize global scale and performance

### After Demo
- [ ] Leave environment running for follow-up questions
- [ ] Share API endpoints for exploration
- [ ] Provide documentation links
- [ ] Schedule follow-up if interested

### Recovery Plans
- **Demo fails:** Have backup video recording
- **Slow deployment:** Pre-deploy earlier, use existing
- **API errors:** Use `./run-demo.sh reset` and retry
- **DNS issues:** Have alternative domain ready

---

## 📞 Support

- **Platform Issues:** Check [troubleshooting](#troubleshooting)
- **Terraform Errors:** Review terraform logs
- **Cloudflare Issues:** Check Cloudflare status page
- **Demo Questions:** See agent documentation

Ready to demo the future of edge computing! 🚀