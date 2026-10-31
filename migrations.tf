# Filling gaps the provider can't cover
#
# Terraform concepts:
#   - `terraform_data` + `local-exec` provisioner: run a local command as part
#     of apply or destroy. HashiCorp calls provisioners a last resort; they're
#     used here only because no resource exists for these two jobs.
#   - `triggers_replace`: re-run the command when these values change.
#   - `when = destroy`: run the command before the resource is destroyed.

# D1 schema application (terraform_data replaces null_resource)
#
# The Cloudflare API has no first-class D1 schema resource, so the schema
# file is applied with `wrangler d1 execute --remote` (idempotent via
# IF NOT EXISTS). The API token is inherited from the calling shell's
# CLOUDFLARE_API_TOKEN (never a Terraform variable, never in state).
#
# R2 cleanup: the Cloudflare API refuses to delete non-empty R2 buckets and
# provider v5 has no force-destroy, so a destroy-time provisioner empties the
# bucket first. Terraform forbids non-self references in destroy provisioners,
# so the API token must be available in the calling shell's
# CLOUDFLARE_API_TOKEN env var, the same one the provider uses.

resource "terraform_data" "d1_schema" {
  depends_on = [cloudflare_d1_database.products, cloudflare_queue_consumer.orders]

  triggers_replace = [
    filemd5("${path.module}/db/schema.sql"),
    cloudflare_d1_database.products.id,
  ]

  provisioner "local-exec" {
    command = "wrangler d1 execute demo-products --file=${path.module}/db/schema.sql --remote"
    # wrangler inherits CLOUDFLARE_API_TOKEN from the calling shell.
    environment = {
      CLOUDFLARE_ACCOUNT_ID = var.account_id
    }
  }
}

resource "terraform_data" "r2_cleanup" {
  depends_on = [cloudflare_r2_bucket.uploads]

  triggers_replace = [
    var.account_id,
    cloudflare_r2_bucket.uploads.name,
  ]

  provisioner "local-exec" {
    when    = destroy
    command = "python3 ${path.module}/scripts/empty-r2.py"
    environment = {
      CF_ACCOUNT_ID = self.triggers_replace[0]
      CF_BUCKET     = self.triggers_replace[1]
    }
  }
}
