#!/bin/bash
# Cache latency comparison demo
# Shows HIT vs MISS response times for the products API

set -euo pipefail

ZONE_NAME=""
if [ -f "terraform.tfvars" ]; then
    ZONE_NAME=$(grep 'zone_name' terraform.tfvars | cut -d'"' -f2)
fi

if [ -z "$ZONE_NAME" ]; then
    echo "ERROR: zone_name not found in terraform.tfvars"
    exit 1
fi

API="https://api.$ZONE_NAME"
ROUNDS=${1:-5}

echo "================================================"
echo " Cache Latency Comparison"
echo " Zone: $ZONE_NAME"
echo " Rounds: $ROUNDS"
echo "================================================"
echo ""

# ---------------------------------------------------------------------------
# Step 1: Bust the cache by creating and deleting a product (triggers cache clear)
# ---------------------------------------------------------------------------
echo "Busting KV cache..."
curl -s -X POST "$API/api/products" \
    -H "Content-Type: application/json" \
    -d '{"name":"__cache_bust__","price":0.01}' -o /dev/null
BUST_ID=$(curl -s "$API/api/products" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
curl -s -X DELETE "$API/api/products/$BUST_ID" -o /dev/null 2>/dev/null || true
echo "Cache cleared."
echo ""

# ---------------------------------------------------------------------------
# Step 2: MISS — first request hits D1
# ---------------------------------------------------------------------------
echo "[ MISS ] First request — no cache, querying D1..."
MISS_TIMES=()
for i in $(seq 1 $ROUNDS); do
    T=$( { time curl -s "$API/api/products" -o /dev/null; } 2>&1 | grep real | awk '{print $2}')
    MS=$(echo "$T" | awk -F'[ms]' '{print ($1 * 60000) + ($2 * 1000) + $3}' | awk '{printf "%.0f", $1}')
    MISS_TIMES+=($MS)
    HEADER=$(curl -s -o /dev/null -w "%{header_json}" "$API/api/products" 2>/dev/null | grep -o '"x-products-cache":\["[^"]*"\]' | grep -o 'HIT\|MISS' || echo "?")
    echo "  Round $i: ${MS}ms  [$HEADER]"
done

# ---------------------------------------------------------------------------
# Step 3: HIT — subsequent requests served from KV
# ---------------------------------------------------------------------------
echo ""
echo "[ HIT ] Subsequent requests — served from KV cache..."
HIT_TIMES=()
for i in $(seq 1 $ROUNDS); do
    T=$( { time curl -s "$API/api/products" -o /dev/null; } 2>&1 | grep real | awk '{print $2}')
    MS=$(echo "$T" | awk -F'[ms]' '{print ($1 * 60000) + ($2 * 1000) + $3}' | awk '{printf "%.0f", $1}')
    HIT_TIMES+=($MS)
    HEADER=$(curl -s -o /dev/null -w "%{header_json}" "$API/api/products" 2>/dev/null | grep -o '"x-products-cache":\["[^"]*"\]' | grep -o 'HIT\|MISS' || echo "?")
    echo "  Round $i: ${MS}ms  [$HEADER]"
done

# ---------------------------------------------------------------------------
# Step 4: Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================"
echo " Results"
echo "================================================"

# Compute averages using awk
MISS_AVG=$(echo "${MISS_TIMES[@]}" | tr ' ' '\n' | awk '{s+=$1; n++} END {printf "%.0f", s/n}')
HIT_AVG=$(echo "${HIT_TIMES[@]}"  | tr ' ' '\n' | awk '{s+=$1; n++} END {printf "%.0f", s/n}')

if [ "$MISS_AVG" -gt 0 ]; then
    SPEEDUP=$(echo "$MISS_AVG $HIT_AVG" | awk '{printf "%.1f", $1/$2}')
else
    SPEEDUP="N/A"
fi

echo ""
echo "  Average MISS (D1 query):  ${MISS_AVG}ms"
echo "  Average HIT  (KV cache):  ${HIT_AVG}ms"
echo "  Cache speedup:            ${SPEEDUP}x faster"
echo ""
echo "  KV cache TTL: 10 minutes"
echo "  Edge cache TTL (Cache Rules): 5 minutes"
echo ""
