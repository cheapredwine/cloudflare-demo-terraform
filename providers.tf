# Providers
#
# Terraform concepts:
#   - `required_version` sets the oldest Terraform CLI that works (1.11 is the
#     first with `override_during`, which the tests use).
#   - `required_providers` pins the Cloudflare provider. `~> 5.28` means 5.28
#     or any later 5.x (the version this was checked against), but never 6.0.
#     `.terraform.lock.hcl` records the exact version `terraform init` chose,
#     so commit it; `terraform init -upgrade` moves it forward. It holds
#     checksums per OS; after an upgrade, record them for everyone (CI runs
#     on Linux and refuses to change the lock file):
#       terraform providers lock -platform=linux_amd64 -platform=linux_arm64 \
#         -platform=darwin_amd64 -platform=darwin_arm64 -platform=windows_amd64
#   - The provider block is empty on purpose: credentials come from the
#     CLOUDFLARE_API_TOKEN environment variable, never from files.

terraform {
  required_version = ">= 1.11.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.28"
    }
  }
}

# Credentials come from the environment, never from tfvars:
#   export CLOUDFLARE_API_TOKEN=...
# The provider, wrangler (D1 schema step), and the R2 cleanup script all read it.
provider "cloudflare" {}
