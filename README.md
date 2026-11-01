# Cloudflare Demo Platform (Terraform, provider v5)

> ⚠️ **NOT OFFICIAL CLOUDFLARE.** Not affiliated with or endorsed by Cloudflare, Inc.
> NO WARRANTIES, EXPRESS OR IMPLIED. Effectively untested demo code — read everything
> and dry-run before you run. You assume all risk. See [DISCLAIMER.md](./DISCLAIMER.md).

One Terraform root module that stands up a small e-commerce backend on
Cloudflare and puts the full edge stack in front of it: WAF (managed, custom,
rate limiting), CDN cache rules, load balancing with failover, Workers with
every common binding type, and Workers AI through AI Gateway. Built on the
**Cloudflare Terraform provider v5** (`~> 5.28`).

**Status:** checked offline (`make verify`) and with a real read-only
`terraform plan` against a live zone. It has **not** been applied end to end
on provider v5, so the API may still reject something the plan accepted.

## Find your topic

Everything is one deployable module, but each topic lives in its own file.
Read that file plus its test to see the whole pattern.

| You care about | File | What it shows | Test (`tests/main.tftest.hcl`) |
|---|---|---|---|
| **WAF, managed rules** | [`waf.tf`](./waf.tf) | Cloudflare Managed + OWASP Core rulesets (official IDs), and a **skip exception** for OWASP 949110 on the admin panel's hostname (`admin.<zone>`), placed before the execute rules | `waf_managed_ruleset` |
| **WAF, custom rules** | [`waf.tf`](./waf.tf) | Block scanner paths, challenge empty user agents, challenge `admin.<zone>` outside an IP allowlist | `waf_custom_ruleset` |
| **Rate limiting** | [`waf.tf`](./waf.tf) | Per-IP limit on `/api/*`, counted per data center (50 req / 10 s, 10 s block, which every plan accepts) | `waf_rate_limit_ruleset` |
| **Redirects** | [`waf.tf`](./waf.tf) | Single redirect, plus a commented "force HTTPS" toggle | `waf_redirects` |
| **CDN / cache** | [`cdn.tf`](./cdn.tf) | Cache rules for the origin-backed root hostname (bypass `/api/*`, cache static files for a day) and v5 per-setting `cloudflare_zone_setting` | `cache_rules`, `zone_settings` |
| **Load balancing** | [`load_balancer.tf`](./load_balancer.tf) | One HTTP monitor, **two pools**, active/passive failover, and a variable that takes the primary out of service | `load_balancer_stack`, `load_balancer_failover_toggle` |
| **Workers (v5 pattern)** | [`workers.tf`](./workers.tf), [`routes.tf`](./routes.tf) | `cloudflare_worker` + `cloudflare_worker_version`; KV, R2, D1, Queue, service, AI, plain-text and **secret** bindings; Workers Logs; `depends_on` so routes wait for deployed code | `worker_bindings`, `worker_routes`, `admin_password_is_a_secret_binding` |
| **AI Gateway** | [`ai-gateway.tf`](./ai-gateway.tf) | Gateway with caching, retries and logging; a Worker calls Workers AI through it | `ai_gateway` |
| **Storage + queues** | [`storage.tf`](./storage.tf), [`queue-consumer.tf`](./queue-consumer.tf) | D1, KV, R2, Queue, and a first-class `cloudflare_queue_consumer`; one KV namespace shared by three Workers (the products API fills it, the order processor and admin panel invalidate it) | `storage`, `queue_consumer`, `worker_bindings` |
| **v4 → v5 upgrade** | [`upgrade-from-v4.tf`](./upgrade-from-v4.tf) | `moved` blocks that rename DNS records in place (verified), and the `removed` + `import` route for Workers, which can't be moved across types | — |

Every ruleset rule sets a `ref`, so rule IDs stay stable when you edit a
ruleset ([why](https://developers.cloudflare.com/terraform/troubleshooting/rule-id-changes/)).

## Reading the Terraform

Terraform loads every `.tf` file in the folder as one configuration. File
names are only for people. Read them in this order; each file starts with a
short header naming the Terraform concept it shows.

| # | File | Terraform concept |
|---|---|---|
| 1 | [`providers.tf`](./providers.tf) | Pinning Terraform and the provider; credentials from the environment |
| 2 | [`variables.tf`](./variables.tf) | Inputs, defaults, `validation`, `sensitive` |
| 3 | [`zone.tf`](./zone.tf) | Data source: read something Terraform doesn't manage; a `check` block |
| 4 | [`storage.tf`](./storage.tf) | Plain resources with no dependencies; `lifecycle { prevent_destroy }` (commented) |
| 5 | [`workers.tf`](./workers.tf) | References between resources, a `local`, a secret from a sensitive variable |
| 6 | [`routes.tf`](./routes.tf), [`queue-consumer.tf`](./queue-consumer.tf), [`dns.tf`](./dns.tf) | Wiring resources together by reference; `depends_on` for order a reference can't express (routes, queue consumer); variables and a `local` inside resources (DNS) |
| 7 | [`waf.tf`](./waf.tf), [`cdn.tf`](./cdn.tf) | One resource type (`cloudflare_ruleset`) used per phase; stable `ref`s |
| 8 | [`load_balancer.tf`](./load_balancer.tf) | A boolean variable that changes live behavior; a `precondition` |
| 9 | [`ai-gateway.tf`](./ai-gateway.tf), [`outputs.tf`](./outputs.tf) | Outputs |
| 10 | [`migrations.tf`](./migrations.tf) | Provisioners: the last-resort escape hatch |
| 11 | [`upgrade-from-v4.tf`](./upgrade-from-v4.tf) | `moved`, `removed`, `import`: changing addresses without destroying things |
| 12 | [`tests/main.tftest.hcl`](./tests/main.tftest.hcl) | `terraform test` with a mocked provider |

**How Terraform decides the order.** Nothing here says "create the
database, then the Worker". The Worker refers to
`cloudflare_d1_database.products.id`, so Terraform must create the database
first. Every reference is an edge in a dependency graph, and Terraform
creates independent resources in parallel. `terraform graph` draws it.

**The loop you'll use:**

```bash
terraform init      # download the provider pinned in providers.tf
terraform plan      # compare config with state and show the diff; changes nothing
terraform apply     # make the diff real and record the result in terraform.tfstate
terraform destroy   # delete everything in state (the zone is a data source, so it stays)
```

**Reading a plan.** Each resource in the plan gets a symbol:

| Symbol | Meaning |
|---|---|
| `+` | create |
| `~` | update in place (the resource keeps its ID) |
| `-` | destroy |
| `-/+` | destroy, then create a replacement: an attribute that can't change in place changed. Look for `# forces replacement` |
| `<=` | read a data source |
| `(known after apply)` | the value comes from the API, so the plan can't know it yet |
| `(sensitive value)` | hidden because the input is `sensitive` |

The last line sums it up: `Plan: 33 to add, 0 to change, 0 to destroy.` A
`-/+` you didn't expect is the line to stop and read, since replacing a
database or bucket loses its data.

**Why no modules, `count` or `for_each`.** They remove repetition, and
real projects should use them. Here every resource is written out so that
the block you're reading is the whole story: no inputs to trace into
another folder, no index to work out. The four Workers in `workers.tf` are
the clearest case: repetitive, but each one reads on its own.

## Architecture

```mermaid
flowchart LR
  client([Client]) --> edge

  subgraph edge[Cloudflare edge, zone]
    waf[WAF: managed + custom<br/>rate limiting, redirects]
    cache[Cache rules]
    lb[Load balancer<br/>app.zone]
  end

  edge --> gw[api.zone<br/>API Gateway Worker]
  edge --> admin[admin.zone<br/>Admin Panel Worker]
  lb --> p1[(Primary pool)] & p2[(Secondary pool)]

  gw -- service binding --> products[Products API Worker]
  gw -- queue --> q[[Queue]] --> orders[Order Processor Worker]
  gw --> r2[(R2 uploads)]
  gw --> kvs[(KV sessions)]
  products --> d1[(D1)]
  products --> kvc[(KV cache)]
  products -- AI binding --> aig[AI Gateway] --> wai[Workers AI]
  orders --> d1
  admin --> d1
```

## Quick start

### Prerequisites
- Terraform >= 1.11 (tested with 1.17), [Wrangler](https://developers.cloudflare.com/workers/wrangler/install-and-update/) (applies the D1 schema), Python 3 (empties R2 at destroy)
- An existing zone in your Cloudflare account

### Token permissions

| Scope | Permission |
|---|---|
| Account | Workers Scripts, Workers KV Storage, Workers R2 Storage, D1, Queues, AI Gateway, Load Balancing: Monitors and Pools — all **Edit** |
| Zone | Zone Settings, DNS, Workers Routes, Cache Rules, Zone WAF, Single Redirect, Load Balancers — all **Edit**; Zone **Read** (the zone lookup) |

### Configure

Terraform reads credentials only from environment variables. The scripts
fill those variables from a gitignored `secrets/` folder, so you set them up
once:

```bash
cp terraform.tfvars.example terraform.tfvars              # account_id, zone_name, admin_allowlist_cidr
printf '%s\n' '<token>' > secrets/cloudflare_api_token     # -> CLOUDFLARE_API_TOKEN
printf '%s\n' '<12+ chars>' > secrets/admin_password       # -> TF_VAR_admin_password
chmod 600 secrets/cloudflare_api_token secrets/admin_password
```

Set `admin_allowlist_cidr` to your own public IP (`<ip>/32`). Everyone else
gets a WAF challenge on `admin.<zone>`, and that includes `make test` and
`make reset`, which call the admin panel from your machine.

Already-exported variables always win. If you run plain `terraform`
yourself, export the two variables first (see [`secrets/README.md`](./secrets/README.md)).

### Verify, deploy, tear down

```bash
make verify    # offline: lint, config guards, fmt, validate, mocked tests
make deploy    # terraform apply + smoke checks
make test      # integration suite against the deployed platform
make destroy   # empties R2, then destroys everything
```

The zone itself is a data source; destroy never deletes it. Destroy also
doesn't undo the zone settings in `cdn.tf` (minimum TLS version, cache
level): a setting can't be deleted, so Terraform just stops managing it and
the zone keeps the last value. Change them back in the dashboard if needed.

## Demos

**Platform:** `make deploy-demo` runs sample API calls. `make latency` compares
KV-cache HIT and MISS latency. `make analytics` generates traffic for the
Workers dashboards. The admin panel is at `https://admin.<zone>` (user
`admin`, your `admin_password`). Click **Load Sample Data** first.

**WAF and rate limiting:**
```bash
curl -i https://api.<zone>/.env                                       # custom rule: 403
curl -i -A "" https://api.<zone>/api/products                         # empty UA: challenged
seq 80 | xargs -P 20 -I{} curl -s -o /dev/null -w "%{http_code} " https://api.<zone>/api/products   # 429s once past 50 in 10 s
```

**Load balancer failover:**
```bash
terraform apply -var primary_origin_enabled=false   # disable the primary origin; app.<zone> moves to secondary
terraform apply                                     # restore
```
The default origins are RFC 5737 documentation addresses, so the monitor
reports every pool unhealthy and traffic goes to the fallback pool. Set
`origin_ipv4` and `secondary_origin_ipv4` to real origins that serve `/health`
to show healthy failover.

**AI Gateway:** `curl https://api.<zone>/api/products/summary` summarizes the
catalog with Workers AI through `demo-ai-gateway`. A repeat call is a gateway
cache hit, visible under **AI → AI Gateway → Logs**.

**Terraform concepts:** `./scripts/demos/terraform-demo.sh <demo>` runs one of
`state-inspect`, `drift-detect`, `idempotency`, `targeted`, `plan-file`,
`refresh-only`, `taint-replace`, `var-override`, `graph` or `workspaces`.
`make tf-all` runs them all.

Every user-facing `.sh` script has a matching `.ps1`.

## API

| Method + path (`https://api.<zone>`) | Purpose |
|---|---|
| `GET /api/products`, `GET /api/products/{id}` | List (KV-cached, `X-Products-Cache: HIT/MISS`) and fetch |
| `POST`/`PUT`/`DELETE /api/products[/{id}]` | Create, update, delete (invalidates the cache) |
| `POST /api/products/seed` | Load 5 sample products (idempotent: skips names already present) |
| `GET /api/products/summary` | AI catalog summary through AI Gateway |
| `POST /api/orders` | Queue an order for async processing |
| `POST /api/upload` (multipart `file`) | Store a file in R2; returns its download `url` |
| `GET /api/upload/<filename>` | Download a stored file (always as an attachment) |
| `POST /api/auth/login`, `GET /api/auth/me` | Demo session auth (accepts any credentials) |

Admin (`https://admin.<zone>`, Basic auth): `/`, `/api/stats`, `/api/products`,
`/api/orders`, `POST /setup` (create tables), `POST /reset` (empty every table;
what `make reset` calls before re-seeding).

Bad input gets a `400` with an `error` field; unexpected failures get a `500`
with no details (they go to Workers Logs). Unknown or non-numeric product ids
are `404` on every method.

## Design notes: read before you copy

This is a demo, and a few choices are deliberate shortcuts:

- **Worker code is deployed by Terraform** to keep everything in one apply.
  Many teams deploy Worker code with Wrangler in CI and keep Terraform for the
  surrounding infrastructure (routes, storage, rulesets). Both are valid.
- **Two `local-exec` provisioners** fill API gaps: applying the D1 schema
  (wrangler), and emptying R2 before destroy, since v5 has no force-destroy.
  HashiCorp treats provisioners as a last resort, so don't copy this pattern
  where a resource exists.
- **State is local.** For shared use, add a remote backend, for example the S3
  backend pointed at R2:
  ```hcl
  terraform {
    backend "s3" {
      bucket = "tf-state"
      key    = "demo-platform/terraform.tfstate"
      region = "auto"
      endpoints                   = { s3 = "https://<account_id>.r2.cloudflarestorage.com" }
      skip_credentials_validation = true
      skip_region_validation      = true
      skip_requesting_account_id  = true
      skip_s3_checksum            = true
      use_path_style              = true
    }
  }
  ```
- **Demo auth.** The API's login accepts any credentials. The admin panel uses
  one Basic-auth password from a secret binding, compared in constant time. Put
  [Cloudflare Access](https://developers.cloudflare.com/cloudflare-one/applications/)
  in front of anything real.

## Testing

- **`make verify`** (offline, no credentials; CI in
  [`.github/workflows/verify.yml`](./.github/workflows/verify.yml) runs the same make targets) runs four checks:
  - shellcheck, shfmt, and JS/Python syntax checks.
  - Config guards in `scripts/tests/config-checks.sh`, for things `terraform test` can't express. Among them:
    - the commented HTTPS toggle stays, and no rule uses `matches` / `~` (Business+ only);
    - every test `run` (in `tests/` or the root) says `command = plan`, and every ruleset rule has a `ref`;
    - scripts, the Makefile and this README only name resource addresses that exist, and every test this README names exists;
    - `admin_allowlist_cidr` has no default, and the admin page escapes every value it puts into HTML;
    - every binding in `workers.tf` is read (`env.<NAME>`) by the Worker it's attached to, so no block carries a binding its code ignores;
    - `.sh` / `.ps1` twins offer the same actions, `make tf-all` runs every demo, the secrets loaders behave the same, and the two schema copies match;
    - the Terraform version under Prerequisites matches `providers.tf`.
  - `terraform fmt` (tracked files only) and `terraform validate`.
  - **Mocked `terraform test` cases**, including negative tests that prove each input validation, the load balancer `precondition` and the zone `check` fire.
- **`make test` / `make smoke`** run integration checks against a deployed
  platform (`scripts/tests/test.sh`, `.ps1`).

The mocked tests show the configuration says what it should. They can't show
the API accepts it, for example whether a rule expression parses. Only a real
`plan`/`apply` checks that.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `Authentication error` (10000) on rulesets / LB / AI | The token is missing that permission; see the table above |
| After upgrading from v4, plan shows DNS records being destroyed | A `moved` block doesn't match your state; compare it with `terraform state list` |
| After upgrading from v4, plan fails with "Unable to Move Resource State" | Workers can't be `moved` across types; use `removed` + `import` (see `upgrade-from-v4.tf`) |
| Worker returns `error code: 1101` | Uncaught exception: `wrangler tail demo-api-gateway`, or check the Worker's Logs tab |
| Admin panel says the database isn't initialized | Re-run `terraform apply` (schema step), or `POST /setup` on the admin panel |
| `/api/products/summary` returns 404 | No products yet: seed first (admin panel **Load Sample Data**, or `make reset`) |
| `/api/products/summary` returns 500 | The Workers AI call failed: check **AI → AI Gateway → Logs** for `demo-ai-gateway`, and that Workers AI is enabled on the account |
| Destroy fails on the R2 bucket | `CLOUDFLARE_API_TOKEN` wasn't set in the shell running destroy |

## Cost

The zone is pre-existing. A demo session stays well inside the Workers, D1,
KV, R2 and Queues free tiers. Some features depend on the zone's plan:

- **Managed WAF** (Cloudflare Managed and OWASP rulesets): Pro or higher.
- **Load balancing**: a paid add-on on any plan.
- **Rate limiting**, custom rules, cache rules and redirects work on Free.
  The rate-limit rule uses the Free limits (10 s period and block, path-only
  expression); raise them on paid plans.

### On a Free-plan zone

An apply on a Free zone without the load-balancing add-on fails on the first
paid resource. To run everything else, remove the paid parts before you apply:

1. Delete [`load_balancer.tf`](./load_balancer.tf).
2. In [`waf.tf`](./waf.tf), delete the `cloudflare_ruleset.waf_managed` block.
3. In `tests/main.tftest.hcl`, delete the runs that check them
   (`waf_managed_ruleset`, `load_balancer_stack`,
   `load_balancer_failover_toggle`) and any assertion that names
   `waf_managed` or `cloudflare_load_balancer`, so `make verify` passes.

`primary_origin_enabled` and `secondary_origin_ipv4` are then unused, which
Terraform allows. This is a deliberate trade: one `count` switch would avoid
the deletions, but it would make every block harder to read.

## License

MIT; see [LICENSE](./LICENSE) and [DISCLAIMER.md](./DISCLAIMER.md).
