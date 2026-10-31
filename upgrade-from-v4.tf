# Upgrading from provider v4
#
# Terraform concept: `moved` blocks.
#
# When a resource's address changes (new type or new name), Terraform by
# default sees the old address vanish and a new one appear, so it plans
# DESTROY + CREATE. A `moved` block says "same object, new address", and the
# plan shows "(moved from ...)" instead.
#
# Moving between resource TYPES only works if the provider implements it.
# These blocks were verified with `terraform plan` against v5.28.1. They are
# harmless on fresh installs and can be deleted once every existing state has
# been applied with v5.

# --- DNS: cloudflare_record (v4) -> cloudflare_dns_record (v5) -- SUPPORTED ----

moved {
  from = cloudflare_record.root
  to   = cloudflare_dns_record.root
}

moved {
  from = cloudflare_record.api
  to   = cloudflare_dns_record.api
}

moved {
  from = cloudflare_record.admin
  to   = cloudflare_dns_record.admin
}

# --- Workers: cloudflare_workers_script (v4) -> cloudflare_worker (v5) ----------
#
# NOT SUPPORTED as a `moved` block. Plan fails with "Unable to Move Resource
# State: the target resource implementation does not include move resource
# state." (Cloudflare's tf-migrate maps v4 workers_script to v5
# workers_script, not to the newer cloudflare_worker.)
#
# To adopt existing v4 Workers without deleting them, use two other Terraform
# concepts instead, once per Worker:
#
#   1. `removed` forgets the old resource without destroying the real Worker:
#
#        removed {
#          from = cloudflare_workers_script.api_gateway
#          lifecycle { destroy = false }
#        }
#
#   2. `import` adopts the existing Worker under its new resource type.
#      worker_id is the Worker's immutable ID (from the API), not its name:
#
#        import {
#          to = cloudflare_worker.api_gateway
#          id = "<account_id>/<worker_id>"
#        }
#
# Then `terraform plan` shows the import, and cloudflare_worker_version
# uploads the code as a new version.
