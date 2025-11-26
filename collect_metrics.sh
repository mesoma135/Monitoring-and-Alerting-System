#!/usr/bin/env bash
set -Eeuo pipefail

# ================================================
# CONFIG
# ================================================

OUT_DIR="$(dirname "$0")/metrics"
SYSLOG="${SYSLOG:-/var/log/syslog}"       # For Kali/Ubuntu
LOG_GLOB="${LOG_GLOB:-}"                 
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

reqs=(top df du ps lsof grep awk sed date uname jq systemctl)
for r in "${reqs[@]}"; do
  command -v "$r" >/dev/null 2>&1 || {
    echo "ERROR: Missing dependency: $r" >&2
    exit 1
  }
done

# Network tools
if command -v ss >/dev/null 2>&1; then NETSTAT_BIN="ss"; elif command -v netstat >/dev/null 2>&1; then NETSTAT_BIN="netstat"; else echo "ERROR: Need ss or netstat"; exit 1; fi
if command -v ip >/dev/null 2>&1; then IFCONF_BIN="ip"; elif command -v ifconfig >/dev/null 2>&1; then IFCONF_BIN="ifconfig"; else echo "ERROR: Need ip or ifconfig"; exit 1; fi

# ================================================
# SERVICE CHECKER (NEW)
# ================================================
collect_services() {
  services=("apache2" "mysql" "nginx" "ssh" "cron")
  status_list=()

  for s in "${services[@]}"; do
    state=$(systemctl is-active "$s" 2>/dev/null || echo "unknown")
    status_list+=("{\"service\":\"$s\",\"status\":\"$state\"}")
  done

  printf "%s\n" "$(jq -cn --arg host "$HOST" --arg ts "$STAMP" --argjson services "[${status_list[*]}]" \
  '{type:"services", host:$host, ts:$ts, services:$services}')"
}

# ================================================
# COLLECTORS
# ================================================

collect_load_mem_cpu() {
  load=$(awk '{print $1","$2","$3}' /proc/loadavg)

  mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2*1024}')
  mem_free=$(grep MemAvailable /proc/meminfo | awk '{print $2*1024}')
  swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2*1024}')
  swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2*1024}')

  cpu_idle=$(grep 'cpu ' /proc/stat | awk '{idle=$5; total=$2+$3+$4+$5+$6+$7+$8; printf "%.2f", (idle/total)*100}')

  jq -cn --arg host "$HOST" --arg ts "$STAMP" \
    --arg load "$load" \
    --arg mem_total "$mem_total" \
    --arg mem_free "$mem_free" \
    --arg swap_total "$swap_total" \
    --arg swap_free "$swap_free" \
    --arg cpu_idle "$cpu_idle" \
    '{type:"load_mem_cpu", host:$host, ts:$ts,
      loadavg:$load,
      mem_bytes:{total:($mem_total|tonumber), free:($mem_free|tonumber)},
      swap_bytes:{total:($swap_total|tonumber), free:($swap_free|tonumber)},
      cpu:{idle_pct:($cpu_idle|tonumber)} }'
}

collect_disk() {
  df_json=$(df -P | awk 'NR>1 {
    print "{\"fs\":\""$1"\",\"size\":\""$2"\",\"used\":\""$3"\",\"avail\":\""$4"\",\"mnt\":\""$6"\"}"
  }' | jq -s .)

  du_json=$(du -x -h "$DU_TOP_PATH" 2>/dev/null | sort -hr | head -n "$DU_TOP_N" | awk '{
    print "{\"size\":\""$1"\",\"path\":\""$2"\"}"
  }' | jq -s .)

  jq -cn --arg host "$HOST" --arg ts "$STAMP" \
    --argjson df "$df_json" \
    --argjson du "$du_json" \
    '{type:"disk", host:$host, ts:$ts, df:$df, du_top:$du}'
}

collect_procs() {
  top_cpu=$(ps -eo pid,ppid,comm,%cpu,%mem --sort=-%cpu | head -n 11 | tail -n +2 | \
    awk '{printf "{\"pid\":%s,\"ppid\":%s,\"cmd\":\"%s\",\"cpu\":%s,\"mem\":%s}\n",$1,$2,$3,$4,$5}' | jq -s .)

  top_mem=$(ps -eo pid,ppid,comm,%mem,%cpu --sort=-%mem | head -n 11 | tail -n +2 | \
    awk '{printf "{\"pid\":%s,\"ppid\":%s,\"cmd\":\"%s\",\"mem\":%s,\"cpu\":%s}\n",$1,$2,$3,$4,$5}' | jq -s .)

  if has_lsof=$(command -v lsof >/dev/null 2>&1); then
    lsof_json=$(lsof -n 2>/dev/null | awk 'NR>1{c[$1]++} END{for(p in c) printf("{\"proc\":\"%s\",\"open_files\":%d}\n",p,c[p])}' | jq -s .)
  else
    lsof_json="[]"
  fi

  jq -cn --arg host "$HOST" --arg ts "$STAMP" \
    --argjson cpu "$top_cpu" \
    --argjson mem "$top_mem" \
    --argjson lsof "$lsof_json" \
    '{type:"processes", host:$host, ts:$ts, top_cpu:$cpu, top_mem:$mem, open_files:$lsof}'
}

collect_network() {
  if [ "$IFCONF_BIN" = "ip" ]; then
    interfaces=$(ip -j addr)
  else
    interfaces=$(ifconfig | sed 's/"/\\"/g' | jq -Rs '.')
  fi

  if [ "$NETSTAT_BIN" = "ss" ]; then
    connections=$(ss -tanp | jq -Rs '.')
  else
    connections=$(netstat -tanp | jq -Rs '.')
  fi

  jq -cn --arg host "$HOST" --arg ts "$STAMP" \
    --argjson interfaces "$interfaces" \
    --arg connections "$connections" \
    '{type:"network", host:$host, ts:$ts, interfaces:$interfaces, connections:$connections}'
}

collect_logs() {
  logs=""
  if [ -r "$SYSLOG" ]; then
    logs=$(tail -n 2000 "$SYSLOG" | grep -Ei 'error|warn|crit' || true)
  fi

  if [ -n "$LOG_GLOB" ]; then
    for f in $LOG_GLOB; do
      if [ -r "$f" ]; then
        extra=$(tail -n 1000 "$f" | grep -Ei 'error|warn|crit' || true)
        logs="$logs"$'\n'"$extra"
      fi
    done
  fi

  jq -cn --arg host "$HOST" --arg ts "$STAMP" --arg logs "$logs" \
    '{type:"logs", host:$host, ts:$ts, matched:$logs}'
}

# ================================================
# EXECUTION
# ================================================

{
  collect_load_mem_cpu
  collect_disk
  collect_procs
  collect_network
  collect_logs
  collect_services   # <--- NEW
} >> "$OUT_FILE"

echo "Data written to: $OUT_FILE"
