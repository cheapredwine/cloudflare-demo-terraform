# Cloudflare Demo Platform - Agent Guide

Technical reference for AI agents interacting with the Cloudflare demo platform infrastructure.

## 🤖 Agent Context

This platform demonstrates Cloudflare's edge computing stack through a production-ready e-commerce application. Agents can use this reference to understand architecture patterns, troubleshoot issues, and extend functionality.

## 📐 Architecture Patterns

### Worker Communication Patterns
```javascript
// API Gateway Pattern - Request routing
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    
    if (path.startsWith('/api/products')) {
      return handleProducts(request, env);
    } else if (path.startsWith('/api/orders')) {
      return handleOrders(request, env);
    }
    // Route to appropriate service
  }
}

// Service Worker Pattern - Specific functionality
async function handleProducts(request, env) {
  // Cache-first strategy
  const cacheKey = `products:${url.search}`;
  const cached = await env.CACHE.get(cacheKey);
  if (cached) return new Response(cached);
  
  // Database query with caching
  const results = await env.DB.prepare('SELECT * FROM products').all();
  await env.CACHE.put(cacheKey, JSON.stringify(results), { expirationTtl: 300 });
  return new Response(JSON.stringify(results));
}
```

### Storage Integration Patterns
```javascript
// D1 Database - Relational queries
const stmt = env.DB.prepare(`
  INSERT INTO products (name, price, stock) 
  VALUES (?, ?, ?)
`);
await stmt.bind(name, price, stock).run();

// KV Storage - Key-value caching
await env.SESSIONS.put(`session:${id}`, JSON.stringify(data), {
  expirationTtl: 86400
});

// R2 Storage - File operations
await env.UPLOADS.put(filename, file.stream(), {
  httpMetadata: { contentType: file.type }
});

// Queue Processing - Async operations
await env.ORDER_QUEUE.send({
  order_id: uuid(),
  items: orderData.items,
  timestamp: new Date().toISOString()
});
```

### Error Handling Patterns
```javascript
// Consistent error responses
function errorResponse(message, status = 500) {
  return new Response(JSON.stringify({
    error: message,
    timestamp: new Date().toISOString()
  }), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

// Graceful degradation
try {
  const data = await env.DB.prepare('SELECT * FROM products').all();
  return new Response(JSON.stringify(data));
} catch (error) {
  // Fallback to cache or static response
  console.error('Database error:', error);
  return errorResponse('Service temporarily unavailable', 503);
}
```

## 🔧 Infrastructure Components

### Terraform Resources
```hcl
# Core pattern: Worker with bindings
resource "cloudflare_worker_script" "api_gateway" {
  account_id = var.account_id
  name       = "demo-api-gateway"
  content    = file("${path.module}/workers/api-gateway.js")

  # Storage bindings
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

  queue_binding {
    name       = "ORDER_QUEUE"
    queue_name = cloudflare_queue.orders.queue_name
  }
}

# DNS routing pattern
resource "cloudflare_worker_route" "api_route" {
  zone_id     = cloudflare_zone.main.id
  pattern     = "api.${var.zone_name}/*"
  script_name = cloudflare_worker_script.api_gateway.name
}
```

### Database Schema Patterns
```sql
-- Products table - Core entity
CREATE TABLE products (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  category TEXT DEFAULT 'general',
  stock INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Orders table - Transaction tracking
CREATE TABLE orders (
  id TEXT PRIMARY KEY,           -- UUID
  customer_id TEXT NOT NULL,
  total_amount DECIMAL(10,2) NOT NULL,
  status TEXT DEFAULT 'pending',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Junction table pattern
CREATE TABLE order_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  order_id TEXT NOT NULL,
  product_id INTEGER NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (order_id) REFERENCES orders (id),
  FOREIGN KEY (product_id) REFERENCES products (id)
);
```

## 🚨 Troubleshooting Patterns

### Common Issues and Solutions

**Database Not Initialized:**
```javascript
// Check and initialize pattern
try {
  await env.DB.prepare('SELECT COUNT(*) FROM products').first();
} catch (error) {
  if (error.message.includes('no such table')) {
    // Initialize database
    await initializeDatabase(env);
  }
  throw error;
}
```

**Worker Binding Errors:**
```javascript
// Defensive binding checks
if (!env.DB) {
  return errorResponse('Database not configured', 500);
}
if (!env.SESSIONS) {
  return errorResponse('Session storage not configured', 500);
}
```

**DNS/Route Issues:**
```bash
# Diagnostic commands
dig api.demo-platform.example    # Check DNS resolution
curl -I https://api.demo-platform.example  # Check worker response
```

### Health Check Patterns
```javascript
// Worker health endpoint
if (url.pathname === '/health') {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: {}
  };

  // Check database
  try {
    await env.DB.prepare('SELECT 1').first();
    health.services.database = 'healthy';
  } catch (error) {
    health.services.database = 'unhealthy';
    health.status = 'degraded';
  }

  // Check KV
  try {
    await env.SESSIONS.get('health-check');
    health.services.kv = 'healthy';
  } catch (error) {
    health.services.kv = 'unhealthy';
    health.status = 'degraded';
  }

  return new Response(JSON.stringify(health), {
    status: health.status === 'healthy' ? 200 : 503,
    headers: { 'Content-Type': 'application/json' }
  });
}
```

## 🔄 Management Automation

### Deployment State Detection
```bash
# Check if infrastructure exists
terraform show -json | jq -r '.values.root_module.resources[] | select(.type=="cloudflare_zone") | .values.name'

# Test endpoint availability  
curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.$ZONE_NAME" 2>/dev/null
```

### Data Reset Automation
```javascript
// Database reset pattern
const resetDatabase = async (env) => {
  const tables = ['order_items', 'orders', 'products'];
  
  for (const table of tables) {
    try {
      await env.DB.prepare(`DELETE FROM ${table}`).run();
    } catch (error) {
      console.log(`Table ${table} doesn't exist or already empty`);
    }
  }
  
  // Reset auto-increment
  await env.DB.prepare(`DELETE FROM sqlite_sequence WHERE name IN ('products', 'order_items')`).run();
};

// Cache clear pattern
const clearCache = async (env) => {
  // KV doesn't have bulk delete, but keys expire
  // Or maintain a list of cache keys to delete
  const cacheKeys = ['products:all', 'products:'];
  for (const key of cacheKeys) {
    try {
      await env.CACHE.delete(key);
    } catch (error) {
      console.log(`Cache key ${key} not found`);
    }
  }
};
```

## 📊 Monitoring Integration

### Custom Analytics Patterns
```javascript
// Track custom metrics
const trackEvent = (eventName, value = 1) => {
  // Cloudflare Analytics Engine integration
  analytics.writeDataPoint({
    'blobs': [eventName],
    'doubles': [value],
    'indexes': [new Date().toISOString().split('T')[0]] // date index
  });
};

// Usage in handlers
await trackEvent('product_created');
await trackEvent('order_processed');
await trackEvent('api_response_time', responseTime);
```

### Error Tracking
```javascript
// Structured error logging
const logError = (error, context = {}) => {
  console.error(JSON.stringify({
    error: error.message,
    stack: error.stack,
    context,
    timestamp: new Date().toISOString()
  }));
};
```

## 🔐 Security Patterns

### Input Validation
```javascript
// Schema validation pattern  
const validateProduct = (data) => {
  if (!data.name || typeof data.name !== 'string') {
    throw new Error('Invalid product name');
  }
  if (!data.price || typeof data.price !== 'number' || data.price <= 0) {
    throw new Error('Invalid product price');
  }
  return true;
};
```

### Rate Limiting Implementation
```javascript
// Simple rate limiting with KV
const checkRateLimit = async (env, clientIP, limit = 100, window = 60) => {
  const key = `rate_limit:${clientIP}`;
  const current = await env.SESSIONS.get(key);
  
  if (!current) {
    await env.SESSIONS.put(key, '1', { expirationTtl: window });
    return true;
  }
  
  const count = parseInt(current);
  if (count >= limit) {
    return false;
  }
  
  await env.SESSIONS.put(key, String(count + 1), { expirationTtl: window });
  return true;
};
```

## 🧪 Testing Patterns

### Unit Test Structure
```javascript
// Worker testing with Miniflare
import { Miniflare } from 'miniflare';

const mf = new Miniflare({
  script: `export default { async fetch() { return new Response('Hello!') } }`,
  d1Databases: ['DB'],
  kvNamespaces: ['SESSIONS'],
  r2Buckets: ['UPLOADS']
});

// Test API endpoints
const response = await mf.dispatchFetch('https://api.example.com/products');
```

### Integration Test Patterns
```bash
# API endpoint testing
test_api_endpoint() {
  local endpoint=$1
  local expected_status=$2
  
  response=$(curl -s -w "HTTPSTATUS:%{http_code}" "$endpoint")
  status=$(echo "$response" | grep -o "HTTPSTATUS:[0-9]*" | cut -d: -f2)
  
  if [ "$status" -eq "$expected_status" ]; then
    echo "✅ $endpoint"
    return 0
  else
    echo "❌ $endpoint (expected $expected_status, got $status)"
    return 1
  fi
}
```

## 🔧 Extension Patterns

### Adding New Endpoints
```javascript
// Router extension pattern
const routes = {
  '/api/products': handleProducts,
  '/api/orders': handleOrders,
  '/api/users': handleUsers,     // New endpoint
  '/api/analytics': handleAnalytics  // New endpoint
};

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const handler = routes[url.pathname] || routes[url.pathname.replace(/\/$/, '')];
    
    if (handler) {
      return handler(request, env, ctx);
    }
    
    return new Response('Not Found', { status: 404 });
  }
}
```

### Adding New Storage
```hcl
# Add new KV namespace
resource "cloudflare_workers_kv_namespace" "analytics" {
  account_id = var.account_id
  title      = "demo-analytics"
}

# Bind to worker
kv_namespace_binding {
  name         = "ANALYTICS"
  namespace_id = cloudflare_workers_kv_namespace.analytics.id
}
```

This reference enables agents to understand, troubleshoot, and extend the Cloudflare demo platform infrastructure effectively.