#!/bin/bash
# Production integration tests for the Cloudflare Demo Platform

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ZONE_NAME=""
PASS=0
FAIL=0
ERRORS=()

if [ -f "terraform.tfvars" ]; then
    ZONE_NAME=$(grep 'zone_name' terraform.tfvars | cut -d'"' -f2)
fi

if [ -z "$ZONE_NAME" ]; then
    echo "ERROR: zone_name not found in terraform.tfvars"
    exit 1
fi

API="https://api.$ZONE_NAME"
ADMIN="https://admin.$ZONE_NAME"

echo "================================================"
echo " Cloudflare Demo Platform - Integration Tests"
echo " Zone: $ZONE_NAME"
echo "================================================"
echo ""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

assert_status() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        pass "$label (HTTP $actual)"
    else
        fail "$label (expected HTTP $expected, got HTTP $actual)"
    fi
}

assert_contains() {
    local label="$1"
    local needle="$2"
    local haystack="$3"
    if echo "$haystack" | grep -q "$needle"; then
        pass "$label (contains '$needle')"
    else
        fail "$label (expected '$needle' in response)"
    fi
}

RESP_BODY=$(mktemp)
RESP_STATUS=$(mktemp)
trap "rm -f $RESP_BODY $RESP_STATUS" EXIT

http_status() {
    curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$@"
}

http_body() {
    curl -s --max-time 15 "$@"
}

wait_for_order_in_admin() {
    local order_id="$1"
    local max_attempts=15
    local attempt=1

    while [ "$attempt" -le "$max_attempts" ]; do
        local body
        body=$(http_body -u "admin:demo123" "$ADMIN/api/orders")
        if echo "$body" | grep -q "$order_id"; then
            return 0
        fi

        sleep 2
        attempt=$((attempt + 1))
    done

    return 1
}

# Writes body to $RESP_BODY, status to $RESP_STATUS
req() {
    curl -s -w "%{http_code}" --max-time 15 -o "$RESP_BODY" "$@" > "$RESP_STATUS"
}

get_status() { cat "$RESP_STATUS"; }
get_body()   { cat "$RESP_BODY"; }

# ---------------------------------------------------------------------------
# 1. API Gateway
# ---------------------------------------------------------------------------
echo "[ 1 ] API Gateway"

status=$(http_status "$API/api/nonexistent")
assert_status "unknown route returns 404" 404 "$status"

status=$(http_status -X OPTIONS "$API/api/products" \
    -H "Origin: https://example.com" \
    -H "Access-Control-Request-Method: GET")
assert_status "OPTIONS preflight returns 200" 200 "$status"

body=$(http_body "$API/api/nonexistent")
assert_contains "404 body returns error message" '"error"' "$body"

echo ""

# ---------------------------------------------------------------------------
# 2. Auth
# ---------------------------------------------------------------------------
echo "[ 2 ] Auth"

# Login
req -X POST "$API/api/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"email":"test@example.com","password":"anypassword"}'
assert_status "login returns 200" 200 "$(get_status)"
assert_contains "login returns session_id" "session_id" "$(get_body)"

SESSION_ID=$(get_body | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

# /me with valid token
req "$API/api/auth/me" -H "Authorization: Bearer $SESSION_ID"
assert_status "/me with valid token returns 200" 200 "$(get_status)"
assert_contains "/me returns email" "test@example.com" "$(get_body)"

# /me with invalid token
status=$(http_status "$API/api/auth/me" -H "Authorization: Bearer invalid-token")
assert_status "/me with invalid token returns 401" 401 "$status"

# /me with no token
status=$(http_status "$API/api/auth/me")
assert_status "/me with no token returns 401" 401 "$status"

echo ""

# ---------------------------------------------------------------------------
# 3. Products
# ---------------------------------------------------------------------------
echo "[ 3 ] Products"

# Seed
req -X POST "$API/api/products/seed"
assert_status "seed returns 200" 200 "$(get_status)"
assert_contains "seed confirms products created" "Seeded" "$(get_body)"

# List
req "$API/api/products"
assert_status "list products returns 200" 200 "$(get_status)"
assert_contains "list returns products array" "products" "$(get_body)"
assert_contains "list includes seeded product" "Coffee" "$(get_body)"

# Cache header
LIST_HEADERS=$(curl -sv --max-time 15 "$API/api/products" 2>&1)
assert_contains "list response includes X-Products-Cache header" "x-products-cache" "$LIST_HEADERS"

# Create
req -X POST "$API/api/products" \
    -H "Content-Type: application/json" \
    -d '{"name":"Test Widget","description":"A test product","price":9.99,"category":"test","stock":5}'
assert_status "create product returns 201" 201 "$(get_status)"
assert_contains "create returns product id" '"id"' "$(get_body)"

PRODUCT_ID=$(get_body | grep -o '"id":[0-9]*' | cut -d: -f2)

# Get single
req "$API/api/products/$PRODUCT_ID"
assert_status "get single product returns 200" 200 "$(get_status)"
assert_contains "get single returns correct product" "Test Widget" "$(get_body)"

# Update
req -X PUT "$API/api/products/$PRODUCT_ID" \
    -H "Content-Type: application/json" \
    -d '{"price":19.99,"stock":10}'
assert_status "update product returns 200" 200 "$(get_status)"
assert_contains "update confirms success" "updated" "$(get_body)"

# Verify update
req "$API/api/products/$PRODUCT_ID"
assert_contains "updated price reflected" "19.99" "$(get_body)"

# Delete
req -X DELETE "$API/api/products/$PRODUCT_ID"
assert_status "delete product returns 200" 200 "$(get_status)"
assert_contains "delete confirms success" "deleted" "$(get_body)"

# Verify gone
status=$(http_status "$API/api/products/$PRODUCT_ID")
assert_status "deleted product returns 404" 404 "$status"

echo ""

# ---------------------------------------------------------------------------
# 4. Queue Consumer Health
# ---------------------------------------------------------------------------
echo "[ 4 ] Queue Consumer"

if command -v wrangler > /dev/null 2>&1; then
    QUEUE_INFO=$(wrangler queues info demo-order-processing 2>/dev/null || true)
    QUEUE_CONSUMERS=$(echo "$QUEUE_INFO" | grep "Number of Consumers:" | awk '{print $4}')

    if [ -n "$QUEUE_CONSUMERS" ] && [ "$QUEUE_CONSUMERS" -ge 1 ]; then
        pass "queue has active consumer(s): $QUEUE_CONSUMERS"
    else
        fail "queue has no consumers (orders will remain queued)"
    fi
else
    echo "  SKIP  wrangler not installed; queue consumer check skipped"
fi

echo ""

# ---------------------------------------------------------------------------
# 5. Orders
# ---------------------------------------------------------------------------
echo "[ 5 ] Orders"

# Get first product id for order
PRODUCTS=$(http_body "$API/api/products")
FIRST_ID=$(echo "$PRODUCTS" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)

if [ -n "$FIRST_ID" ]; then
    req -X POST "$API/api/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customer_id\":\"test-customer\",\"items\":[{\"product_id\":$FIRST_ID,\"quantity\":1,\"unit_price\":24.99}],\"total\":24.99}"
    assert_status "create order returns 200" 200 "$(get_status)"
    assert_contains "order returns order_id" "order_id" "$(get_body)"
    assert_contains "order status is queued" "queued" "$(get_body)"

    ORDER_ID=$(get_body | grep -o '"order_id":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$ORDER_ID" ]; then
        if wait_for_order_in_admin "$ORDER_ID"; then
            pass "queued order appears in admin orders"
        else
            fail "queued order did not appear in admin orders within 30s"
        fi
    else
        fail "could not parse order_id from create order response"
    fi
else
    fail "create order (no products available to order)"
fi

# Missing required fields
status=$(http_status -X POST "$API/api/orders" \
    -H "Content-Type: application/json" \
    -d '{"customer_id":"test"}')
assert_status "order missing items returns 400" 400 "$status"

echo ""

# ---------------------------------------------------------------------------
# 6. Upload
# ---------------------------------------------------------------------------
echo "[ 6 ] Upload"

# Create a temp file
TMPFILE=$(mktemp /tmp/test-upload.XXXXXX.txt)
echo "test file content $(date)" > "$TMPFILE"

req -X POST "$API/api/upload" -F "file=@$TMPFILE"
assert_status "file upload returns 200" 200 "$(get_status)"
assert_contains "upload returns filename" "filename" "$(get_body)"
assert_contains "upload returns url" "uploads.$ZONE_NAME" "$(get_body)"

rm "$TMPFILE"

# No file
status=$(http_status -X POST "$API/api/upload")
assert_status "upload with no file returns 400" 400 "$status"

echo ""

# ---------------------------------------------------------------------------
# 7. Admin Panel
# ---------------------------------------------------------------------------
echo "[ 7 ] Admin Panel"

# No auth
status=$(http_status "$ADMIN/")
assert_status "admin without auth returns 401" 401 "$status"

# Wrong password
status=$(http_status -u "admin:wrongpassword" "$ADMIN/")
assert_status "admin with wrong password returns 401" 401 "$status"

# Valid auth - dashboard
req -u "admin:demo123" "$ADMIN/"
assert_status "admin dashboard returns 200" 200 "$(get_status)"
assert_contains "dashboard returns HTML" "Demo Platform Admin" "$(get_body)"

# Stats
req -u "admin:demo123" "$ADMIN/api/stats"
assert_status "admin stats returns 200" 200 "$(get_status)"
assert_contains "stats returns products count" "products" "$(get_body)"
assert_contains "stats returns orders count" "orders" "$(get_body)"
assert_contains "stats returns revenue" "revenue" "$(get_body)"

# Products list
req -u "admin:demo123" "$ADMIN/api/products"
assert_status "admin products returns 200" 200 "$(get_status)"
assert_contains "admin products returns array" "products" "$(get_body)"

# Orders list
req -u "admin:demo123" "$ADMIN/api/orders"
assert_status "admin orders returns 200" 200 "$(get_status)"
assert_contains "admin orders returns array" "orders" "$(get_body)"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
TOTAL=$((PASS + FAIL))
echo "================================================"
echo " Results: $PASS/$TOTAL passed"
echo "================================================"

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo ""
    echo "Failed tests:"
    for err in "${ERRORS[@]}"; do
        echo "  - $err"
    done
    echo ""
    exit 1
else
    echo ""
    echo "All tests passed."
    echo ""
    exit 0
fi
