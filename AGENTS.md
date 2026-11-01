# Cloudflare Demo Platform: agent guide

Terraform example (Cloudflare provider v5) for WAF, CDN, load balancing, rate
limiting, Workers and AI Gateway audiences. **The goal is to make Terraform
obvious.** Prefer explicit, readable HCL over clever HCL. User-facing docs
live in README.md only.

## Rules for changes

1. **Obvious over clever.** No `for_each` / `try()` / dynamic tricks where
   writing the blocks out reads better (that's why `workers.tf` repeats itself).
   Every `.tf` file opens with a header naming the Terraform concept it shows.
   Keep it true when you edit the file.
2. **Terraform gets credentials only from the environment.** `CLOUDFLARE_API_TOKEN`
   (the provider, wrangler and `scripts/empty-r2.py` all read it), and
   `TF_VAR_admin_password` (a sensitive variable that becomes a `secret_text`
   binding). Never add a token variable. Scripts fill both from the gitignored
   `secrets/` store through `scripts/lib/env.sh` / `env.ps1`, without overriding
   values that are already set (tested in config-checks). Never print them.
3. **Every ruleset rule has a `ref`** (tested). Admin rules match the host
   `admin.<zone>`, not a path. No `matches` operator (Business+ only; guarded).
   Cache rules only affect origin traffic, not Worker responses.
4. **Every test `run` says `command = plan`.** The default is apply, and a
   mocked apply still runs the `local-exec` provisioners against the real API
   (guarded in config-checks).
   For unknown IDs at plan time, use `override_resource { override_during = plan }`.
5. **Don't add `moved` blocks from `cloudflare_workers_script`.** The provider
   can't move that type to `cloudflare_worker`; plan fails (verified, guarded).
   DNS `cloudflare_record` → `cloudflare_dns_record` moves are verified to work.
6. **`.sh` and `.ps1` twins stay in sync.** Scripts may only use resource
   addresses that exist in the `.tf` files (guarded). The `.sh` scripts pass
   the admin password to curl with `-K` (`admin_curl_config`), never `-u`.
7. **`admin_allowlist_cidr` has no default** (guarded): the WAF challenges
   everyone else on `admin.<zone>`, including the test and reset scripts.
8. **The admin page escapes every value it renders** with `esc()` (guarded):
   product and order fields come from the public, unauthenticated API.
9. **Every binding in `workers.tf` is read by its Worker** as `env.<NAME>`
   (guarded in config-checks). A Worker that only *consumes* a queue gets no
   queue binding (the consumer is `cloudflare_queue_consumer`); a binding is
   for sending. The `CACHE` KV namespace is shared: products-api writes
   `products:all`, order-processor and admin-panel delete it.
10. **Workers answer bad input with 400 and never leak `error.message`** in a
    500 body (log it with `console.error`; it shows up in Workers Logs). D1
    affected-row counts live at `result.meta.changes`, not `result.changes`.
11. Run `make verify` before committing; it must be green. Don't hand-copy
    counts (tests, resources) into docs; they drift.

## Layout

```
providers.tf          provider pin; empty provider block (token from env)
variables.tf          inputs + validation (account_id, zone_name, origins, allowlist, admin_password, failover toggle)
zone.tf               data source for the existing zone + `check` that it's active
dns.tf                root A record + api/admin AAAA 100:: placeholders (full names)
storage.tf            R2, 2x KV, D1 (commented prevent_destroy example), queue
workers.tf            4 explicit cloudflare_worker + cloudflare_worker_version pairs (only bindings the code reads)
routes.tf             api.<zone>/* and admin.<zone>/* routes (depends_on version + D1 schema)
queue-consumer.tf     orders queue -> order-processor Worker
waf.tf                managed (CF Managed + OWASP, 949110 skip on admin.<zone>), custom, rate limit (Free-plan limits), redirects (commented Rule 2 HTTPS toggle: keep it)
cdn.tf                cache rules for the origin-backed root host + cache_level / min_tls_version settings
load_balancer.tf      1 monitor, primary + secondary pools, failover LB at app.<zone> (precondition: origins differ)
ai-gateway.tf         demo-ai-gateway (products-api calls Workers AI through it; postpaid billing)
migrations.tf         terraform_data: D1 schema (wrangler) + R2 empty at destroy
upgrade-from-v4.tf    DNS moved blocks; documented removed+import path for Workers
outputs.tf            URLs, IDs
tests/main.tftest.hcl mocked tests (incl. expect_failures negative tests); every input pinned
scripts/tests/config-checks.sh  grep guards terraform test can't express
workers/*.js          Worker code (admin-panel reads env.ADMIN_PASSWORD, constant-time compare)
scripts/              lifecycle (run-demo), tests (test, smoke), demos, lib/env.{sh,ps1}; .sh + .ps1
secrets/              gitignored real secrets (README + *.example tracked)
.github/workflows/verify.yml    CI = make verify, no secrets
.github/dependabot.yml          weekly PRs for the SHA-pinned actions (provider bumps stay manual: see providers.tf)
```

## Key facts

- Official managed-ruleset IDs (from Cloudflare's Terraform WAF docs): CF Managed
  `efb7b8c949ac4650a09736fc376e9aee`, OWASP Core `4814384a9e5d4991b9815dcfc25d2f1f`,
  rule 949110 `6179ae15870a4bb7b2d480d4843b323c`. Phase `http_request_firewall_managed`.
- Default IPs are RFC 5737 documentation addresses: the LB monitor reports
  every pool unhealthy until real origins are set.
- Destroy doesn't revert `cloudflare_zone_setting`s or delete individual
  `cloudflare_worker_version`s: the provider's Delete only drops them from state.
- `make verify` = lint (shellcheck, shfmt, node --check, py_compile) + config
  guards + fmt + validate + `terraform test`.
- Required token permissions: see README "Token permissions".

## State of the project

- Fully migrated to v5 (v5.28.1; Terraform >= 1.11, tested with 1.17). Never applied on v5;
  a real read-only `plan` against the zone succeeds (all creates).
- The old v4 deployment's state is effectively empty, so the v4 → v5 renames
  don't matter for this account.
- Demo zone: jsherron.com, test account. Never commit account or zone IDs.
