#!/usr/bin/env bash
# Config-content guards that terraform test cannot express:
# things that live in comments or must simply not disappear.
# Run before `terraform test` (wired into `make verify`).

set -euo pipefail
cd "$(dirname "$0")/../.."

fail() {
	echo "FAIL: $1" >&2
	exit 1
}

# The Rule 2 HTTPS-redirect demo toggle (restored verbatim from the original
# waf.tf, commit 81cc01b) must stay in the redirects ruleset as a comment.
grep -q 'Force HTTPS' waf.tf ||
	fail "redirects ruleset lost the commented Rule 2 (Force HTTPS) toggle"
grep -q 'concat(\\"https://' waf.tf ||
	fail "Rule 2 lost its https redirect target_url expression"

# Tests must stay on plan: a mocked apply still runs the local-exec
# provisioners (wrangler / empty-r2.py), which call the real Cloudflare API.
# A run block with no `command` defaults to apply, so every run block must
# say `command = plan` explicitly.
for t in tests/*.tftest.hcl; do
	runs=$(grep -cE '^run "' "$t")
	plans=$(grep -cE '^\s*command\s*=\s*plan\s*$' "$t")
	[ "$runs" -eq "$plans" ] ||
		fail "$t: $runs run blocks but only $plans say command = plan (the default is apply)"
done

# The provider cannot move cloudflare_workers_script -> cloudflare_worker
# (plan fails: "Unable to Move Resource State"); see upgrade-from-v4.tf.
if grep -nE '^\s*from\s*=\s*cloudflare_workers_script\.' ./*.tf; then
	fail "moved block from cloudflare_workers_script is unsupported by the provider (use removed + import)"
fi

# The Rules language `matches` (regex) operator needs a Business or Enterprise
# plan. Use starts_with(), contains, eq or wildcard so the demo runs on any plan.
if grep -nE '^[^#]*[[:space:]]matches[[:space:]]' ./*.tf; then
	fail "Rules expression uses 'matches' (Business/Enterprise only)"
fi

# Every resource address a script runs terraform against must exist in the
# config (a demo once targeted cloudflare_workers_script.products_api after
# that resource was renamed).
while read -r addr; do
	type=${addr%%.*}
	name=${addr#*.}
	grep -qE "^(resource|data) \"$type\" \"$name\"" ./*.tf ||
		fail "scripts reference $addr, which no .tf file declares"
done < <(grep -rhoE 'cloudflare_[a-z0-9_]+\.[a-z0-9_]+' scripts/demos scripts/lifecycle scripts/tests/test.* | sort -u)

# No hardcoded admin credentials anywhere in the Worker code.
if grep -rn 'demo123' workers/; then
	fail "hardcoded admin password found in workers/ (use the ADMIN_PASSWORD secret)"
fi

# Workers can't read repo files, so the admin panel's POST /setup embeds a
# copy of db/schema.sql. The two copies must define the same tables.
python3 - <<'PY' || fail "db/schema.sql and workers/admin-panel.js define different tables"
import re, sys
def tables(text):
    out = {}
    for name, body in re.findall(r"CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\n\s*\)", text, re.S):
        out[name] = re.sub(r"\s*\(", "(", " ".join(body.split()))
    return out
sql = tables(open("db/schema.sql").read())
js = tables(open("workers/admin-panel.js").read())
if not sql or sql != js:
    print("db/schema.sql:", sql, "\nadmin-panel.js:", js, file=sys.stderr)
    sys.exit(1)
PY

# The secrets loader must load from secrets/ files and never override a value
# already set in the environment. Exercised in a scratch copy of the layout.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/scripts/lib" "$scratch/secrets"
cp scripts/lib/env.sh scripts/lib/env.ps1 "$scratch/scripts/lib/"
printf 'file-token\n' >"$scratch/secrets/cloudflare_api_token"
# Spaces inside the value must survive; the Windows line ending must not.
printf 'file pass word\r\n' >"$scratch/secrets/admin_password"
# printenv runs as a child process, so this also proves the values are EXPORTED
# (terraform and wrangler only see exported variables).
# shellcheck disable=SC2016 # single quotes: the inner bash expands these
loaded=$(env -u CLOUDFLARE_API_TOKEN -u TF_VAR_admin_password bash -c \
	'source "$1/scripts/lib/env.sh"; echo "$(printenv CLOUDFLARE_API_TOKEN)/$(printenv TF_VAR_admin_password)"' _ "$scratch")
[ "$loaded" = "file-token/file pass word" ] ||
	fail "scripts/lib/env.sh did not load secrets/ files"
# shellcheck disable=SC2016
kept=$(CLOUDFLARE_API_TOKEN=from-env bash -c \
	'source "$1/scripts/lib/env.sh"; printenv CLOUDFLARE_API_TOKEN' _ "$scratch")
[ "$kept" = "from-env" ] ||
	fail "scripts/lib/env.sh overrode an already-set CLOUDFLARE_API_TOKEN"

# admin_curl_config must escape the characters that are special inside a
# quoted curl config value (" and \), and keep spaces. Test password only.
# shellcheck disable=SC2016
auth_value=$(TF_VAR_admin_password='a "b" \c d' bash -c \
	'source "$1/scripts/lib/env.sh"; f=$(admin_curl_config); cat "$f"; rm -f "$f"' _ "$scratch")
[ "$auth_value" = 'user = "admin:a \"b\" \\c d"' ] ||
	fail "admin_curl_config wrote a badly escaped curl config: $auth_value"

# env.ps1 must read the same files the same way (skipped if pwsh is absent).
if command -v pwsh >/dev/null; then
	# shellcheck disable=SC2016
	ps_loaded=$(env -u CLOUDFLARE_API_TOKEN -u TF_VAR_admin_password SCRATCH="$scratch" pwsh -NoProfile -Command \
		'. (Join-Path $env:SCRATCH "scripts/lib/env.ps1"); "$env:CLOUDFLARE_API_TOKEN/$env:TF_VAR_admin_password"')
	[ "$ps_loaded" = "$loaded" ] ||
		fail "scripts/lib/env.ps1 loads secrets differently from env.sh"
fi

echo "config-checks: all guards passed"
