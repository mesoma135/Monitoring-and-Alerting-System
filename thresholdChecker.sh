#!/bin/bash
echo "THRESHOLD CHECKER RAN at $(date)"

METRICS_FILE="$(dirname "$0")/metrics/metrics-$(date -u +%Y%m%d).jsonl"

CPU_THRESHOLD=50
MEM_THRESHOLD=10
DISK_THRESHOLD=1
STD_THRESHOLD=5

if [ ! -f "$METRICS_FILE" ]; then
  echo "ERROR: Metrics file not found: $METRICS_FILE"
  exit 1
fi

latest_line=$(tail -n 6 "$METRICS_FILE" | jq -s '.[-1]')

cpu=$(echo "$latest_line" | jq '.cpu.idle_pct // 0')
mem_used=$(echo "$latest_line" | jq '.mem_bytes.total - .mem_bytes.free')
mem_total=$(echo "$latest_line" | jq '.mem_bytes.total')
disk=$(echo "$latest_line" | jq '.du_top[0].size // 0')

# -------------------------
# Threshold Check Function
# -------------------------
check_threshold() {
  local value=$1
  local threshold=$2
  local name=$3
  value=$(echo "$value" | sed 's/[^0-9.]//g')
  if (( $(echo "$value > $threshold" | bc -l) )); then
    echo "ALERT_${name}_HIGH:$value"
  else
    echo "OK_${name}:$value"
  fi
}

# Resource checks
check_threshold "$cpu" "$CPU_THRESHOLD" "CPU"
memory=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc -l)
check_threshold "$memory" "$MEM_THRESHOLD" "MEMORY"
check_threshold "$disk" "$DISK_THRESHOLD" "DISK"

# -------------------------
# Service Status Checks (NEW)
# -------------------------
services=$(echo "$latest_line" | jq -c '.services // []')

echo "$services" | jq -c '.[]' | while read item; do
  svc=$(echo "$item" | jq -r '.service')
  status=$(echo "$item" | jq -r '.status')

  if [ "$status" != "active" ]; then
    echo "ALERT_SERVICE_${svc^^}:$status"
  else
    echo "OK_SERVICE_${svc^^}:$status"
  fi
done
  
# -------------------------
# Anomaly Detector
# -------------------------
HISTORY_FILE="/tmp/error_history.txt"
touch "$HISTORY_FILE"

errors=0  
echo "$errors" >> "$HISTORY_FILE"
tail -n 5 "$HISTORY_FILE" > /tmp/tmp_hist
mv /tmp/tmp_hist "$HISTORY_FILE"

mean=$(awk '{sum+=$1} END {print (NR>0 ? sum/NR : 0)}' "$HISTORY_FILE")

if (( $(echo "$errors > $mean + $STD_THRESHOLD" | bc -l) )); then
  echo "ANOMALY_ERROR_SPIKE:true"
else
  echo "ANOMALY_ERROR_SPIKE:false"
fi
