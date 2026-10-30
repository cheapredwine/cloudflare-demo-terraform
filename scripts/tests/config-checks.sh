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

# The OWASP 949110 override guidance must stay in the managed ruleset comment
# (rule id ends in ...843b323c; resolve the full 32-hex ID via the API).
grep -q '843b323c' waf.tf ||
	fail "managed ruleset lost the 949110 override guidance (843b323c tail)"

echo "config-checks: all guards passed"
