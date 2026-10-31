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
3. **Every ruleset rule has a `ref`** (tested).
4. **Tests stay on `command = plan`.** A mocked `apply` still runs the
   `local-exec` provisioners against the real API (guarded in config-checks).
   For unknown IDs at plan time, use `override_resource { override_during = plan }`.
5. **Don't add `moved` blocks from `cloudflare_workers_script`.** The provider
   can't move that type to `cloudflare_worker`; plan fails (verified, guarded).
   DNS `cloudflare_record` → `cloudflare_dns_record` moves are verified to work.
6. **`.sh` and `.ps1` twins stay in sync.**
7. Run `make verify` before committing; it must be green.

## Layout

```
providers.tf          provider pin; empty provider block (token from env)
variables.tf          inputs + validation (account_id, zone_name, origins, allowlist, admin_password, failover toggle)
zone.tf               data source for the existing zone
dns.tf                root A record + api/admin AAAA 100:: placeholders
storage.tf            R2, 2x KV, D1, queue
workers.tf            4 explicit cloudflare_worker + cloudflare_worker_version pairs
routes.tf             api.<zone>/* and admin.<zone>/* routes
queue-consumer.tf     orders queue -> order-processor Worker
waf.tf                managed (CF Managed + OWASP, 949110 skip on /admin), custom, rate limit, redirects (commented Rule 2 HTTPS toggle: keep it)
cdn.tf                cache rules + cache_level / min_tls_version settings
load_balancer.tf      1 monitor, primary + secondary pools, failover LB at app.<zone>
ai-gateway.tf         demo-ai-gateway (products-api calls Workers AI through it)
migrations.tf         terraform_data: D1 schema (wrangler) + R2 empty at destroy
upgrade-from-v4.tf    DNS moved blocks; documented removed+import path for Workers
outputs.tf            URLs, IDs
tests/main.tftest.hcl 25 mocked tests (incl. expect_failures negative tests)
scripts/tests/config-checks.sh  grep guards terraform test can't express
workers/*.js          Worker code (admin-panel reads env.ADMIN_PASSWORD, constant-time compare)
scripts/              lifecycle (run-demo), tests (test, smoke), demos, lib/env.{sh,ps1}; .sh + .ps1
secrets/              gitignored real secrets (README + *.example tracked)
.github/workflows/verify.yml    CI = make verify, no secrets
```

## Key facts

- Official managed-ruleset IDs (from Cloudflare's Terraform WAF docs): CF Managed
  `efb7b8c949ac4650a09736fc376e9aee`, OWASP Core `4814384a9e5d4991b9815dcfc25d2f1f`,
  rule 949110 `6179ae15870a4bb7b2d480d4843b323c`. Phase `http_request_firewall_managed`.
- Default IPs are RFC 5737 documentation addresses: the LB monitor reports
  every pool unhealthy until real origins are set.
- `make verify` = lint (shellcheck, shfmt, node --check, py_compile) + config
  guards + fmt + validate + `terraform test`.
- Required token permissions: see README "Token permissions".

## State of the project

- Fully migrated to v5 (v5.28.1, Terraform 1.17). Never applied on v5;
  a real read-only `plan` against the zone succeeds (all creates).
- The old v4 deployment's state is effectively empty, so the v4 → v5 renames
  don't matter for this account.
- Demo zone: jsherron.com, test account. Never commit account or zone IDs.
