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
        return await handleProducts(request, env, corsHeaders);
      } else if (path.startsWith('/api/orders')) {
        return await handleOrders(request, env, corsHeaders);
      } else if (path.startsWith('/api/upload')) {
        return await handleUpload(request, env, corsHeaders);
      } else if (path.startsWith('/api/auth')) {
        return await handleAuth(request, env, corsHeaders);
      } else {
        return new Response(JSON.stringify({ error: 'Not found' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }
    } catch (error) {
      // Details go to Workers Logs, not to the client.
      console.error('api gateway error', error);
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

async function handleProducts(request, env, corsHeaders) {
  // Rewrite /api/products* -> /products* and proxy to products worker
  const url = new URL(request.url);
  const rewrittenPath = url.pathname.replace(/^\/api/, '');
  const proxiedUrl = `https://products-api.internal${rewrittenPath}${url.search}`;

  const hasBody = !['GET', 'HEAD'].includes(request.method);

  // Strip host header — service bindings don't need it and it can cause errors
  const forwardHeaders = new Headers(request.headers);
  forwardHeaders.delete('host');

  const proxiedRequest = new Request(proxiedUrl, {
    method: request.method,
    headers: forwardHeaders,
    body: hasBody ? request.body : null,
  });

  const response = await env.PRODUCTS_API.fetch(proxiedRequest);

  // Pass through response with CORS headers added
  const newHeaders = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders)) {
    newHeaders.set(key, value);
  }

  return new Response(response.body, {
    status: response.status,
    headers: newHeaders,
  });
}

async function handleOrders(request, env, corsHeaders) {
  if (request.method === 'POST') {
    const orderData = await readJson(request);

    // Validate order
    if (!orderData || !orderData.customer_id || !Array.isArray(orderData.items) || orderData.items.length === 0) {
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
      items: orderData.items, // the order processor prices them from D1
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
  // GET /api/upload/<filename>: read a file back from R2. Served as a
  // download (attachment + nosniff) so an uploaded HTML file can't run
  // script on api.<zone>.
  const key = new URL(request.url).pathname.slice('/api/upload/'.length);
  if (request.method === 'GET' && key) {
    const object = await env.UPLOADS.get(decodeURIComponent(key));
    if (!object) {
      return new Response(JSON.stringify({ error: 'File not found' }), {
        status: 404,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }
    return new Response(object.body, {
      headers: {
        ...corsHeaders,
        'Content-Type': 'application/octet-stream',
        'Content-Disposition': 'attachment',
        'X-Content-Type-Options': 'nosniff',
      }
    });
  }

  if (request.method === 'POST') {
    try {
      let formData;
      try {
        formData = await request.formData();
      } catch {
        return new Response(JSON.stringify({ error: 'No file provided' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      const file = formData.get('file');
      
      if (!file) {
        return new Response(JSON.stringify({ error: 'No file provided' }), {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        });
      }

      // Generate unique filename — file.name may be undefined depending on client
      const originalName = (file.name && file.name !== 'undefined') ? file.name : 'upload';
      const filename = `${crypto.randomUUID()}-${originalName}`;
      
      // Upload to R2
      await env.UPLOADS.put(filename, file, {
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
        url: `https://api.${env.ZONE_NAME}/api/upload/${encodeURIComponent(filename)}`
      }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    } catch (error) {
      console.error('upload failed', error);
      return new Response(JSON.stringify({ error: 'Upload failed' }), {
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
    const loginData = await readJson(request);
    if (!loginData) {
      return new Response(JSON.stringify({ error: 'Request body must be a JSON object' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

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