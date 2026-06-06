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
        console.error('Order processing failed:', error);
        message.retry();
      }
    }
  }
};

async function processOrder(orderData, env) {
  const { order_id, customer_id, items, total, created_at } = orderData;
  
  console.log(`Processing order ${order_id} for customer ${customer_id}`);

  // Insert order into database
  const orderStmt = env.DB.prepare(`
    INSERT INTO orders (id, customer_id, total_amount, status, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?)
  `);
  
  const now = new Date().toISOString();
  await orderStmt.bind(
    order_id,
    customer_id,
    total,
    'processing',
    created_at,
    now
  ).run();

  // Insert order items
  for (const item of items) {
    const itemStmt = env.DB.prepare(`
      INSERT INTO order_items (order_id, product_id, quantity, unit_price)
      VALUES (?, ?, ?, ?)
    `);
    
    await itemStmt.bind(
      order_id,
      item.product_id,
      item.quantity,
      item.unit_price
    ).run();

    // Update product stock
    const stockStmt = env.DB.prepare(`
      UPDATE products 
      SET stock = stock - ?, updated_at = ?
      WHERE id = ? AND stock >= ?
    `);
    
    const stockResult = await stockStmt.bind(
      item.quantity,
      now,
      item.product_id,
      item.quantity
    ).run();

    if (stockResult.changes === 0) {
      throw new Error(`Insufficient stock for product ${item.product_id}`);
    }
  }

  // Simulate payment processing delay
  await new Promise(resolve => setTimeout(resolve, 1000));

  // Update order status to completed
  const updateStmt = env.DB.prepare(`
    UPDATE orders 
    SET status = ?, updated_at = ?
    WHERE id = ?
  `);
  
  await updateStmt.bind('completed', now, order_id).run();

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