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

# Every input is set here, so the tests don't depend on your local
# terraform.tfvars (terraform test reads it) or TF_VAR_* environment.
variables {
  admin_password         = "dummy-pw-1234"
  account_id             = "01a7362d546811e79dd32d0171c0d0e6"
  zone_name              = "demo-platform.example"
  origin_ipv4            = "203.0.113.10"
  secondary_origin_ipv4  = "203.0.113.20"
  admin_allowlist_cidr   = "203.0.113.0/24"
  primary_origin_enabled = true
}

# ---------------------------------------------------------------------------
# Zone + DNS
# ---------------------------------------------------------------------------

run "zone_lookup" {
  command = plan

  assert {
    error_message = "zone lookup should filter by the zone name and the account"
    condition     = data.cloudflare_zone.main.filter.name == "demo-platform.example" && data.cloudflare_zone.main.filter.account.id == "01a7362d546811e79dd32d0171c0d0e6"
  }
}

run "dns_records" {
  command = plan

  assert {
    error_message = "root A record should point at the demo origin and be proxied"
    condition     = cloudflare_dns_record.root.type == "A" && cloudflare_dns_record.root.content == "203.0.113.10" && cloudflare_dns_record.root.proxied == true
  }

  assert {
    error_message = "api record should be AAAA at api.<zone>"
    condition     = cloudflare_dns_record.api.type == "AAAA" && cloudflare_dns_record.api.name == "api.demo-platform.example"
  }

  assert {
    error_message = "admin record should be AAAA at admin.<zone>"
    condition     = cloudflare_dns_record.admin.type == "AAAA" && cloudflare_dns_record.admin.name == "admin.demo-platform.example"
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

run "workers_defined" {
  command = plan

  assert {
    error_message = "the four demo Workers should have their expected names"
    condition = [
      cloudflare_worker.api_gateway.name,
      cloudflare_worker.products_api.name,
      cloudflare_worker.order_processor.name,
      cloudflare_worker.admin_panel.name,
    ] == ["demo-api-gateway", "demo-products-api", "demo-order-processor", "demo-admin-panel"]
  }

  assert {
    error_message = "each worker should get a deployed version"
    condition     = alltrue([for v in [cloudflare_worker_version.api_gateway, cloudflare_worker_version.products_api, cloudflare_worker_version.order_processor, cloudflare_worker_version.admin_panel] : v.deploy == true])
  }
}

run "worker_bindings" {
  command = plan

  # Pin both KV namespace IDs at plan time so the assertions can tell the
  # cache namespace from the sessions namespace.
  override_resource {
    target          = cloudflare_workers_kv_namespace.cache
    override_during = plan
    values          = { id = "mock-kv-cache" }
  }

  override_resource {
    target          = cloudflare_workers_kv_namespace.sessions
    override_during = plan
    values          = { id = "mock-kv-sessions" }
  }

  assert {
    error_message = "api_gateway should carry 5 bindings (KV, R2, queue, service, zone name)"
    condition     = length(cloudflare_worker_version.api_gateway.bindings) == 5
  }

  assert {
    error_message = "products_api should carry 4 bindings (D1, KV, AI, gateway id)"
    condition     = length(cloudflare_worker_version.products_api.bindings) == 4
  }

  assert {
    # The products API writes the cached list; the order processor and the
    # admin panel invalidate it, so all three must point at the same namespace.
    error_message = "products_api, order_processor and admin_panel should share the CACHE KV namespace"
    condition = alltrue([
      for v in [cloudflare_worker_version.products_api, cloudflare_worker_version.order_processor, cloudflare_worker_version.admin_panel] :
      anytrue([for b in v.bindings : b.type == "kv_namespace" && b.name == "CACHE" && b.namespace_id == "mock-kv-cache"])
    ])
  }

  assert {
    error_message = "api_gateway should hold the SESSIONS namespace (it's the only Worker that reads sessions)"
    condition     = anytrue([for b in cloudflare_worker_version.api_gateway.bindings : b.type == "kv_namespace" && b.name == "SESSIONS" && b.namespace_id == "mock-kv-sessions"])
  }

  assert {
    error_message = "only the gateway should hold the SESSIONS namespace; nothing else reads sessions"
    condition = alltrue([
      for v in [cloudflare_worker_version.products_api, cloudflare_worker_version.order_processor, cloudflare_worker_version.admin_panel] :
      !anytrue([for b in v.bindings : b.type == "kv_namespace" && b.namespace_id == "mock-kv-sessions"])
    ])
  }

  assert {
    error_message = "products_api should have a Workers AI binding"
    condition     = anytrue([for b in cloudflare_worker_version.products_api.bindings : b.type == "ai"])
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
    error_message = "managed WAF should live in the managed firewall phase"
    condition     = cloudflare_ruleset.waf_managed.phase == "http_request_firewall_managed"
  }

  assert {
    error_message = "managed WAF should carry 3 rules (exception + 2 execute)"
    condition     = length(cloudflare_ruleset.waf_managed.rules) == 3
  }

  assert {
    error_message = "949110 exception: skip map should have exactly one ruleset key"
    condition     = length(keys(cloudflare_ruleset.waf_managed.rules[0].action_parameters.rules)) == 1
  }

  assert {
    error_message = "949110 exception: the OWASP ruleset key must be present"
    condition     = contains(keys(cloudflare_ruleset.waf_managed.rules[0].action_parameters.rules), "4814384a9e5d4991b9815dcfc25d2f1f")
  }

  assert {
    error_message = "949110 exception: rule ID must be the official 32-hex (...843b323c)"
    condition     = can(regex("6179ae15870a4bb7b2d480d4843b323c", jsonencode(cloudflare_ruleset.waf_managed.rules[0].action_parameters.rules)))
  }

  assert {
    error_message = "exception (skip) must precede the execute rules"
    condition     = cloudflare_ruleset.waf_managed.rules[0].action == "skip" && alltrue([for i, r in cloudflare_ruleset.waf_managed.rules : r.action == "execute" if i > 0])
  }

  assert {
    error_message = "Cloudflare Managed Ruleset should be executed with its official ID"
    condition     = cloudflare_ruleset.waf_managed.rules[1].action_parameters.id == "efb7b8c949ac4650a09736fc376e9aee"
  }

  assert {
    error_message = "OWASP Core Ruleset should be executed with its official ID"
    condition     = cloudflare_ruleset.waf_managed.rules[2].action_parameters.id == "4814384a9e5d4991b9815dcfc25d2f1f"
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

  assert {
    error_message = "admin rule should reference the corporate IP allowlist"
    condition     = anytrue([for r in cloudflare_ruleset.waf_custom.rules : can(regex("203\\.0\\.113\\.0/24", r.expression))])
  }

  # Regression: these rules once matched the path "/admin", but the admin
  # panel is served at admin.<zone>/ and never has /admin in its path.
  assert {
    error_message = "admin allowlist rule should match the admin panel's hostname"
    condition     = [for r in cloudflare_ruleset.waf_custom.rules : r.expression if r.ref == "challenge_admin_non_allowlisted"] == ["(http.host eq \"admin.demo-platform.example\" and not ip.src in {203.0.113.0/24})"]
  }

  assert {
    error_message = "OWASP 949110 skip should be limited to the admin panel's hostname"
    condition     = cloudflare_ruleset.waf_managed.rules[0].expression == "(http.host eq \"admin.demo-platform.example\")"
  }
}

run "waf_rate_limit_ruleset" {
  command = plan

  assert {
    error_message = "rate limiting should be in the ratelimit phase"
    condition     = cloudflare_ruleset.waf_rate_limit.phase == "http_ratelimit"
  }

  assert {
    error_message = "rate limit rule should be per-IP and per-colo (the API requires cf.colo.id)"
    condition     = toset(cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.characteristics) == toset(["cf.colo.id", "ip.src"])
  }

  assert {
    error_message = "rate limit should allow 50 requests per 10s window"
    condition     = cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.requests_per_period == 50 && cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.period == 10
  }

  assert {
    error_message = "rate limit should block for 10s, the only duration every plan (including Free) accepts"
    condition     = cloudflare_ruleset.waf_rate_limit.rules[0].ratelimit.mitigation_timeout == 10
  }
}

run "waf_redirects" {
  command = plan

  assert {
    error_message = "redirects ruleset should be preserved from the v4 config"
    condition     = cloudflare_ruleset.redirects.phase == "http_request_dynamic_redirect"
  }

  assert {
    error_message = "redirects ruleset should carry exactly 1 enabled rule (Rule 2 HTTPS toggle stays commented)"
    condition     = length(cloudflare_ruleset.redirects.rules) == 1
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
    error_message = "cache rules should be bypass_cache_api then cache_static_assets"
    condition     = [for r in cloudflare_ruleset.cache_rules.rules : r.ref] == ["bypass_cache_api", "cache_static_assets"]
  }

  # Worker responses (api.<zone>, admin.<zone>) never reach the cache, so a
  # cache rule only does something on the origin-backed root hostname.
  assert {
    error_message = "the caching rule should target the origin-backed root hostname"
    condition     = startswith(cloudflare_ruleset.cache_rules.rules[1].expression, "(http.host eq \"demo-platform.example\"")
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
  # Stay on plan: a mocked apply would still run the local-exec provisioners
  # (wrangler / empty-r2.py). Pin IDs at plan time so the wiring is comparable.
  command = plan

  override_resource {
    target          = cloudflare_load_balancer_monitor.http
    override_during = plan
    values          = { id = "mock-monitor" }
  }

  override_resource {
    target          = cloudflare_load_balancer_pool.primary
    override_during = plan
    values          = { id = "mock-pool-primary" }
  }

  override_resource {
    target          = cloudflare_load_balancer_pool.secondary
    override_during = plan
    values          = { id = "mock-pool-secondary" }
  }

  assert {
    error_message = "health monitor should probe /health over HTTP with the app Host header"
    condition     = cloudflare_load_balancer_monitor.http.path == "/health" && cloudflare_load_balancer_monitor.http.type == "http" && contains(cloudflare_load_balancer_monitor.http.header["Host"], "app.demo-platform.example")
  }

  assert {
    error_message = "both pools should share the one health monitor"
    condition     = cloudflare_load_balancer_pool.primary.monitor == cloudflare_load_balancer_monitor.http.id && cloudflare_load_balancer_pool.secondary.monitor == cloudflare_load_balancer_monitor.http.id
  }

  assert {
    error_message = "pools should use the primary and secondary origin addresses"
    condition     = cloudflare_load_balancer_pool.primary.origins[0].address == "203.0.113.10" && cloudflare_load_balancer_pool.secondary.origins[0].address == "203.0.113.20"
  }

  assert {
    error_message = "load balancer should fail over primary -> secondary (steering off, ordered pools)"
    condition     = cloudflare_load_balancer.app.steering_policy == "off" && length(cloudflare_load_balancer.app.default_pools) == 2 && cloudflare_load_balancer.app.default_pools[0] == cloudflare_load_balancer_pool.primary.id && cloudflare_load_balancer.app.fallback_pool == cloudflare_load_balancer_pool.secondary.id
  }

  assert {
    error_message = "primary origin should be enabled by default"
    condition     = cloudflare_load_balancer_pool.primary.origins[0].enabled
  }
}

run "load_balancer_failover_toggle" {
  command = plan

  variables {
    primary_origin_enabled = false
  }

  assert {
    error_message = "primary_origin_enabled=false should drain the primary origin"
    condition     = !cloudflare_load_balancer_pool.primary.origins[0].enabled
  }

  assert {
    error_message = "secondary origin must stay enabled during failover"
    condition     = cloudflare_load_balancer_pool.secondary.origins[0].enabled
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

# ---------------------------------------------------------------------------
# Variable overrides + validation (negative tests)
# ---------------------------------------------------------------------------

run "origin_and_allowlist_overrides" {
  command = plan

  variables {
    origin_ipv4          = "198.51.100.7"
    admin_allowlist_cidr = "198.51.100.0/24"
  }

  assert {
    error_message = "root DNS record should follow origin_ipv4"
    condition     = cloudflare_dns_record.root.content == "198.51.100.7"
  }

  assert {
    error_message = "LB pool origin should follow origin_ipv4"
    condition     = cloudflare_load_balancer_pool.primary.origins[0].address == "198.51.100.7"
  }

  assert {
    error_message = "admin WAF rule should follow admin_allowlist_cidr"
    condition     = anytrue([for r in cloudflare_ruleset.waf_custom.rules : strcontains(r.expression, "198.51.100.0/24")])
  }
}

run "rules_have_stable_refs" {
  command = plan

  assert {
    error_message = "every ruleset rule should set ref so rule IDs survive edits"
    condition = alltrue([
      for r in concat(
        cloudflare_ruleset.waf_managed.rules,
        cloudflare_ruleset.waf_custom.rules,
        cloudflare_ruleset.waf_rate_limit.rules,
        cloudflare_ruleset.redirects.rules,
        cloudflare_ruleset.cache_rules.rules,
      ) : r.ref != null && r.ref != ""
    ])
  }
}

run "workers_observability" {
  command = plan

  assert {
    error_message = "every Worker should have Workers Logs enabled"
    condition     = alltrue([for w in [cloudflare_worker.api_gateway, cloudflare_worker.products_api, cloudflare_worker.order_processor, cloudflare_worker.admin_panel] : w.observability.enabled && w.observability.logs.enabled && w.observability.logs.invocation_logs])
  }
}

run "rejects_bad_account_id" {
  command = plan

  variables {
    account_id = "not-an-account-id"
  }

  expect_failures = [var.account_id]
}

run "rejects_bad_origin_ip" {
  command = plan

  variables {
    origin_ipv4 = "999.1.1.1"
  }

  expect_failures = [var.origin_ipv4]
}

run "rejects_bad_allowlist_cidr" {
  command = plan

  variables {
    admin_allowlist_cidr = "203.0.113.0"
  }

  expect_failures = [var.admin_allowlist_cidr]
}

run "rejects_short_admin_password" {
  command = plan

  variables {
    admin_password = "demo123"
  }

  expect_failures = [var.admin_password]
}

run "admin_password_is_a_secret_binding" {
  command = plan

  assert {
    error_message = "admin panel should receive ADMIN_PASSWORD as secret_text, not plain_text"
    condition     = anytrue([for b in cloudflare_worker_version.admin_panel.bindings : b.name == "ADMIN_PASSWORD" && b.type == "secret_text"])
  }

  assert {
    error_message = "no Worker should carry a plain_text binding that looks like a credential"
    condition     = alltrue(flatten([for v in [cloudflare_worker_version.api_gateway, cloudflare_worker_version.products_api, cloudflare_worker_version.order_processor, cloudflare_worker_version.admin_panel] : [for b in v.bindings : !(b.type == "plain_text" && can(regex("(?i)pass|secret|token|key", b.name)))]]))
  }
}

run "rejects_ipv6_origin" {
  command = plan

  variables {
    origin_ipv4 = "2001:db8::1"
  }

  expect_failures = [var.origin_ipv4]
}

run "rejects_bad_zone_name" {
  command = plan

  variables {
    zone_name = "https://Example.com"
  }

  expect_failures = [var.zone_name]
}

run "rejects_bad_secondary_origin_ip" {
  command = plan

  variables {
    secondary_origin_ipv4 = "203.0.113.300"
  }

  expect_failures = [var.secondary_origin_ipv4]
}

run "rejects_same_origin_for_both_pools" {
  command = plan

  variables {
    secondary_origin_ipv4 = "203.0.113.10" # same as origin_ipv4
  }

  expect_failures = [cloudflare_load_balancer.app]
}

run "warns_when_zone_not_active" {
  command = plan

  override_data {
    target          = data.cloudflare_zone.main
    override_during = plan
    values = {
      id     = "023e105f4ecef8ad9ca31a8372d0c353"
      status = "pending"
    }
  }

  expect_failures = [check.zone_is_active]
}
