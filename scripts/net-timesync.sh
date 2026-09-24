#!/usr/bin/env bash
# ==============================================================================
# Automatic Boot Time Synchronizer for Battery-less Systems (MacBookPro7,1)
# 1. Loads saved timestamp immediately to escape year 2001.
# 2. Probes HTTP Date headers from fast reliable targets to sync exact second.
# 3. Synchronizes system clock and writes to hwclock & fake-hwclock.
# ==============================================================================
LOG_FILE="/var/log/net-timesync.log"
exec >> "$LOG_FILE" 2>&1

echo "--------------------------------------------------------"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] net-timesync triggered ($*)"

# 1. Step 1: Load last known saved clock immediately
if command -v fake-hwclock >/dev/null 2>&1; then
  fake-hwclock load force || true
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Loaded fake-hwclock"
fi

# 2. Step 2: Probe HTTP Date in loop (up to 60 tries = 120s)
PROBE_URLS=(
  "http://connectivitycheck.gstatic.com/generate_204"
  "http://www.google.com"
  "http://www.baidu.com"
  "http://192.168.91.1"
)

SYNCED=0
for i in $(seq 1 60); do
  for url in "${PROBE_URLS[@]}"; do
    DATE_STR=$(curl -sI -m 2 "$url" 2>/dev/null | grep -i '^date:' | head -1 | cut -d: -f2- | tr -d '\r\n')
    if [ -n "$DATE_STR" ]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Got Date from $url: $DATE_STR"
      date -s "$DATE_STR"
      hwclock -w || true
      if command -v fake-hwclock >/dev/null 2>&1; then
        fake-hwclock save || true
      fi
      SYNCED=1
      break 2
    fi
  done
  sleep 2
done

if [ "$SYNCED" -eq 1 ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Clock synchronized successfully! Current: $(date)"
  exit 0
else
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Timed out waiting for network connectivity."
  exit 1
fi
