#!/bin/bash
# Cache latency comparison demo
# Shows HIT vs MISS response times for the products API

set -euo pipefail

ZONE_NAME=""
if [ -f "terraform.tfvars" ]; then
	ZONE_NAME=$(sed -n 's/^zone_name[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' terraform.tfvars)
fi

if [ -z "$ZONE_NAME" ]; then
	echo "ERROR: zone_name not found in terraform.tfvars"
	exit 1
fi

API="https://api.$ZONE_NAME"
ROUNDS=${1:-5}
HEADERS=$(mktemp)
trap 'rm -f "$HEADERS"' EXIT

echo "================================================"
echo " Cache Latency Comparison"
echo " Zone: $ZONE_NAME"
echo " Rounds: $ROUNDS"
echo "================================================"
echo ""

# Clear the products API's KV cache. Any write clears it, so create a
# throwaway product and delete it again by the id the POST returned (never
# touching a real product).
clear_cache() {
	local id
	id=$(curl -s --max-time 15 -X POST "$API/api/products" \
		-H "Content-Type: application/json" \
		-d '{"name":"__cache_bust__","price":0.01}' |
		grep -o '"id":[0-9]*' | head -1 | cut -d: -f2 || true)
	if [ -n "$id" ]; then
		curl -s --max-time 15 -X DELETE "$API/api/products/$id" -o /dev/null || true
	fi
}

# Time one GET; print "<ms> <HIT|MISS|?>" from that same request.
timed_get() {
	local secs cache
	secs=$(curl -s --max-time 15 -o /dev/null -D "$HEADERS" -w '%{time_total}' "$API/api/products" || echo 0)
	cache=$(grep -i '^x-products-cache:' "$HEADERS" | tr -d '\r' | awk '{print $2}' || true)
	awk -v s="$secs" -v c="${cache:-?}" 'BEGIN {printf "%.0f %s\n", s * 1000, c}'
}

# ---------------------------------------------------------------------------
# Step 1: MISS: clear the cache before every request, so each one queries D1
# ---------------------------------------------------------------------------
echo "[ MISS ] Cache cleared before each request: querying D1..."
MISS_TIMES=()
for i in $(seq 1 "$ROUNDS"); do
	clear_cache
	read -r MS HEADER < <(timed_get)
	MISS_TIMES+=("$MS")
	echo "  Round $i: ${MS}ms  [$HEADER]"
done

# ---------------------------------------------------------------------------
# Step 2: HIT: the last MISS filled the cache, so these come from KV
# ---------------------------------------------------------------------------
echo ""
echo "[ HIT ] Cache left alone: served from KV..."
HIT_TIMES=()
for i in $(seq 1 "$ROUNDS"); do
	read -r MS HEADER < <(timed_get)
	HIT_TIMES+=("$MS")
	echo "  Round $i: ${MS}ms  [$HEADER]"
done

# ---------------------------------------------------------------------------
# Step 3: Summary
# ---------------------------------------------------------------------------
echo ""
echo "================================================"
echo " Results"
echo "================================================"

# Compute averages using awk
MISS_AVG=$(echo "${MISS_TIMES[@]}" | tr ' ' '\n' | awk '{s+=$1; n++} END {printf "%.0f", s/n}')
HIT_AVG=$(echo "${HIT_TIMES[@]}" | tr ' ' '\n' | awk '{s+=$1; n++} END {printf "%.0f", s/n}')

if [ "$HIT_AVG" -gt 0 ]; then
	SPEEDUP=$(echo "$MISS_AVG $HIT_AVG" | awk '{printf "%.1f", $1/$2}')
else
	SPEEDUP="N/A"
fi

echo ""
echo "  Average MISS (D1 query):  ${MISS_AVG}ms"
echo "  Average HIT  (KV cache):  ${HIT_AVG}ms"
echo "  Cache speedup:            ${SPEEDUP}x faster"
echo ""
echo "  KV cache TTL: 10 minutes (workers/products-api.js)"
echo "  api.<zone> is served by a Worker, so cdn.tf's cache rules don't apply here."
echo ""
