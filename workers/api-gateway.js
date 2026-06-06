/**
 * Demo API Gateway Worker
 * Routes requests to appropriate services and handles auth
 */

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Add CORS headers
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    };

    // Handle OPTIONS request
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      // Route to different services
      if (path.startsWith('/api/products')) {
        return handleProducts(request, env, corsHeaders);
      } else if (path.startsWith('/api/orders')) {
        return handleOrders(request, env, corsHeaders);
      } else if (path.startsWith('/api/upload')) {
        return handleUpload(request, env, corsHeaders);
      } else if (path.startsWith('/api/auth')) {
        return handleAuth(request, env, corsHeaders);
      } else {
        return new Response(JSON.stringify({ 
          error: 'Not found',
          available_endpoints: [
            '/api/products',
            '/api/orders', 
            '/api/upload',
            '/api/auth'
          ]
        }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
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

async function handleProducts(request, env, corsHeaders) {
  const url = new URL(request.url);
  
  if (request.method === 'GET') {
    // Try cache first
    const cacheKey = `products:${url.search}`;
    const cached = await env.SESSIONS.get(cacheKey);
    
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
    const stmt = env.DB.prepare('SELECT * FROM products ORDER BY name LIMIT 50');
    const results = await stmt.all();
    
    const response = JSON.stringify({
      products: results.results || [],
      count: results.results?.length || 0,
      cached_at: new Date().toISOString()
    });

    // Cache for 5 minutes
    await env.SESSIONS.put(cacheKey, response, { expirationTtl: 300 });

    return new Response(response, {
      headers: { 
        ...corsHeaders, 
        'Content-Type': 'application/json',
        'X-Cache': 'MISS'
      }
    });
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function handleOrders(request, env, corsHeaders) {
  if (request.method === 'POST') {
    const orderData = await request.json();
    
    // Validate order
    if (!orderData.customer_id || !orderData.items) {
      return new Response(JSON.stringify({ error: 'Missing required fields' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Generate order ID
    const orderId = crypto.randomUUID();
    const timestamp = new Date().toISOString();

    // Queue for processing
    await env.ORDER_QUEUE.send({
      order_id: orderId,
      customer_id: orderData.customer_id,
      items: orderData.items,
      total: orderData.total,
      created_at: timestamp
    });

    return new Response(JSON.stringify({
      order_id: orderId,
      status: 'queued',
      message: 'Order received and queued for processing'
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function handleUpload(request, env, corsHeaders) {
  if (request.method === 'POST') {
    try {
      const formData = await request.formData();
      const file = formData.get('file');
      
      if (!file) {
        return new Response(JSON.stringify({ error: 'No file provided' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      // Generate unique filename
      const filename = `${crypto.randomUUID()}-${file.name}`;
      
      // Upload to R2
      await env.UPLOADS.put(filename, file.stream(), {
        httpMetadata: {
          contentType: file.type,
        },
        customMetadata: {
          uploadedAt: new Date().toISOString(),
        },
      });

      return new Response(JSON.stringify({
        filename: filename,
        size: file.size,
        type: file.type,
        url: `https://uploads.demo-platform.example/${filename}`
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      return new Response(JSON.stringify({ 
        error: 'Upload failed',
        message: error.message 
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}

async function handleAuth(request, env, corsHeaders) {
  const url = new URL(request.url);
  
  if (request.method === 'POST' && url.pathname === '/api/auth/login') {
    const loginData = await request.json();
    
    // Demo auth - accept any email/password
    if (loginData.email && loginData.password) {
      const sessionId = crypto.randomUUID();
      const sessionData = {
        user_id: crypto.randomUUID(),
        email: loginData.email,
        created_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()
      };

      await env.SESSIONS.put(`session:${sessionId}`, JSON.stringify(sessionData), {
        expirationTtl: 86400 // 24 hours
      });

      return new Response(JSON.stringify({
        session_id: sessionId,
        user: {
          id: sessionData.user_id,
          email: sessionData.email
        },
        expires_at: sessionData.expires_at
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    return new Response(JSON.stringify({ error: 'Invalid credentials' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  if (request.method === 'GET' && url.pathname === '/api/auth/me') {
    const sessionId = request.headers.get('Authorization')?.replace('Bearer ', '');
    
    if (!sessionId) {
      return new Response(JSON.stringify({ error: 'No session token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const sessionData = await env.SESSIONS.get(`session:${sessionId}`);
    if (!sessionData) {
      return new Response(JSON.stringify({ error: 'Invalid session' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const session = JSON.parse(sessionData);
    return new Response(JSON.stringify({
      user: {
        id: session.user_id,
        email: session.email
      },
      expires_at: session.expires_at
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }

  return new Response(JSON.stringify({ error: 'Method not allowed' }), {
    status: 405,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  });
}