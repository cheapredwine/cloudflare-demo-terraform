/**
 * Demo Order Processing Worker
 * Processes orders from queue and handles async operations
 */

export default {
  async fetch(request, env, ctx) {
    return new Response(JSON.stringify({
      service: 'Order Processor',
      status: 'healthy',
      timestamp: new Date().toISOString()
    }), {
      headers: { 'Content-Type': 'application/json' }
    });
  },

  async queue(batch, env, ctx) {
    for (const message of batch.messages) {
      try {
        await processOrder(message.body, env);
        message.ack();
      } catch (error) {
        // Only temporary failures (e.g. D1 unavailable) reach here; a retry
        // is safe because processOrder writes everything in one transaction
        // and skips orders it has already stored.
        console.error('Order processing failed, will retry:', error);
        message.retry();
      }
    }
  }
};

// Messages are delivered at least once, so the same order can arrive twice.
async function processOrder(orderData, env) {
  const { order_id, customer_id, items, created_at } = orderData;

  const existing = await env.DB.prepare('SELECT id FROM orders WHERE id = ?').bind(order_id).first();
  if (existing) {
    console.log(`Order ${order_id} already processed; skipping duplicate delivery`);
    return;
  }

  // Price and stock come from D1, never from the client's message. A bad
  // order is rejected (acked, not retried): a retry would fail the same way.
  let total = 0;
  for (const item of items || []) {
    const product = await env.DB.prepare('SELECT price, stock FROM products WHERE id = ?')
      .bind(item.product_id).first();
    if (!product || !(item.quantity > 0) || product.stock < item.quantity) {
      console.warn(`Order ${order_id} rejected: product ${item.product_id} missing or out of stock`);
      return;
    }
    item.unit_price = product.price;
    total += product.price * item.quantity;
  }
  if (!items || items.length === 0) {
    console.warn(`Order ${order_id} rejected: no items`);
    return;
  }

  console.log(`Processing order ${order_id} for customer ${customer_id}`);

  // One batch = one transaction: the order, its items and the stock changes
  // are stored together or not at all.
  const now = new Date().toISOString();
  const statements = [
    env.DB.prepare(`
      INSERT INTO orders (id, customer_id, total_amount, status, created_at, updated_at)
      VALUES (?, ?, ?, 'completed', ?, ?)
    `).bind(order_id, customer_id, Math.round(total * 100) / 100, created_at, now),
  ];
  for (const item of items) {
    statements.push(
      env.DB.prepare(`
        INSERT INTO order_items (order_id, product_id, quantity, unit_price)
        VALUES (?, ?, ?, ?)
      `).bind(order_id, item.product_id, item.quantity, item.unit_price),
      env.DB.prepare(`
        UPDATE products SET stock = stock - ?, updated_at = ? WHERE id = ?
      `).bind(item.quantity, now, item.product_id),
    );
  }
  await env.DB.batch(statements);

  // Send confirmation (simulated)
  await sendOrderConfirmation(order_id, customer_id, env);

  console.log(`Order ${order_id} completed successfully`);
}

async function sendOrderConfirmation(orderId, customerId, env) {
  // In a real app, this would send email/SMS
  // For demo, we'll just log
  console.log(`📧 Order confirmation sent for ${orderId} to customer ${customerId}`);
  
  // Could also trigger webhooks, update external systems, etc.
  return Promise.resolve();
}