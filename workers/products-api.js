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

      if (path === '/products' && method === 'GET') {
        return await getProducts(env, corsHeaders);
      } else if (path === '/products' && method === 'POST') {
        return await createProduct(request, env, corsHeaders);
      } else if (path.match(/\/products\/\d+/) && method === 'GET') {
        const id = path.split('/').pop();
        return await getProduct(id, env, corsHeaders);
      } else if (path.match(/\/products\/\d+/) && method === 'PUT') {
        const id = path.split('/').pop();
        return await updateProduct(id, request, env, corsHeaders);
      } else if (path.match(/\/products\/\d+/) && method === 'DELETE') {
        const id = path.split('/').pop();
        return await deleteProduct(id, env, corsHeaders);
      } else if (path === '/products/seed' && method === 'POST') {
        return await seedProducts(env, corsHeaders);
      }

      return new Response(JSON.stringify({ error: 'Not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      return new Response(JSON.stringify({ 
        error: 'Internal server error',
        message: error.message 
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  }
};

async function getProducts(env, corsHeaders) {
  // Check cache first
  const cached = await env.CACHE.get('products:all');
  if (cached) {
    return new Response(cached, {
      headers: { 
        ...corsHeaders, 
        'Content-Type': 'application/json',
        'X-Cache': 'HIT'
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
      'X-Cache': 'MISS'
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
  const data = await request.json();
  
  // Validate required fields
  if (!data.name || !data.price) {
    return new Response(JSON.stringify({ 
      error: 'Missing required fields: name, price' 
    }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
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
  const data = await request.json();
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
  
  if (result.changes === 0) {
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
  
  if (result.changes === 0) {
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

  for (const product of sampleProducts) {
    try {
      const stmt = env.DB.prepare(`
        INSERT INTO products (name, description, price, category, stock, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `);
      
      await stmt.bind(
        product.name,
        product.description,
        product.price,
        product.category,
        product.stock,
        now,
        now
      ).run();
      
      created++;
    } catch (error) {
      // Product might already exist, continue
      console.log(`Skipped ${product.name}: ${error.message}`);
    }
  }

  // Clear cache
  await env.CACHE.delete('products:all');

  return new Response(JSON.stringify({
    message: `Seeded ${created} products`,
    timestamp: now
  }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}