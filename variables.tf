# Inputs
#
# Terraform concepts:
#   - `variable` blocks are the module's inputs. Set them in terraform.tfvars,
#     with -var on the command line, or as TF_VAR_<name> env vars.
#   - `default` makes an input optional.
#   - `validation` rejects bad input at plan time with a clear message.
#   - `sensitive = true` hides the value in plan/apply output. (It is still
#     stored in state, so protect your state file.)

variable "account_id" {
  description = "Cloudflare account ID (32 hex characters)"
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character lowercase hex Cloudflare account ID."
  }
}

variable "zone_name" {
  description = "Primary zone for the demo (must already exist in the account)"
  type        = string
  default     = "demo-platform.example"

  validation {
    condition     = can(regex("^([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}$", var.zone_name))
    error_message = "zone_name must be a lowercase apex domain such as example.com."
  }
}

variable "origin_ipv4" {
  description = "Primary origin IPv4 (root DNS record + primary LB pool). Default is a documentation address (RFC 5737); set a real origin to see healthy LB checks."
  type        = string
  default     = "203.0.113.10"

  validation {
    condition     = can(cidrhost("${var.origin_ipv4}/32", 0))
    error_message = "origin_ipv4 must be a valid IPv4 address."
  }
}

variable "admin_allowlist_cidr" {
  description = "Corporate CIDR allowed to reach /admin without a managed challenge"
  type        = string
  default     = "203.0.113.0/24"

  validation {
    condition     = can(cidrnetmask(var.admin_allowlist_cidr))
    error_message = "admin_allowlist_cidr must be an IPv4 CIDR such as 198.51.100.0/24."
  }
}

variable "secondary_origin_ipv4" {
  description = "Secondary origin IPv4 for the passive failover LB pool (RFC 5737 default)"
  type        = string
  default     = "203.0.113.20"

  validation {
    condition     = can(cidrhost("${var.secondary_origin_ipv4}/32", 0))
    error_message = "secondary_origin_ipv4 must be a valid IPv4 address."
  }
}

variable "primary_origin_enabled" {
  description = "Set false to drain the primary pool and demo load balancer failover"
  type        = bool
  default     = true
}

variable "admin_password" {
  description = "Admin panel Basic-auth password (user: admin). Stored as a Worker secret; prefer TF_VAR_admin_password over tfvars."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.admin_password) >= 12
    error_message = "admin_password must be at least 12 characters."
  }
}
