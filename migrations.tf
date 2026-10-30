# D1 schema application (terraform_data replaces null_resource)
#
# The Cloudflare API has no first-class D1 schema resource, so the schema
# file is applied with `wrangler d1 execute --remote` (idempotent via
# IF NOT EXISTS). The API token is passed only through the provisioner
# environment (not stored in triggers/state).
#
# R2 cleanup: the Cloudflare API refuses to delete non-empty R2 buckets and
# provider v5 has no force-destroy, so a destroy-time provisioner empties the
# bucket first. Terraform forbids non-self references in destroy provisioners,
# so the API token must be available in the calling shell's
# CLOUDFLARE_API_TOKEN env var (run-demo.sh sets it when it can).

resource "terraform_data" "d1_schema" {
  depends_on = [cloudflare_d1_database.products, cloudflare_queue_consumer.orders]

  triggers_replace = [
    filemd5("${path.module}/db/schema.sql"),
    cloudflare_d1_database.products.id,
  ]

  provisioner "local-exec" {
    command = "wrangler d1 execute demo-products --file=${path.module}/db/schema.sql --remote"
    environment = {
      CLOUDFLARE_API_TOKEN  = var.cloudflare_api_token
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
