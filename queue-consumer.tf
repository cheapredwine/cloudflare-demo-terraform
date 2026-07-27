resource "null_resource" "queue_consumer" {
  depends_on = [
    cloudflare_queue.orders,
    cloudflare_workers_script.order_processor,
  ]

  triggers = {
    queue_name      = cloudflare_queue.orders.name
    consumer_script = cloudflare_workers_script.order_processor.name
    script_hash     = filemd5("${path.module}/workers/order-processor.js")
    account_id      = var.account_id
    api_token       = var.cloudflare_api_token
  }

  provisioner "local-exec" {
    command = <<-EOT
      wrangler queues consumer worker remove ${self.triggers.queue_name} ${self.triggers.consumer_script} >/dev/null 2>&1 || true
      wrangler queues consumer worker add ${self.triggers.queue_name} ${self.triggers.consumer_script}
    EOT

    environment = {
      CLOUDFLARE_API_TOKEN  = lookup(self.triggers, "api_token", "")
      CLOUDFLARE_ACCOUNT_ID = lookup(self.triggers, "account_id", "")
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "wrangler queues consumer worker remove ${self.triggers.queue_name} ${self.triggers.consumer_script} >/dev/null 2>&1 || true"

    environment = {
      CLOUDFLARE_API_TOKEN  = lookup(self.triggers, "api_token", "")
      CLOUDFLARE_ACCOUNT_ID = lookup(self.triggers, "account_id", "")
    }
  }
}
