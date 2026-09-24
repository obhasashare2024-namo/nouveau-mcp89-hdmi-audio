#!/bin/bash
set -euo pipefail

echo "=== HDMI Audio Playback Diagnostic & Test Script ==="

# 1. Unmute all ALSA IEC958 / HDMI outputs on Card 0
echo "[1/3] Unmuting ALSA IEC958 controls on card 0..."
amixer -c 0 cset numid=30 on 2>/dev/null || true
amixer -c 0 cset numid=37 on 2>/dev/null || true
amixer -c 0 cset numid=44 on 2>/dev/null || true
amixer -c 0 cset numid=14 on 2>/dev/null || true

# 2. Check ELD
echo "[2/3] Checking HDMI ELD status..."
if [ -f /proc/asound/card0/eld#4.0 ]; then
  cat /proc/asound/card0/eld#4.0 | grep -E "monitor_name|connection_type|sad_count|coding_type" || true
fi

# 3. Play test tone
echo "[3/3] Playing 48kHz stereo sine wave (440Hz) to HDMI device (plughw:0,7)..."
speaker-test -D plughw:0,7 -c 2 -r 48000 -t sine -f 440 -l 1 || true

echo "Done! If you heard a tone from the TV/monitor, HDMI audio is working."
