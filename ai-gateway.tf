# AI Gateway
#
# Terraform concept: a plain resource plus an output. The products-api Worker
# (workers.tf) gets the gateway's ID through a plain_text binding, so model
# calls get the gateway's caching, retries and logging.
# Note: in v5 the gateway's name is its `id`.

resource "cloudflare_ai_gateway" "demo" {
  account_id = var.account_id
  # In v5 the gateway's name is its `id`
  id = "demo-ai-gateway"

  cache_invalidate_on_update = true
  cache_ttl                  = 3600
  collect_logs               = true

  rate_limiting_interval = 60
  rate_limiting_limit    = 1000

  retry_backoff      = "constant"
  retry_delay        = 1000
  retry_max_attempts = 3

  workers_ai_billing_mode = "unified"
}

output "ai_gateway_id" {
  description = "AI Gateway ID used by the products Worker"
  value       = cloudflare_ai_gateway.demo.id
}
