#!/usr/bin/env bash
set -Eeuo pipefail

# ================================================
# CONFIG
# ================================================

OUT_DIR="$(dirname "$0")/metrics"
SYSLOG="${SYSLOG:-/var/log/syslog}"
DU_TOP_PATH="${DU_TOP_PATH:-/}"
DU_TOP_N="${DU_TOP_N:-10}"

HOST="$(hostname -f || hostname)"
STAMP="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"

mkdir -p "$OUT_DIR"
OUT_FILE="$OUT_DIR/metrics-$(date -u +%Y%m%d).jsonl"
touch "$OUT_FILE"

# ================================================
# DEPENDENCY CHECKS
# ================================================

reqs=(top df du ps grep awk sed date uname jq systemctl)
for r in "${reqs[@]}"; do
  command -v "$r" >/dev/null 2>&1 || {
    echo "ERROR: Missing dependency: $r" >&2
    exit 1
  }
done

# ================================================
# SERVICE CHECKER (SANITIZED)
# ================================================

collect_services() {
  services=("apache2" "mysql" "nginx" "ssh" "cron")

  service_array=$(
    for s in "${services[@]}"; do
      state=$(systemctl is-active "$s" 2>/dev/null || echo "unknown")
      state_clean=$(printf "%s" "$state" | tr -d '\000-\031')
      printf '{"service":"%s","status":"%s"}\n' "$s" "$state_clean"
    done | jq -s .
  )

  jq -cn \
    --arg host "$HOST" \
    --arg ts "$STAMP" \
    --argjson services "$service_array" \
    '{type:"services", host:$host, ts:$ts, services:$services}'
}

# ================================================
# CPU + MEMORY
# ================================================

collect_load_mem_cpu() {

  load=$(awk '{print $1","$2","$3}' /proc/loadavg)

  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2*1024}')
  mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2*1024}')
  swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2*1024}')
  swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2*1024}')

  # CPU idle %
  cpu_idle=$(grep 'cpu ' /proc/stat | awk '{idle=$5; total=$2+$3+$4+$5+$6+$7+$8; printf "%.2f",(idle/total)*100}')

  jq -cn \
    --arg host "$HOST" \
    --arg ts "$STAMP" \
    --arg load "$load" \
    --arg mem_total "$mem_total" \
    --arg mem_free "$mem_free" \
    --arg swap_total "$swap_total" \
    --arg swap_free "$swap_free" \
    --arg cpu_idle "$cpu_idle" \
    '{
      type:"load_mem_cpu",
      host:$host,
      ts:$ts,
      loadavg:$load,
      mem_bytes:{total:($mem_total|tonumber), free:($mem_free|tonumber)},
      swap_bytes:{total:($swap_total|tonumber), free:($swap_free|tonumber)},
      cpu:{idle_pct:($cpu_idle|tonumber)}
    }'
}

# ================================================
# DISK
# ================================================

collect_disk() {

  df_json=$(
    df -P | awk 'NR>1 {
      printf "{\"fs\":\"%s\",\"size\":\"%s\",\"used\":\"%s\",\"avail\":\"%s\",\"mnt\":\"%s\"}\n",$1,$2,$3,$4,$6
    }' | jq -s .
  )

  du_json=$(
    du -x -h "$DU_TOP_PATH" 2>/dev/null | sort -hr | head -n "$DU_TOP_N" | \
    awk '{printf "{\"size\":\"%s\",\"path\":\"%s\"}\n",$1,$2}' | jq -s .
  )

  jq -cn \
    --arg host "$HOST" \
    --arg ts "$STAMP" \
    --argjson df "$df_json" \
    --argjson du "$du_json" \
    '{type:"disk", host:$host, ts:$ts, df:$df, du_top:$du}'
}

# ================================================
# EXECUTION (SANITIZED)
# ================================================

{
  collect_services
  collect_load_mem_cpu
  collect_disk
} >> "$OUT_FILE"

echo "Data written to: $OUT_FILE"
