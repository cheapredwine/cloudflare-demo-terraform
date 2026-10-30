# Queue consumer (provider v5: first-class resource, replaces the
# null_resource + wrangler local-exec workaround used on v4)

resource "cloudflare_queue_consumer" "orders" {
  account_id  = var.account_id
  queue_id    = cloudflare_queue.orders.queue_id
  script_name = cloudflare_worker.workers["order_processor"].name
  type        = "worker"

  settings = {
    batch_size  = 10
    max_retries = 3
  }
}
