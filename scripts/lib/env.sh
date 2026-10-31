#!/usr/bin/env bash
# Sourced by the demo scripts. Loads credentials into the environment from the
# gitignored secrets/ store, unless they are already set. Never echoes values.
#   secrets/cloudflare_api_token -> CLOUDFLARE_API_TOKEN   (provider, wrangler, R2 cleanup)
#   secrets/admin_password       -> TF_VAR_admin_password  (admin panel Worker secret)

_secrets_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/secrets"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -f "$_secrets_dir/cloudflare_api_token" ]; then
	CLOUDFLARE_API_TOKEN=$(tr -d '[:space:]' <"$_secrets_dir/cloudflare_api_token")
	export CLOUDFLARE_API_TOKEN
fi

if [ -z "${TF_VAR_admin_password:-}" ] && [ -f "$_secrets_dir/admin_password" ]; then
	TF_VAR_admin_password=$(tr -d '[:space:]' <"$_secrets_dir/admin_password")
	export TF_VAR_admin_password
fi

unset _secrets_dir
