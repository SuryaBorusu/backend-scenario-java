#!/usr/bin/env bash
# load-test.sh — Generate traffic against the PetClinic API for observability testing
# Usage: ./load-test.sh [base_url]

BASE_URL="${1:-http://localhost:9966/petclinic}"
API="$BASE_URL/api"

echo "==> PetClinic Load Test"
echo "    Target: $API"
echo ""

# ── 1. Warm-up: 50 requests to common endpoints ──────────────────────────────
echo "[1/4] Warm-up (50 requests across endpoints)..."
for i in $(seq 1 50); do
  curl -s -o /dev/null "$API/owners"
  curl -s -o /dev/null "$API/vets"
  curl -s -o /dev/null "$API/pets"
  curl -s -o /dev/null "$API/pettypes"
  curl -s -o /dev/null "$API/visits"
done
echo "      Done."

# ── 2. Sustained load: 200 requests to /owners ───────────────────────────────
echo "[2/4] Sustained load (200 GET /owners)..."
for i in $(seq 1 200); do
  curl -s -o /dev/null "$API/owners"
done
echo "      Done."

# ── 3. Error traffic: 404s to populate error rate panel ──────────────────────
echo "[3/4] Error traffic (30 x 404 requests)..."
for i in $(seq 1 30); do
  curl -s -o /dev/null "$API/owners/99999"
  curl -s -o /dev/null "$API/pets/99999"
  curl -s -o /dev/null "$API/vets/99999"
done
echo "      Done."

# ── 4. Mixed burst: parallel requests to spike CPU + latency ─────────────────
echo "[4/5] Burst load (100 parallel requests)..."
for i in $(seq 1 100); do
  curl -s -o /dev/null "$API/owners" &
done
wait
echo "      Done."

# ── 5. 500 error traffic: invalid endpoint to populate server-error panel ─────
echo "[5/5] 500 error traffic (30 x invalid endpoint requests)..."
for i in $(seq 1 30); do
  curl -s -o /dev/null "$BASE_URL/api/o76e73"
done
echo "      Done."

echo ""
echo "==> Load test complete. Check Grafana at http://localhost:3000"
echo "    Wait ~30s for Prometheus to scrape and panels to update."
