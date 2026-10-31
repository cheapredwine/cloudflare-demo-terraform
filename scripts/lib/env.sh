#!/usr/bin/env bash
# Sourced by the demo scripts. Loads credentials into the environment from the
# gitignored secrets/ store, unless they are already set. Never echoes values.
# Each file holds one value; only the trailing line ending is removed, so a
# password may contain spaces. Keep in sync with env.ps1.
#   secrets/cloudflare_api_token -> CLOUDFLARE_API_TOKEN   (provider, wrangler, R2 cleanup)
#   secrets/admin_password       -> TF_VAR_admin_password  (admin panel Worker secret)

# $(...) drops trailing newlines; the parameter expansion drops a trailing CR
# left by files saved on Windows.
_read_secret() {
	local value
	value=$(cat "$1")
	printf '%s' "${value%$'\r'}"
}

_secrets_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/secrets"

if [ -z "${CLOUDFLARE_API_TOKEN:-}" ] && [ -f "$_secrets_dir/cloudflare_api_token" ]; then
	CLOUDFLARE_API_TOKEN=$(_read_secret "$_secrets_dir/cloudflare_api_token")
	export CLOUDFLARE_API_TOKEN
fi

if [ -z "${TF_VAR_admin_password:-}" ] && [ -f "$_secrets_dir/admin_password" ]; then
	TF_VAR_admin_password=$(_read_secret "$_secrets_dir/admin_password")
	export TF_VAR_admin_password
fi

unset _secrets_dir

# Writes a curl config file holding the admin panel's Basic-auth login and
# prints its path; the caller passes it with `curl -K <file>` and deletes it.
# (curl -u admin:<password> would show the password in `ps` to every local
# user.) mktemp creates the file readable by its owner only.
admin_curl_config() {
	local file escaped
	file=$(mktemp)
	escaped=${TF_VAR_admin_password//\\/\\\\}
	escaped=${escaped//\"/\\\"}
	printf 'user = "admin:%s"\n' "$escaped" >"$file"
	printf '%s' "$file"
}
unset -f _read_secret
