# Pending review

Decisions waiting on a human. Retire a section (or this file) in the same
session that executes the decision.

## 1. First end-to-end `terraform apply` on provider v5 (2026-11-01)

**What's being decided:** whether to run `make deploy` against the demo zone
with the current config. README "Status" is still honest: the config has
passed `make verify` and a real read-only `plan`, but has **never been
applied on v5**, so the API may reject something the plan accepted (rule
expressions, binding shapes, the v5 `cloudflare_worker_version` upload).

**Why it needs a human:** it is a deploy with cost and blast radius.

- The zone needs **Pro or higher** for the managed WAF rulesets and the
  **load-balancing add-on** for `load_balancer.tf`; otherwise the first paid
  resource fails the apply (see README "On a Free-plan zone" for what to
  delete first).
- Destroy does not revert the two `cloudflare_zone_setting`s (cache level,
  minimum TLS 1.2); the zone keeps them.
- It creates public hostnames `api.`, `admin.` and `app.` on the zone.

**What unblocks it:** a yes (and which plan/add-ons the zone has), then:

```bash
make verify && make deploy && make test   # test.sh now covers the 404/400 paths fixed in PR #6
```

**Pair with it:** bump `local.compatibility_date` in `workers.tf`
(currently `2025-09-01`) — the repo rule is "bump deliberately and re-test",
and this is the first chance to re-test.

**On success:** update README "Status" to say applied on v5 on <date>, record
anything the API rejected in Troubleshooting, and delete this section.
