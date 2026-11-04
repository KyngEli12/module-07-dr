#!/usr/bin/env bash
# =============================================================
# DR Failover Drill — Pilot Light (us-east-1 → us-west-2)
#
# Run this AFTER terraform apply to simulate a DR event.
# What it does:
#   1. Stops primary ASG (simulates region failure)
#   2. Activates DR ASG (pilot light → live)
#   3. Promotes DR RDS read replica → standalone primary
#   4. Verifies Route 53 DNS flips to DR within ~90s
#   5. Measures RTO (time from stop to DR serving traffic)
# =============================================================

set -euo pipefail

# --- Config (populate from terraform output) ---
PRIMARY_ASG_NAME=$(terraform output -raw dr_asg_name | sed 's/-dr-/-primary-/')
DR_ASG_NAME=$(terraform output -raw dr_asg_name)
DR_REPLICA_ID=$(terraform output -raw dr_replica_identifier)
APP_URL=$(terraform output -raw app_url)
PRIMARY_REGION="us-east-1"
DR_REGION="us-west-2"

echo "=============================================="
echo " DR FAILOVER DRILL — $(date)"
echo " Primary region : $PRIMARY_REGION"
echo " DR region      : $DR_REGION"
echo "=============================================="

# --- Step 1: Confirm baseline ---
echo ""
echo "[1/5] Baseline check — primary should be serving traffic..."
RESPONSE=$(curl -sf "$APP_URL" 2>/dev/null || echo "UNREACHABLE")
echo "  Response: $RESPONSE"

DRILL_START=$(date +%s)

# --- Step 2: Simulate primary failure — scale ASG to 0 ---
echo ""
echo "[2/5] SIMULATING FAILURE — scaling primary ASG to 0..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$PRIMARY_ASG_NAME" \
  --desired-capacity 0 \
  --region "$PRIMARY_REGION"
echo "  Primary ASG scaled to 0. Route 53 health check will begin failing."
echo "  Health check threshold: 3 failures × 30s = ~90s until DNS flips"

# --- Step 3: Activate DR — scale pilot light to 1 ---
echo ""
echo "[3/5] ACTIVATING DR — scaling pilot light ASG to 1..."
aws autoscaling set-desired-capacity \
  --auto-scaling-group-name "$DR_ASG_NAME" \
  --desired-capacity 1 \
  --region "$DR_REGION"
echo "  DR ASG scaling. Instance startup ~60s."

# --- Step 4: Promote RDS read replica ---
echo ""
echo "[4/5] PROMOTING RDS read replica → standalone primary..."
aws rds promote-read-replica \
  --db-instance-identifier "$DR_REPLICA_ID" \
  --region "$DR_REGION"

echo "  Waiting for replica promotion (this takes 2-5 minutes)..."
aws rds wait db-instance-available \
  --db-instance-identifier "$DR_REPLICA_ID" \
  --region "$DR_REGION"
echo "  RDS replica promoted. Now accepting writes in $DR_REGION."

# --- Step 5: Poll until Route 53 flips ---
echo ""
echo "[5/5] Monitoring DNS failover — polling every 15s..."
MAX_WAIT=300
ELAPSED=0
DR_ACTIVE=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
  RESPONSE=$(curl -sf --max-time 5 "$APP_URL" 2>/dev/null || echo "UNREACHABLE")

  if echo "$RESPONSE" | grep -q "us-west-2"; then
    DR_ACTIVE=true
    break
  fi

  echo "  t+${ELAPSED}s — still primary or unreachable: $RESPONSE"
  sleep 15
  ELAPSED=$((ELAPSED + 15))
done

DRILL_END=$(date +%s)
RTO=$((DRILL_END - DRILL_START))

echo ""
echo "=============================================="
if [ "$DR_ACTIVE" = true ]; then
  echo " ✅ FAILOVER COMPLETE"
  echo "    RTO achieved: ${RTO}s (~$((RTO / 60))m $((RTO % 60))s)"
  echo "    DR region is serving traffic."
  echo ""
  echo "    Final response: $RESPONSE"
else
  echo " ⚠️  DNS has not flipped after ${MAX_WAIT}s."
  echo "    Check Route 53 health check status in the console."
  echo "    Health check may need more time — TTL and resolver caching varies."
fi
echo "=============================================="

echo ""
echo "--- POST-DRILL: Restore primary (cleanup) ---"
echo "To restore primary when done:"
echo "  aws autoscaling set-desired-capacity --auto-scaling-group-name $PRIMARY_ASG_NAME --desired-capacity 1 --region $PRIMARY_REGION"
echo "  aws autoscaling set-desired-capacity --auto-scaling-group-name $DR_ASG_NAME --desired-capacity 0 --region $DR_REGION"
echo "  NOTE: To restore RDS replication, you must create a new read replica from the promoted instance."
