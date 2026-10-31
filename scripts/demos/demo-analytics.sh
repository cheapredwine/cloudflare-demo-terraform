#!/bin/bash
# Workers Analytics traffic generator
# Generates realistic traffic so Cloudflare Analytics dashboard shows live data
# Run this during a demo, then pull up the dashboard to show real-time metrics

set -euo pipefail

# Load credentials from the gitignored secrets/ store (see secrets/README.md).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/../lib/env.sh"

ZONE_NAME=""
if [ -f "terraform.tfvars" ]; then
	ZONE_NAME=$(sed -n 's/^zone_name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' terraform.tfvars)
fi

if [ -z "$ZONE_NAME" ]; then
	echo "ERROR: zone_name not found in terraform.tfvars"
	exit 1
fi

API="https://api.$ZONE_NAME"
ADMIN="https://admin.$ZONE_NAME"

# Admin password comes from TF_VAR_admin_password (filled from
# secrets/admin_password by scripts/lib/env.sh).
if [ -z "${TF_VAR_admin_password:-}" ]; then
	echo "ERROR: put the admin password in secrets/admin_password (or set TF_VAR_admin_password)"
	exit 1
fi
ADMIN_AUTH=$(admin_curl_config)
trap 'rm -f "$ADMIN_AUTH"' EXIT
ROUNDS=${1:-3}

echo "================================================"
echo " Workers Analytics Traffic Generator"
echo " Zone: $ZONE_NAME"
echo "================================================"
echo ""
echo "This script generates traffic across all workers."
echo "Open the Cloudflare dashboard to see live metrics:"
echo ""
# ?to=/:account/... links let the dashboard pick the account, so the
# account ID never appears on screen.
echo "  Workers & Pages:"
echo "  https://dash.cloudflare.com/?to=/:account/workers-and-pages"
echo ""
echo "  Per-worker (API Gateway):"
echo "  https://dash.cloudflare.com/?to=/:account/workers/services/view/demo-api-gateway/production"
echo ""
echo "  Per-worker (Products API):"
echo "  https://dash.cloudflare.com/?to=/:account/workers/services/view/demo-products-api/production"
echo ""
echo "  Zone Analytics:"
echo "  https://dash.cloudflare.com/?to=/:account/$ZONE_NAME/analytics/traffic"
echo ""
echo "Rounds are 10 s apart: waf.tf rate-limits /api/* to 50 requests per"
echo "10 s per IP, and blocked requests wouldn't reach the Workers."
echo ""
echo "Generating traffic... (${ROUNDS} rounds)"
echo ""

q() { curl -s -o /dev/null "$@"; }

for i in $(seq 1 "$ROUNDS"); do
	[ "$i" -gt 1 ] && sleep 10
	echo "Round $i/$ROUNDS"

	# A real product ID (IDs aren't reused, so after a reset 1 may not exist)
	PRODUCT_ID=$(curl -s "$API/api/products" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2 || true)
	PRODUCT_ID=${PRODUCT_ID:-1}

	# Auth flow
	printf "  Auth... "
	SESSION=$(curl -s -X POST "$API/api/auth/login" \
		-H "Content-Type: application/json" \
		-d '{"email":"demo@example.com","password":"demo"}' |
		grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
	q "$API/api/auth/me" -H "Authorization: Bearer $SESSION"
	q "$API/api/auth/me" -H "Authorization: Bearer invalid"
	echo "done"

	# Products — mix of hits and misses
	printf "  Products (MISS then HITs)... "
	q -X POST "$API/api/products" -H "Content-Type: application/json" \
		-d "{\"name\":\"Demo Product $i\",\"price\":$((i * 10)).99,\"stock\":$((i * 5))}"
	q "$API/api/products"
	q "$API/api/products"
	q "$API/api/products"
	q "$API/api/products/$PRODUCT_ID"
	q "$API/api/products/999999" # 404
	echo "done"

	# Orders
	printf "  Orders... "
	q -X POST "$API/api/orders" \
		-H "Content-Type: application/json" \
		-d "{\"customer_id\":\"demo-$i\",\"items\":[{\"product_id\":$PRODUCT_ID,\"quantity\":1}]}"
	q -X POST "$API/api/orders" \
		-H "Content-Type: application/json" \
		-d '{"customer_id":"missing-items"}'
	echo "done"

	# Upload
	printf "  Upload... "
	TMPFILE=$(mktemp /tmp/demo-upload.XXXXXX.txt)
	echo "demo file $i $(date)" >"$TMPFILE"
	q -X POST "$API/api/upload" -F "file=@$TMPFILE"
	q -X POST "$API/api/upload"
	rm "$TMPFILE"
	echo "done"

	# 404s (shows error rate in analytics)
	printf "  404s... "
	q "$API/api/nonexistent"
	q "$API/api/nonexistent2"
	echo "done"

	# Admin panel
	printf "  Admin... "
	q -K "$ADMIN_AUTH" "$ADMIN/"
	q -K "$ADMIN_AUTH" "$ADMIN/api/stats"
	q -K "$ADMIN_AUTH" "$ADMIN/api/products"
	q -K "$ADMIN_AUTH" "$ADMIN/api/orders"
	q -u "admin:wrongpassword" "$ADMIN/"
	echo "done"

	echo ""
done

echo "================================================"
echo " Traffic generation complete"
echo " ~$((ROUNDS * 25)) requests sent across all workers"
echo "================================================"
echo ""
echo "Dashboard links (may take ~1 min to show data):"
echo "  Workers: https://dash.cloudflare.com/?to=/:account/workers-and-pages"
echo "  Zone:    https://dash.cloudflare.com/?to=/:account/$ZONE_NAME/analytics/traffic"
echo ""
