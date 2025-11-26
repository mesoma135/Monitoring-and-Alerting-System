#!/bin/bash

METRICS_FILE="$HOME/sysmon/metrics-$(date -u +%Y%m%d).jsonl"

# Defining Thresholds
CPU_THRESHOLD=90
MEM_THRESHOLD=85
DISK_THRESHOLD=80
STD_THRESHOLD=5

# Checking for JSON file
if [ ! -f "$METRICS_FILE" ]; then
  echo "ERROR: Metrics file not found: $METRICS_FILE"
  exit 1
fi

# Get the latest line from JSONL file
latest_line=$(tail -n 1 "$METRICS_FILE")

# Extract values from JSON using jq
cpu=$(echo "$latest_line" | jq '.cpu.idle_pct // 0' 2>/dev/null || echo "0")
mem_used=$(echo "$latest_line" | jq '.mem_bytes.total - .mem_bytes.free // 0' 2>/dev/null || echo "0")
mem_total=$(echo "$latest_line" | jq '.mem_bytes.total // 1' 2>/dev/null || echo "1")

# Calculate memory percentage
if (( $(echo "$mem_total > 0" | bc -l) )); then
  memory=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc -l)
else
  memory=0
fi

# Get disk usage (approximate)
disk=$(echo "$latest_line" | jq '.du_top[0].size // 0' 2>/dev/null || echo "0")

# Placeholder for errors
errors=0

# Threshold Check Function
check_threshold() {
  local value=$1
  local threshold=$2
  local name=$3
  
  # Remove any non-numeric characters
  value=$(echo "$value" | sed 's/[^0-9.]//g')
  
  if (( $(echo "$value > $threshold" | bc -l) )); then
    echo "ALERT_${name}_HIGH:$value"
  else
    echo "OK_${name}:$value"
  fi
}

# Threshold Checks
check_threshold "$cpu" "$CPU_THRESHOLD" "CPU"
check_threshold "$memory" "$MEM_THRESHOLD" "MEMORY"
check_threshold "$disk" "$DISK_THRESHOLD" "DISK"

# Anomaly Detection with a sliding window of 5
HISTORY_FILE="/tmp/error_history.txt"

# Create the file if not found in directory
touch "$HISTORY_FILE"

# Append new value
echo "$errors" >> "$HISTORY_FILE"

# Keep only last 5 entries
tail -n 5 "$HISTORY_FILE" > /tmp/tmp_history
mv /tmp/tmp_history "$HISTORY_FILE"

# Calculate the mean
mean=$(awk '{sum+=$1} END {if (NR>0) print sum/NR; else print 0}' "$HISTORY_FILE")

# Detect spikes
if (( $(echo "$errors > $mean + $STD_THRESHOLD" | bc -l) )); then
  echo "ANOMALY_ERROR_SPIKE:true"
else
  echo "ANOMALY_ERROR_SPIKE:false"
fi



