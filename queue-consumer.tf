# Queue consumer: connects the orders queue to the order-processor Worker
#
# Terraform concept: a resource that only links two others (the queue and the
# Worker). Its references give Terraform the right creation order.

resource "cloudflare_queue_consumer" "orders" {
  account_id  = var.account_id
  queue_id    = cloudflare_queue.orders.queue_id
  script_name = cloudflare_worker.order_processor.name
  type        = "worker"

  # Attach the consumer only once the Worker has code with a queue() handler.
  depends_on = [cloudflare_worker_version.order_processor]

  settings = {
    batch_size  = 10
    max_retries = 3
  }
}
