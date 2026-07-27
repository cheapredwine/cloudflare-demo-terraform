#!/bin/bash
# Workers Analytics traffic generator
# Generates realistic traffic so Cloudflare Analytics dashboard shows live data
# Run this during a demo, then pull up the dashboard to show real-time metrics

set -euo pipefail

ZONE_NAME=""
ACCOUNT_ID=""
if [ -f "terraform.tfvars" ]; then
    ZONE_NAME=$(grep 'zone_name' terraform.tfvars | cut -d'"' -f2)
    ACCOUNT_ID=$(grep 'account_id' terraform.tfvars | cut -d'"' -f2)
fi

if [ -z "$ZONE_NAME" ]; then
    echo "ERROR: zone_name not found in terraform.tfvars"
    exit 1
fi

API="https://api.$ZONE_NAME"
ADMIN="https://admin.$ZONE_NAME"
ROUNDS=${1:-3}

echo "================================================"
echo " Workers Analytics Traffic Generator"
echo " Zone: $ZONE_NAME"
echo "================================================"
echo ""
echo "This script generates traffic across all workers."
echo "Open the Cloudflare dashboard to see live metrics:"
echo ""
echo "  Workers Analytics:"
echo "  https://dash.cloudflare.com/$ACCOUNT_ID/workers/overview"
echo ""
echo "  Per-worker (API Gateway):"
echo "  https://dash.cloudflare.com/$ACCOUNT_ID/workers/services/view/demo-api-gateway/production/metrics"
echo ""
echo "  Per-worker (Products API):"
echo "  https://dash.cloudflare.com/$ACCOUNT_ID/workers/services/view/demo-products-api/production/metrics"
echo ""
echo "  Zone Analytics:"
echo "  https://dash.cloudflare.com/$ACCOUNT_ID/$ZONE_NAME/analytics/traffic"
echo ""
echo "Generating traffic... (${ROUNDS} rounds)"
echo ""

q() { curl -s -o /dev/null "$@"; }

for i in $(seq 1 $ROUNDS); do
    echo "Round $i/$ROUNDS"

    # Auth flow
    printf "  Auth... "
    SESSION=$(curl -s -X POST "$API/api/auth/login" \
        -H "Content-Type: application/json" \
        -d '{"email":"demo@example.com","password":"demo"}' \
        | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
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
    q "$API/api/products/1"
    q "$API/api/products/2"
    echo "done"

    # Orders
    printf "  Orders... "
    q -X POST "$API/api/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customer_id\":\"demo-$i\",\"items\":[{\"product_id\":1,\"quantity\":1,\"unit_price\":24.99}],\"total\":24.99}"
    q -X POST "$API/api/orders" \
        -H "Content-Type: application/json" \
        -d '{"customer_id":"missing-items"}'
    echo "done"

    # Upload
    printf "  Upload... "
    TMPFILE=$(mktemp /tmp/demo-upload.XXXXXX.txt)
    echo "demo file $i $(date)" > "$TMPFILE"
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
    q -u "admin:demo123" "$ADMIN/"
    q -u "admin:demo123" "$ADMIN/api/stats"
    q -u "admin:demo123" "$ADMIN/api/products"
    q -u "admin:demo123" "$ADMIN/api/orders"
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
echo "  Workers: https://dash.cloudflare.com/$ACCOUNT_ID/workers/overview"
echo "  Zone:    https://dash.cloudflare.com/$ACCOUNT_ID/$ZONE_NAME/analytics/traffic"
echo ""
