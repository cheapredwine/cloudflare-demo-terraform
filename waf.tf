# WAF Ruleset: Dynamic Redirects
# Uses cloudflare_ruleset (modern approach, replaces legacy Page Rules)

resource "cloudflare_ruleset" "redirects" {
  zone_id = data.cloudflare_zone.main.id
  name    = "Demo redirect rules"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  # Rule 1: Simple path redirect
  # /old-shop -> /api/products
  rules {
    enabled     = true
    description = "Redirect old shop path to products API"
    expression  = "(http.request.uri.path eq \"/old-shop\")"
    action      = "redirect"

    action_parameters {
      from_value {
        status_code = 301
        target_url {
          value = "https://api.${var.zone_name}/api/products"
        }
        preserve_query_string = false
      }
    }
  }

  # Rule 2: Redirect HTTP to HTTPS
  # Uncomment to enforce TLS on all requests
  # rules {
  #   enabled     = true
  #   description = "Force HTTPS"
  #   expression  = "(not ssl)"
  #   action      = "redirect"
  #
  #   action_parameters {
  #     from_value {
  #       status_code = 301
  #       target_url {
  #         expression = "concat(\"https://\", http.host, http.request.uri.path)"
  #       }
  #       preserve_query_string = true
  #     }
  #   }
  # }
}
