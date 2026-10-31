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

# The OWASP 949110 anomaly-score exception must be live in the managed ruleset,
# using the official published IDs (rule ends in ...843b323c, OWASP ruleset
# 4814384a..., CF Managed Ruleset efb7b8c9...). Docs: /terraform/
# additional-configurations/waf-managed-rulesets/
grep -q '6179ae15870a4bb7b2d480d4843b323c' waf.tf ||
	fail "managed ruleset lost the OWASP 949110 rule ID (6179ae...843b323c)"
grep -q '4814384a9e5d4991b9815dcfc25d2f1f' waf.tf ||
	fail "managed ruleset lost the OWASP Core Ruleset ID (4814384a...)"
grep -q 'efb7b8c949ac4650a09736fc376e9aee' waf.tf ||
	fail "managed ruleset lost the Cloudflare Managed Ruleset ID (efb7b8c9...)"

echo "config-checks: all guards passed"
