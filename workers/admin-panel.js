/**
 * Demo Admin Panel Worker
 * Simple admin interface for managing products and orders
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Redirect plain HTTP before asking for a password, so the browser never
    // sends Basic-auth credentials unencrypted.
    if (url.protocol === 'http:') {
      url.protocol = 'https:';
      return Response.redirect(url.toString(), 301);
    }

    // Basic auth check
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !(await isValidAuth(authHeader, env))) {
      return new Response('Unauthorized', {
        status: 401,
        headers: {
          'WWW-Authenticate': 'Basic realm="Admin Panel"'
        }
      });
    }

    try {
      if (path === '/' || path === '') {
        return serveDashboard(env);
      } else if (path === '/api/stats') {
        return getStats(env);
      } else if (path === '/api/orders') {
        return getOrders(env);
      } else if (path === '/api/products') {
        return getProducts(env);
      } else if ((path === '/setup' || path === '/reset') && request.method === 'POST') {
        // Browsers resend cached Basic-auth credentials on cross-site
        // requests, so refuse POSTs that a different site's page started.
        const origin = request.headers.get('Origin');
        if (origin && origin !== url.origin) {
          return new Response('Forbidden', { status: 403 });
        }
        return path === '/setup' ? setupDatabase(env) : resetData(env);
      }

      return new Response('Not Found', { status: 404 });
    } catch (error) {
      // Details go to Workers Logs, not to the client.
      console.error('admin panel error', error);
      return new Response(JSON.stringify({ 
        error: 'Internal server error'
      }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }
  }
};

// Basic auth (user: admin). The password is the ADMIN_PASSWORD secret binding
// set from var.admin_password; nothing is hardcoded.
async function isValidAuth(authHeader, env) {
  if (!env.ADMIN_PASSWORD) return false;

  // "Basic <base64(user:password)>"; the scheme name is case-insensitive.
  const match = /^basic\s+(\S+)$/i.exec(authHeader);
  if (!match) return false;
  let decoded;
  try {
    const bytes = Uint8Array.from(atob(match[1]), (c) => c.charCodeAt(0));
    decoded = new TextDecoder().decode(bytes);
  } catch {
    return false; // not valid base64
  }
  const sep = decoded.indexOf(':');
  if (sep === -1) return false;

  // Compare both parts in constant time, always (no early exit on the user).
  const [userOk, passOk] = await Promise.all([
    constantTimeEqual(decoded.slice(0, sep), 'admin'),
    constantTimeEqual(decoded.slice(sep + 1), env.ADMIN_PASSWORD),
  ]);
  return userOk && passOk;
}

// Hash both strings first so timingSafeEqual always gets equal-length input.
async function constantTimeEqual(a, b) {
  const encoder = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', encoder.encode(a)),
    crypto.subtle.digest('SHA-256', encoder.encode(b)),
  ]);
  return crypto.subtle.timingSafeEqual(ha, hb);
}

function serveDashboard(env) {
  const zoneName = env.ZONE_NAME || 'demo-platform.example';
  const html = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Demo Platform Admin</title>
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: #f5f5f5;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white;
            border-radius: 8px;
            padding: 20px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        .header { 
            border-bottom: 1px solid #eee; 
            padding-bottom: 20px; 
            margin-bottom: 20px; 
        }
        .stats { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); 
            gap: 20px; 
            margin-bottom: 30px; 
        }
        .stat-card { 
            background: #007bff; 
            color: white; 
            padding: 20px; 
            border-radius: 6px; 
            text-align: center; 
        }
        .stat-card h3 { margin: 0 0 10px 0; font-size: 2em; }
        .stat-card p { margin: 0; opacity: 0.9; }
        .section { margin-bottom: 30px; }
        .section h2 { color: #333; border-bottom: 2px solid #007bff; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background: #f8f9fa; font-weight: 600; }
        .btn { 
            background: #007bff; 
            color: white; 
            border: none; 
            padding: 8px 16px; 
            border-radius: 4px; 
            cursor: pointer; 
            margin-right: 10px;
        }
        .btn:hover { background: #0056b3; }
        .btn-success { background: #28a745; }
        .btn-success:hover { background: #1e7e34; }
        .loading { color: #666; font-style: italic; }
        .error { color: #dc3545; background: #f8d7da; padding: 10px; border-radius: 4px; margin: 10px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 Demo Platform Admin</h1>
            <p>Manage your e-commerce platform powered by Cloudflare Workers</p>
        </div>

        <div class="stats">
            <div class="stat-card">
                <h3 id="total-products">-</h3>
                <p>Total Products</p>
            </div>
            <div class="stat-card">
                <h3 id="total-orders">-</h3>
                <p>Total Orders</p>
            </div>
            <div class="stat-card">
                <h3 id="revenue">-</h3>
                <p>Revenue (Demo)</p>
            </div>
        </div>

        <div class="section">
            <h2>🛠️ Setup</h2>
            <button class="btn btn-success" onclick="setupDatabase()">Initialize Database</button>
            <button class="btn btn-success" onclick="seedData()">Load Sample Data</button>
            <div id="setup-result"></div>
        </div>

        <div class="section">
            <h2>📦 Recent Products</h2>
            <div id="products-table">Loading...</div>
        </div>

        <div class="section">
            <h2>📋 Recent Orders</h2>
            <div id="orders-table">Loading...</div>
        </div>
    </div>

    <script>
        const API_BASE = '';

        async function fetchStats() {
            try {
                const response = await fetch('/api/stats');
                if (response.ok) {
                    const stats = await response.json();
                    document.getElementById('total-products').textContent = stats.products || '0';
                    document.getElementById('total-orders').textContent = stats.orders || '0';
                    document.getElementById('revenue').textContent = '$' + (stats.revenue || '0');
                }
            } catch (error) {
                console.error('Failed to fetch stats:', error);
            }
        }

        // Product and order fields come from the public API, so anyone can
        // set them. Escape every value before it goes into innerHTML.
        function esc(value) {
            const entities = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
            return String(value ?? '').replace(/[&<>"']/g, (c) => entities[c]);
        }

        async function fetchProducts() {
            try {
                const response = await fetch('/api/products');
                const data = await response.json();
                
                let html = '<table><tr><th>ID</th><th>Name</th><th>Price</th><th>Category</th><th>Stock</th></tr>';
                for (const product of data.products || []) {
                    html += \`<tr>
                        <td>\${esc(product.id)}</td>
                        <td>\${esc(product.name)}</td>
                        <td>$\${esc(product.price)}</td>
                        <td>\${esc(product.category)}</td>
                        <td>\${esc(product.stock)}</td>
                    </tr>\`;
                }
                html += '</table>';
                
                document.getElementById('products-table').innerHTML = html;
            } catch (error) {
                document.getElementById('products-table').innerHTML = '<div class="error">Failed to load products</div>';
            }
        }

        async function fetchOrders() {
            try {
                const response = await fetch('/api/orders');
                const data = await response.json();
                
                let html = '<table><tr><th>ID</th><th>Customer</th><th>Status</th><th>Total</th><th>Created</th></tr>';
                for (const order of data.orders || []) {
                    html += \`<tr>
                        <td>\${esc(order.id)}</td>
                        <td>\${esc(order.customer_id)}</td>
                        <td>\${esc(order.status)}</td>
                        <td>$\${esc(order.total_amount)}</td>
                        <td>\${esc(new Date(order.created_at).toLocaleString())}</td>
                    </tr>\`;
                }
                html += '</table>';
                
                document.getElementById('orders-table').innerHTML = html;
            } catch (error) {
                document.getElementById('orders-table').innerHTML = '<div class="error">Failed to load orders</div>';
            }
        }

        async function setupDatabase() {
            const resultDiv = document.getElementById('setup-result');
            resultDiv.innerHTML = '<div class="loading">Setting up database...</div>';
            
            try {
                const response = await fetch('/setup', { method: 'POST' });
                const result = await response.json();
                
                if (response.ok) {
                    resultDiv.innerHTML = \`<div style="color: green; background: #d4edda; padding: 10px; border-radius: 4px; margin: 10px 0;">\${esc(result.message)}</div>\`;
                    setTimeout(loadData, 1000);
                } else {
                    resultDiv.innerHTML = \`<div class="error">\${esc(result.error)}</div>\`;
                }
            } catch (error) {
                resultDiv.innerHTML = \`<div class="error">Setup failed: \${esc(error.message)}</div>\`;
            }
        }

        async function seedData() {
            const resultDiv = document.getElementById('setup-result');
            resultDiv.innerHTML = '<div class="loading">Loading sample data...</div>';
            
            try {
                const response = await fetch(\`https://api.${zoneName}/api/products/seed\`, { method: 'POST' });
                const result = await response.json();
                
                if (response.ok) {
                    resultDiv.innerHTML = \`<div style="color: green; background: #d4edda; padding: 10px; border-radius: 4px; margin: 10px 0;">\${esc(result.message)}</div>\`;
                    setTimeout(loadData, 1000);
                } else {
                    resultDiv.innerHTML = \`<div class="error">\${esc(result.error || 'Failed to seed data')}</div>\`;
                }
            } catch (error) {
                resultDiv.innerHTML = \`<div class="error">Seed failed: \${esc(error.message)}</div>\`;
            }
        }

        function loadData() {
            fetchStats();
            fetchProducts();
            fetchOrders();
        }

        // Load data on page load
        loadData();
    </script>
</body>
</html>`;

  return new Response(html, {
    headers: { 'Content-Type': 'text/html' }
  });
}

async function getStats(env) {
  try {
    // Get product count
    const productCount = await env.DB.prepare('SELECT COUNT(*) as count FROM products').first();
    
    // Get order count and revenue
    const orderStats = await env.DB.prepare(`
      SELECT COUNT(*) as count, COALESCE(SUM(total_amount), 0) as revenue 
      FROM orders
    `).first();

    return new Response(JSON.stringify({
      products: productCount?.count || 0,
      orders: orderStats?.count || 0,
      revenue: orderStats?.revenue || 0,
      timestamp: new Date().toISOString()
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Stats unavailable' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function getProducts(env) {
  try {
    const stmt = env.DB.prepare(`
      SELECT id, name, price, category, stock, created_at
      FROM products 
      ORDER BY created_at DESC 
      LIMIT 10
    `);
    
    const result = await stmt.all();
    
    return new Response(JSON.stringify({
      products: result.results || [],
      count: result.results?.length || 0
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({ 
      products: [],
      error: 'Database not initialized' 
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

async function getOrders(env) {
  try {
    const stmt = env.DB.prepare(`
      SELECT id, customer_id, status, total_amount, created_at
      FROM orders 
      ORDER BY created_at DESC 
      LIMIT 10
    `);
    
    const result = await stmt.all();
    
    return new Response(JSON.stringify({
      orders: result.results || [],
      count: result.results?.length || 0
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    return new Response(JSON.stringify({ 
      orders: [],
      error: 'Database not initialized' 
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  }
}

// Empty every table (children first, for the foreign keys), then drop the
// products API's cached list (shared KV namespace, key products:all) so
// GET /api/products doesn't keep serving the deleted catalog for 10 minutes.
async function resetData(env) {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM order_items'),
    env.DB.prepare('DELETE FROM orders'),
    env.DB.prepare('DELETE FROM products'),
  ]);
  await env.CACHE.delete('products:all');
  return new Response(JSON.stringify({ message: 'All products and orders deleted' }), {
    headers: { 'Content-Type': 'application/json' }
  });
}

// Same tables as db/schema.sql (a Worker can't read repo files); keep the two
// copies identical. scripts/tests/config-checks.sh compares them.
async function setupDatabase(env) {
  try {
    // Create products table
    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        price DECIMAL(10,2) NOT NULL,
        category TEXT DEFAULT 'general',
        stock INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `).run();

    // Create orders table
    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        total_amount DECIMAL(10,2) NOT NULL,
        status TEXT DEFAULT 'pending',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    `).run();

    // Create order_items table
    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        unit_price DECIMAL(10,2) NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders (id),
        FOREIGN KEY (product_id) REFERENCES products (id)
      )
    `).run();

    return new Response(JSON.stringify({
      message: 'Database initialized successfully',
      tables: ['products', 'orders', 'order_items']
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  } catch (error) {
    console.error('database setup failed', error);
    return new Response(JSON.stringify({ 
      error: 'Database setup failed'
    }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
}