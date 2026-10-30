# Terraform-native test suite for the Cloudflare Demo Platform.
#
# Uses mock_provider so tests validate configuration shape, resource wiring
# and computed values without touching the Cloudflare API (no credentials
# needed). Run with `make verify` or `terraform test`.

mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      id     = "023e105f4ecef8ad9ca31a8372d0c353"
      name   = "demo-platform.example"
      status = "active"
      name_servers = [
        "ada.ns.cloudflare.com",
        "bob.ns.cloudflare.com",
      ]
      plan    = { name = "Pro Plan" }
      account = { id = "01a7362d546811e79dd32d0171c0d0e6" }
    }
  }
}

variables {
  cloudflare_api_token = "test-token-value-not-a-real-secret"
  account_id           = "01a7362d546811e79dd32d0171c0d0e6"
  zone_name            = "demo-platform.example"
}

# ---------------------------------------------------------------------------
# Zone + DNS
# ---------------------------------------------------------------------------

run "zone_lookup" {
  command = plan

  assert {
    error_message = "zone data source should resolve the demo zone id"
    condition     = data.cloudflare_zone.main.id == "023e105f4ecef8ad9ca31a8372d0c353"
  }
}

run "dns_records" {
  command = plan

  assert {
    error_message = "root A record should point at the demo origin and be proxied"
    condition     = cloudflare_dns_record.root.type == "A" && cloudflare_dns_record.root.proxied == true
  }

  assert {
    error_message = "api record should be AAAA at api.<zone>"
    condition     = cloudflare_dns_record.api.type == "AAAA" && cloudflare_dns_record.api.name == "api"
  }

  assert {
    error_message = "admin record should be AAAA at admin.<zone>"
    condition     = cloudflare_dns_record.admin.type == "AAAA" && cloudflare_dns_record.admin.name == "admin"
  }
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

run "storage" {
  command = plan

  assert {
    error_message = "D1 database name should be demo-products"
    condition     = cloudflare_d1_database.products.name == "demo-products"
  }

  assert {
    error_message = "queue should use the v5 queue_name attribute"
    condition     = cloudflare_queue.orders.queue_name == "demo-order-processing"
  }

  assert {
    error_message = "R2 bucket should be demo-platform-uploads"
    condition     = cloudflare_r2_bucket.uploads.name == "demo-platform-uploads"
  }
}

# ---------------------------------------------------------------------------
# Workers
# ---------------------------------------------------------------------------

run "workers_count" {
  command = plan

  assert {
    error_message = "exactly 4 workers should be defined"
    condition     = length(cloudflare_worker.workers) == 4
  }

  assert {
    error_message = "each worker should get a deployed version"
    condition     = alltrue([for _, v in cloudflare_worker_version.versions : v.deploy == true])
  }
}

run "worker_bindings" {
  command = plan

  assert {
    error_message = "api_gateway should carry 6 bindings (KV, R2, D1, queue, service, zone name)"
    condition     = length(cloudflare_worker_version.versions["api_gateway"].bindings) == 6
  }

  assert {
    error_message = "products_api should carry 4 bindings (D1, KV, AI, gateway id)"
    condition     = length(cloudflare_worker_version.versions["products_api"].bindings) == 4
  }

  assert {
    error_message = "products_api should have a Workers AI binding"
    condition     = anytrue([for b in cloudflare_worker_version.versions["products_api"].bindings : b.type == "ai"])
  }
}

run "worker_routes" {
  command = plan

  assert {
    error_message = "api route should match api.<zone>/*"
    condition     = cloudflare_workers_route.api_gateway_route.pattern == "api.demo-platform.example/*"
  }

  assert {
    error_message = "admin route should match admin.<zone>/*"
    condition     = cloudflare_workers_route.admin_route.pattern == "admin.demo-platform.example/*"
  }
}

# ---------------------------------------------------------------------------
# Queue consumer (v5 first-class resource)
# ---------------------------------------------------------------------------

run "queue_consumer" {
  command = plan

  assert {
    error_message = "queue consumer should attach the order processor"
    condition     = cloudflare_queue_consumer.orders.script_name == "demo-order-processor"
  }

  assert {
    error_message = "queue consumer should be a worker consumer"
    condition     = cloudflare_queue_consumer.orders.type == "worker"
  }

  assert {
    error_message = "queue consumer should retry failed messages 3 times"
    condition     = cloudflare_queue_consumer.orders.settings.max_retries == 3
  }
}

# ---------------------------------------------------------------------------
# WAF
# ---------------------------------------------------------------------------

run "waf_managed_ruleset" {
  command = plan

  assert {
    error_message = "managed WAF should execute the Cloudflare Managed Ruleset"
    condition     = cloudflare_ruleset.waf_managed.phase == "http_config_settings"
  }

  assert {
    error_message = "managed WAF ruleset should carry exactly one execute rule"
    condition     = length(cloudflare_ruleset.waf_managed.rules) == 1
  }
}

run "waf_custom_ruleset" {
  command = plan

  assert {
    error_message = "custom WAF should be in the custom firewall phase"
    condition     = cloudflare_ruleset.waf_custom.phase == "http_request_firewall_custom"
  }

  assert {
    error_message = "custom WAF should define 3 rules"
    condition     = length(cloudflare_ruleset.waf_custom.rules) == 3
  }

  assert {
    error_message = "custom WAF should block scanners"
    condition     = anytrue([for r in cloudflare_ruleset.waf_custom.rules : r.action == "block"])
  }

  assert {
    error_message = "custom WAF should challenge rather than hard-block humans"
    condition     = anytrue([for r in cloudflare_ruleset.waf_custom.rules : r.action == "managed_challenge"])
  }
}

run "waf_rate_limit_ruleset" {
  command = plan

  assert {
    error_message = "rate limiting should be in the ratelimit phase"
    condition     = cloudflare_ruleset.waf_rate_limit.phase == "http_ratelimit"
  }

  assert {
    error_message = "rate limit rule should be per-IP and per-colo"
    condition     = contains(cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.characteristics, "ip.src")
  }

  assert {
    error_message = "rate limit should allow 50 requests per 10s window"
    condition     = cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.requests_per_period == 50 && cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.period == 10
  }
}

run "waf_redirects" {
  command = plan

  assert {
    error_message = "redirects ruleset should be preserved from the v4 config"
    condition     = cloudflare_ruleset.redirects.phase == "http_request_dynamic_redirect"
  }
}

# ---------------------------------------------------------------------------
# CDN / cache
# ---------------------------------------------------------------------------

run "cache_rules" {
  command = plan

  assert {
    error_message = "cache rules should live in the cache settings phase"
    condition     = cloudflare_ruleset.cache_rules.phase == "http_request_cache_settings"
  }

  assert {
    error_message = "cache rules should define 2 rules (bypass API, cache admin)"
    condition     = length(cloudflare_ruleset.cache_rules.rules) == 2
  }
}

run "zone_settings" {
  command = plan

  assert {
    error_message = "cache level should be aggressive"
    condition     = cloudflare_zone_setting.cache_level.value == "aggressive"
  }

  assert {
    error_message = "minimum TLS version should be 1.2"
    condition     = cloudflare_zone_setting.min_tls_version.value == "1.2"
  }
}

# ---------------------------------------------------------------------------
# Load balancing
# ---------------------------------------------------------------------------

run "load_balancer_stack" {
  command = plan

  assert {
    error_message = "health monitor should probe /health over HTTP"
    condition     = cloudflare_load_balancer_monitor.http.path == "/health" && cloudflare_load_balancer_monitor.http.type == "http"
  }

  assert {
    error_message = "pool origin should be the demo origin address"
    condition     = cloudflare_load_balancer_pool.primary.origins[0].address == "203.0.113.10"
  }

  assert {
    error_message = "load balancer should route app.<zone> with a single default pool"
    condition     = cloudflare_load_balancer.app.name == "app.demo-platform.example" && length(cloudflare_load_balancer.app.default_pools) == 1
  }
}

# ---------------------------------------------------------------------------
# AI Gateway
# ---------------------------------------------------------------------------

run "ai_gateway" {
  command = plan

  assert {
    error_message = "gateway id (its name in v5) should be demo-ai-gateway"
    condition     = cloudflare_ai_gateway.demo.id == "demo-ai-gateway"
  }

  assert {
    error_message = "gateway should cache model responses for 1h and invalidate on update"
    condition     = cloudflare_ai_gateway.demo.cache_ttl == 3600 && cloudflare_ai_gateway.demo.cache_invalidate_on_update == true
  }

  assert {
    error_message = "gateway should log requests"
    condition     = cloudflare_ai_gateway.demo.collect_logs == true
  }
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

run "outputs" {
  command = plan

  assert {
    error_message = "api_gateway_url output should be derived from zone_name"
    condition     = output.api_gateway_url == "https://api.demo-platform.example"
  }

  assert {
    error_message = "ai_gateway_id output should be exposed"
    condition     = output.ai_gateway_id == "demo-ai-gateway"
  }

  assert {
    error_message = "load_balancer_hostname output should be exposed"
    condition     = output.load_balancer_hostname == "app.demo-platform.example"
  }
}
