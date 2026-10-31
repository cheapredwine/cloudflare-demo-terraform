variable "cloudflare_api_token" {
  description = "Cloudflare API token (see README for the required permissions)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.cloudflare_api_token)) >= 20 && !startswith(var.cloudflare_api_token, "your-")
    error_message = "cloudflare_api_token looks empty, truncated, or still the example placeholder."
  }
}

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
  description = "Origin IPv4 for the root DNS record and the load balancer pool. Default is a documentation address (RFC 5737); set a real origin to see healthy LB checks."
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
