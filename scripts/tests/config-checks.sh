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
# say `command = plan`. terraform test reads *.tftest.hcl in the root AND in
# tests/, so check both.
shopt -s nullglob
for t in ./*.tftest.hcl tests/*.tftest.hcl; do
	runs=$(grep -cE '^\s*run\s+"' "$t" || true)
	plans=$(grep -cE '^\s*command\s*=\s*plan\s*$' "$t" || true)
	[ "$runs" -eq "$plans" ] ||
		fail "$t: $runs run blocks but only $plans say command = plan (the default is apply)"
done
shopt -u nullglob

# The provider cannot move cloudflare_workers_script -> cloudflare_worker
# (plan fails: "Unable to Move Resource State"); see upgrade-from-v4.tf.
if grep -nE '^\s*from\s*=\s*cloudflare_workers_script\.' ./*.tf; then
	fail "moved block from cloudflare_workers_script is unsupported by the provider (use removed + import)"
fi

# The Rules language regex operator (`matches`, or its short form `~`) needs
# a Business or Enterprise plan. Use starts_with(), contains, eq or wildcard.
if grep -nE '^\s*expression\s*=.*[[:space:]](matches|~)[[:space:]]' ./*.tf; then
	fail "Rules expression uses 'matches' / '~' (Business/Enterprise only)"
fi

# Every ruleset rule needs a `ref` (stable rule IDs across edits): one
# uncommented `ref =` per uncommented `action =`, across all .tf files.
refs=$(cat ./*.tf | grep -cE '^\s*ref\s*=' || true)
actions=$(cat ./*.tf | grep -cE '^\s*action\s*=' || true)
[ "$refs" -eq "$actions" ] ||
	fail "$actions ruleset rules but $refs refs: every rule needs a ref"

# Every resource address that scripts, the Makefile or the README mention
# must exist in the config (a demo once targeted cloudflare_workers_script
# .products_api after that resource was renamed). Address-shaped words in the
# README that are v4 names (upgrade docs) are listed in V4_NAMES.
V4_NAMES=' cloudflare_record.root cloudflare_record.api cloudflare_record.admin '
while read -r addr; do
	case "$V4_NAMES" in *" $addr "*) continue ;; esac
	type=${addr%%.*}
	name=${addr#*.}
	grep -qE "^(resource|data) \"$type\" \"$name\"" ./*.tf ||
		fail "scripts or docs reference $addr, which no .tf file declares"
done < <(grep -hoE '(cloudflare_[a-z0-9_]+|terraform_data)\.[a-z_][a-z0-9_]*' \
	scripts/demos/* scripts/lifecycle/* scripts/tests/test.* Makefile README.md |
	grep -vE '\.(id|name|queue_id|queue_name|status|filter)$' | sort -u)

# The README's minimum Terraform version must match providers.tf.
floor=$(sed -nE 's/^ *required_version *= *">= *([0-9]+\.[0-9]+).*/\1/p' providers.tf)
grep -qF "Terraform >= $floor" README.md ||
	fail "README doesn't say 'Terraform >= $floor' (providers.tf required_version)"

# admin_allowlist_cidr must stay required: a default that isn't the user's
# own IP makes the WAF challenge every admin request, scripts included.
if awk '/^variable "admin_allowlist_cidr"/,/^}/' variables.tf | grep -qE '^\s*default\s*='; then
	fail "admin_allowlist_cidr must not have a default (users must set their own IP)"
fi

# No hardcoded admin credentials anywhere in the Worker code.
if grep -rn 'demo123' workers/; then
	fail "hardcoded admin password found in workers/ (use the ADMIN_PASSWORD secret)"
fi

# The admin page builds HTML from API data that anyone can write. Every
# value interpolated into the page script (\${...}) must go through esc().
if grep -nE '\\\$\{' workers/*.js | grep -vE '\\\$\{esc\('; then
	fail "workers/: page-script interpolation without esc() (stored XSS risk)"
fi

# The admin password reaches curl through a 0600 config file (-K), never on
# the command line (-u admin:$PASSWORD shows up in `ps`).
if grep -rnE --exclude=config-checks.sh -- '-u "?admin:\$' scripts/; then
	fail "scripts/: pass the admin password with -K \"\$ADMIN_AUTH\", not -u"
fi

# Twins: every user-facing .sh script has a .ps1 with the same actions.
python3 - <<'PY' || fail ".sh / .ps1 twins differ (see above)"
import pathlib, re, sys
ok = True
for sh in sorted(pathlib.Path("scripts").glob("*/*.sh")):
    if sh.parent.name == "lib" or sh.name == "config-checks.sh":
        continue
    ps1 = sh.with_suffix(".ps1")
    if not ps1.exists():
        print(f"{sh} has no {ps1.name} twin", file=sys.stderr); ok = False; continue
    sh_actions = set(re.findall(r'^"?([a-z][a-z-]*)"?\)$', sh.read_text(), re.M))
    ps_actions = set(re.findall(r'^\s+"([a-z][a-z-]*)" \{', ps1.read_text(), re.M)) - {"help"}
    if sh_actions != ps_actions:
        print(f"{sh.name} actions {sorted(sh_actions)} != {ps1.name} actions {sorted(ps_actions)}", file=sys.stderr)
        ok = False
# `all` must run every demo (tf-all once skipped two).
demo = pathlib.Path("scripts/demos/terraform-demo.sh").read_text()
run_all = demo[demo.index("run_all() {"):].split("\n}\n", 1)[0]
for action in re.findall(r'^([a-z][a-z-]*)\)$', demo, re.M):
    if action != "all" and "demo_" + action.replace("-", "_") not in run_all:
        print(f"terraform-demo.sh: run_all doesn't call demo_{action.replace('-', '_')}", file=sys.stderr)
        ok = False
demo_ps = pathlib.Path("scripts/demos/terraform-demo.ps1").read_text()
run_all_ps = demo_ps[demo_ps.index("function Run-All {"):].split("\n}\n", 1)[0]
for action in re.findall(r'^\s+"([a-z][a-z-]*)" \{ Check-Prereqs', demo_ps, re.M):
    fn = "Demo-" + "".join(w.capitalize() for w in action.split("-"))
    if fn not in run_all_ps:
        print(f"terraform-demo.ps1: Run-All doesn't call {fn}", file=sys.stderr)
        ok = False
sys.exit(0 if ok else 1)
PY

# Every test name the README's "Find your topic" table points readers to
# must be a real `run` block.
python3 - <<'PY' || fail "README names a test that doesn't exist"
import re, sys
runs = set(re.findall(r'^run "([^"]+)"', open("tests/main.tftest.hcl").read(), re.M))
named = set()
for line in open("README.md"):
    if line.startswith("| **"):
        named |= set(re.findall(r"`([a-z0-9_]+)`", line.rstrip().rstrip("|").rsplit("|", 1)[-1]))
missing = sorted(named - runs)
if missing or not named:
    print("missing run blocks:", missing or "(no test names found)", file=sys.stderr)
    sys.exit(1)
PY

# Workers can't read repo files, so the admin panel's POST /setup embeds a
# copy of db/schema.sql. Both copies must define the same tables and indexes.
python3 - <<'PY' || fail "db/schema.sql and workers/admin-panel.js define different schemas"
import re, sys
def schema(text):
    out = {}
    for name, body in re.findall(r"CREATE TABLE IF NOT EXISTS (\w+) \((.*?)\n\s*\)", text, re.S):
        out["table " + name] = re.sub(r"\s*\(", "(", " ".join(body.split()))
    for stmt in re.findall(r"CREATE (?:UNIQUE )?INDEX[^;`]*", text):
        out[" ".join(stmt.split())] = ""
    return out
sql = schema(open("db/schema.sql").read())
js = schema(open("workers/admin-panel.js").read())
if not sql or sql != js:
    print("db/schema.sql:", sql, "\nadmin-panel.js:", js, file=sys.stderr)
    sys.exit(1)
PY

# Every binding a Worker version declares must be read by that Worker's code
# (`env.<NAME>`). workers.tf promises that one block shows everything a
# Worker gets; a binding the code never touches makes that promise false,
# and it once hid an unused D1 binding on the gateway for months.
python3 - <<'PY' || fail "workers.tf declares a binding its Worker code never reads (see above)"
import pathlib, re, sys
ok = True
tf = pathlib.Path("workers.tf").read_text()
versions = re.findall(r'resource "cloudflare_worker_version" "(\w+)" \{(.*?)\n\}', tf, re.S)
if not versions:
    print("no cloudflare_worker_version blocks found in workers.tf", file=sys.stderr); sys.exit(1)
def strip_comments(text, line_marker):
    # Whole-line comments and /* */ blocks only: a trailing `//` may be part
    # of a URL such as `https://api.${env.ZONE_NAME}`.
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(l for l in text.splitlines() if not l.lstrip().startswith(line_marker))
for name, body in versions:
    body = strip_comments(body, "#")
    module = re.search(r'content_file\s*=\s*"\$\{path\.module\}/(workers/[\w.-]+\.js)"', body)
    if not module:
        print(f"{name}: no content_file under workers/", file=sys.stderr); ok = False; continue
    code = strip_comments(pathlib.Path(module.group(1)).read_text(), "//")
    blist = re.search(r"bindings\s*=\s*\[(.*?)\n\s*\]", body, re.S)
    if not blist:
        print(f"{name}: no bindings list found", file=sys.stderr); ok = False; continue
    # One `{ ... }` per binding, keys in any order; every element must name itself.
    elements = re.findall(r"\{[^{}]*\}", blist.group(1), re.S)
    bindings = [m.group(1) for e in elements if (m := re.search(r'\bname\s*=\s*"(\w+)"', e))]
    if len(bindings) != len(elements):
        print(f"{name}: {len(elements)} bindings but only {len(bindings)} have a name", file=sys.stderr); ok = False; continue
    for b in bindings:
        if not re.search(r'\benv\.' + re.escape(b) + r'\b', code):
            print(f"{name}: binding {b} is never read as env.{b} in {module.group(1)}", file=sys.stderr)
            ok = False
sys.exit(0 if ok else 1)
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
