# Providers
#
# Terraform concepts:
#   - `required_version` pins the Terraform CLI; `required_providers` pins the
#     Cloudflare provider (`~> 5.0` = any 5.x). `.terraform.lock.hcl` records
#     the exact version `terraform init` chose, so commit it.
#   - The provider block is empty on purpose: credentials come from the
#     CLOUDFLARE_API_TOKEN environment variable, never from files.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Credentials come from the environment, never from tfvars:
#   export CLOUDFLARE_API_TOKEN=...
# The provider, wrangler (D1 schema step), and the R2 cleanup script all read it.
provider "cloudflare" {}
