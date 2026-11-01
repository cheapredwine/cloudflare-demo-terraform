/**
 * Demo Products API Worker
 * Handles CRUD operations for products with caching
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      const path = url.pathname;
      const method = request.method;
      // Anchored: only an all-digit id matches, so /products/12abc is a 404
      // rather than a lookup for "12abc".
      const idMatch = path.match(/^\/products\/(\d+)$/);

      if (path === '/products' && method === 'GET') {
        return await getProducts(env, corsHeaders);
      } else if (path === '/products' && method === 'POST') {
        return await createProduct(request, env, corsHeaders);
      } else if (idMatch && method === 'GET') {
        return await getProduct(idMatch[1], env, corsHeaders);
      } else if (idMatch && method === 'PUT') {
        return await updateProduct(idMatch[1], request, env, corsHeaders);
      } else if (idMatch && method === 'DELETE') {
        return await deleteProduct(idMatch[1], env, corsHeaders);
      } else if (path === '/products/seed' && method === 'POST') {
        return await seedProducts(env, corsHeaders);
      } else if (path === '/products/summary' && method === 'GET') {
        return await summarizeCatalog(env, corsHeaders);
      }

      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      // Details go to Workers Logs, not to the client.
      console.error('products api error', error);
      return new Response(JSON.stringify({ error: 'Internal server error' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  }
};

// A body that isn't a JSON object is the client's mistake (400), not a
// server error. Returns null for invalid JSON, arrays and scalars.
async function readJson(request) {
  try {
    const data = await request.json();
    return data && typeof data === 'object' && !Array.isArray(data) ? data : null;
  } catch {
    return null;
  }
}

// Optional integer fields (stock) must be a non-negative whole number when sent.
function isCount(value) {
  return Number.isInteger(value) && value >= 0;
}

function badRequest(message, corsHeaders) {
  return new Response(JSON.stringify({ error: message }), {
    status: 400,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function getProducts(env, corsHeaders) {
  // Check cache first
  const cached = await env.CACHE.get('products:all');
  if (cached) {
    return new Response(cached, {
      headers: { 
        ...corsHeaders, 
        'Content-Type': 'application/json',
        'X-Products-Cache': 'HIT'
      }
    });
  }

  // Query database
  const stmt = env.DB.prepare(`
    SELECT id, name, description, price, category, stock, created_at, updated_at
    FROM products 
    ORDER BY name
  `);
  
  const result = await stmt.all();
  const response = JSON.stringify({
    products: result.results || [],
    count: result.results?.length || 0,
    timestamp: new Date().toISOString()
  });

  // Cache for 10 minutes
  await env.CACHE.put('products:all', response, { expirationTtl: 600 });

  return new Response(response, {
    headers: { 
      ...corsHeaders, 
      'Content-Type': 'application/json',
      'X-Products-Cache': 'MISS'
    }
  });
}

async function getProduct(id, env, corsHeaders) {
  const stmt = env.DB.prepare(`
    SELECT id, name, description, price, category, stock, created_at, updated_at
    FROM products 
    WHERE id = ?
  `);
  
  const result = await stmt.bind(id).first();
  
  if (!result) {
    return new Response(JSON.stringify({ error: 'Product not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  return new Response(JSON.stringify(result), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function createProduct(request, env, corsHeaders) {
  const data = await readJson(request);
  if (!data) {
    return badRequest('Request body must be a JSON object', corsHeaders);
  }

  // Validate types, not just presence: "19.99" as a string must not land in
  // the DECIMAL column, nor "abc" in the INTEGER one. price 0 is allowed.
  if (typeof data.name !== 'string' || !data.name || typeof data.price !== 'number' || !(data.price >= 0)) {
    return badRequest('Missing required fields: name (string), price (a non-negative number)', corsHeaders);
  }
  if (data.stock !== undefined && !isCount(data.stock)) {
    return badRequest('stock must be a non-negative integer', corsHeaders);
  }

  const now = new Date().toISOString();
  const stmt = env.DB.prepare(`
    INSERT INTO products (name, description, price, category, stock, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?)
  `);
  
  const result = await stmt.bind(
    data.name,
    data.description || '',
    data.price,
    data.category || 'general',
    data.stock || 0,
    now,
    now
  ).run();

  // Clear cache
  await env.CACHE.delete('products:all');

  return new Response(JSON.stringify({
    id: result.meta.last_row_id,
    name: data.name,
    description: data.description || '',
    price: data.price,
    category: data.category || 'general',
    stock: data.stock || 0,
    created_at: now,
    updated_at: now
  }), {
    status: 201,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function updateProduct(id, request, env, corsHeaders) {
  const data = await readJson(request);
  if (!data) {
    return badRequest('Request body must be a JSON object', corsHeaders);
  }
  if (data.price !== undefined && (typeof data.price !== 'number' || !(data.price >= 0))) {
    return badRequest('price must be a non-negative number', corsHeaders);
  }
  if (data.stock !== undefined && !isCount(data.stock)) {
    return badRequest('stock must be a non-negative integer', corsHeaders);
  }
  const now = new Date().toISOString();
  
  // Build dynamic update query
  const updates = [];
  const values = [];
  
  if (data.name !== undefined) {
    updates.push('name = ?');
    values.push(data.name);
  }
  if (data.description !== undefined) {
    updates.push('description = ?');
    values.push(data.description);
  }
  if (data.price !== undefined) {
    updates.push('price = ?');
    values.push(data.price);
  }
  if (data.category !== undefined) {
    updates.push('category = ?');
    values.push(data.category);
  }
  if (data.stock !== undefined) {
    updates.push('stock = ?');
    values.push(data.stock);
  }
  
  if (updates.length === 0) {
    return new Response(JSON.stringify({ error: 'No fields to update' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  updates.push('updated_at = ?');
  values.push(now, id);

  const stmt = env.DB.prepare(`
    UPDATE products 
    SET ${updates.join(', ')}
    WHERE id = ?
  `);
  
  const result = await stmt.bind(...values).run();

  // D1 reports affected rows under meta (result.changes doesn't exist).
  if (result.meta.changes === 0) {
    return new Response(JSON.stringify({ error: 'Product not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  // Clear cache
  await env.CACHE.delete('products:all');

  return new Response(JSON.stringify({ 
    message: 'Product updated successfully',
    updated_at: now
  }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function deleteProduct(id, env, corsHeaders) {
  const stmt = env.DB.prepare('DELETE FROM products WHERE id = ?');
  const result = await stmt.bind(id).run();

  if (result.meta.changes === 0) {
    return new Response(JSON.stringify({ error: 'Product not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  // Clear cache
  await env.CACHE.delete('products:all');

  return new Response(JSON.stringify({ 
    message: 'Product deleted successfully' 
  }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function seedProducts(env, corsHeaders) {
  const sampleProducts = [
    {
      name: 'Premium Coffee Beans',
      description: 'Single-origin coffee from Colombian highlands',
      price: 24.99,
      category: 'beverages',
      stock: 50
    },
    {
      name: 'Wireless Headphones',
      description: 'Noise-cancelling Bluetooth headphones',
      price: 199.99,
      category: 'electronics',
      stock: 25
    },
    {
      name: 'Organic Cotton T-Shirt',
      description: 'Sustainable and comfortable cotton tee',
      price: 29.99,
      category: 'clothing',
      stock: 100
    },
    {
      name: 'Smart Water Bottle',
      description: 'Temperature-tracking hydration companion',
      price: 49.99,
      category: 'fitness',
      stock: 35
    },
    {
      name: 'Artisan Chocolate Box',
      description: 'Handcrafted dark chocolate assortment',
      price: 34.99,
      category: 'food',
      stock: 20
    }
  ];

  const now = new Date().toISOString();
  let created = 0;

  // Idempotent: a sample product is inserted only if no product with that
  // name exists, so clicking "Load Sample Data" twice doesn't duplicate the
  // catalog. (The schema has no UNIQUE constraint on name; real products may
  // legitimately share one.)
  for (const product of sampleProducts) {
    const result = await env.DB.prepare(`
      INSERT INTO products (name, description, price, category, stock, created_at, updated_at)
      SELECT ?, ?, ?, ?, ?, ?, ?
      WHERE NOT EXISTS (SELECT 1 FROM products WHERE name = ?)
    `).bind(
      product.name,
      product.description,
      product.price,
      product.category,
      product.stock,
      now,
      now,
      product.name
    ).run();

    created += result.meta.changes ?? 0;
  }

  // Clear cache
  await env.CACHE.delete('products:all');

  return new Response(JSON.stringify({
    message: `Seeded ${created} products (${sampleProducts.length - created} already present)`,
    created,
    skipped: sampleProducts.length - created,
    timestamp: now
  }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

/**
 * AI catalog summary — Workers AI call routed through the AI Gateway.
 * The gateway (id passed via the AI_GATEWAY_ID binding) applies caching,
 * retries and request logging to every model invocation.
 */
async function summarizeCatalog(env, corsHeaders) {
  if (!env.AI) {
    return new Response(JSON.stringify({ error: 'AI binding not available' }), {
      status: 503,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  // Reuse the cached product list as context for the summary
  let cached = await env.CACHE.get('products:all');
  if (!cached) {
    const result = await env.DB.prepare('SELECT id, name, price, category FROM products ORDER BY name').all();
    cached = JSON.stringify({ products: result.results || [] });
  }

  const catalog = JSON.parse(cached).products || [];
  if (catalog.length === 0) {
    return new Response(JSON.stringify({ error: 'No products to summarize — seed first' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  const catalogText = catalog
    .map(p => `- ${p.name} ($${p.price}, ${p.category})`)
    .join('\n');

  const response = await env.AI.run('@cf/meta/llama-3.1-8b-instruct', {
    prompt: `Write a 2-sentence friendly summary of this store catalog:\n${catalogText}`,
    max_tokens: 120
  }, {
    gateway: {
      id: env.AI_GATEWAY_ID
    }
  });

  return new Response(JSON.stringify({
    summary: response.response || '',
    model: '@cf/meta/llama-3.1-8b-instruct',
    ai_gateway: env.AI_GATEWAY_ID,
    product_count: catalog.length,
    timestamp: new Date().toISOString()
  }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}