#!/usr/bin/env bash
# ==============================================================================
# MacBookPro7,1 (2010 Mid) Smart Audio & Display Auto-Router Daemon
# Plugged in DP/HDMI:
#   - Lid Open: TV primary (1080p60 + underscan), LVDS internal LCD stays ON (failsafe)
#   - Lid Closed: Clamshell mode, TV only, LVDS internal LCD OFF
# Unplugged: LVDS 1280x800 internal LCD ON, internal speakers ON
# ==============================================================================
export XDG_RUNTIME_DIR="/run/user/$(id -u 2>/dev/null || echo 1000)"
export DISPLAY="${DISPLAY:-:0.0}"
export XAUTHORITY="${XAUTHORITY:-/home/namobuddha/.Xauthority}"

CARD="alsa_card.pci-0000_00_08.0"
SINK_HDMI="alsa_output.pci-0000_00_08.0.hdmi-stereo-extra1"
SINK_ANALOG="alsa_output.pci-0000_00_08.0.analog-stereo"
PROFILE_HDMI="output:hdmi-stereo-extra1+input:analog-stereo"
PROFILE_ANALOG="output:analog-stereo+input:analog-stereo"

LAST_STATE=""
LAST_LID=""

# Ensure DPMS and screen blanking do not turn off display signal
xset -dpms s off s noblank 2>/dev/null || true

set_dp_display() {
  LID_CLOSED=0
  if grep -q 'closed' /proc/acpi/button/lid/*/state 2>/dev/null; then
    LID_CLOSED=1
  fi

  # Mode selection for DP-1
  if xrandr 2>/dev/null | grep -A 10 '^DP-1 connected' | grep -E '1920x1080[[:space:]]+.*60\.00' >/dev/null; then
    MODE_ARGS="--mode 1920x1080 --rate 60.00"
  elif xrandr 2>/dev/null | grep -A 10 '^DP-1 connected' | grep -E '1920x1080[[:space:]]' >/dev/null; then
    MODE_ARGS="--mode 1920x1080"
  else
    MODE_ARGS="--auto"
  fi

  if [ "$LID_CLOSED" -eq 1 ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Lid is closed -> Clamshell mode: TV only, LVDS off"
    xrandr --output DP-1 --primary $MODE_ARGS --output LVDS-1 --off 2>/dev/null || true
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Lid is open -> Safe Dual mode: TV primary, LVDS on"
    xrandr --output DP-1 --primary $MODE_ARGS --output LVDS-1 --mode 1280x800 --right-of DP-1 2>/dev/null || true
  fi

  # Apply underscan to eliminate TV overscan cropping (5% margin, 16:9 ratio)
  xrandr --output DP-1 --set underscan on --set "underscan hborder" 48 --set "underscan vborder" 27 2>/dev/null || true
}

while true; do
  IS_CONNECTED=0
  if xrandr 2>/dev/null | grep -q "^DP-1 connected"; then
    IS_CONNECTED=1
  fi

  if [ "$IS_CONNECTED" -eq 1 ]; then
    CURRENT_STATE="HDMI"
  else
    CURRENT_STATE="ANALOG"
  fi

  CURRENT_LID=$(grep -oE 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null || echo "open")

  # Auto-heal display signal: if DP-1 is connected but has dropped active mode or lid changed
  if [ "$CURRENT_STATE" = "HDMI" ]; then
    if xrandr 2>/dev/null | grep -q '^DP-1 connected (' || [ "$CURRENT_LID" != "$LAST_LID" ]; then
      set_dp_display
      LAST_LID="$CURRENT_LID"
    fi
  fi

  # State transition or self-healing audio profile
  CURRENT_PROFILE=$(pactl list cards 2>/dev/null | awk -F': ' '/Active Profile:/{print $2}')

  if [ "$CURRENT_STATE" != "$LAST_STATE" ] || ([ "$CURRENT_STATE" = "HDMI" ] && [ "$CURRENT_PROFILE" != "$PROFILE_HDMI" ]); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Audio Router applying $CURRENT_STATE (active profile: $CURRENT_PROFILE)..."
    if [ "$CURRENT_STATE" = "HDMI" ]; then
      set_dp_display

      pactl set-card-profile "$CARD" "$PROFILE_HDMI" 2>/dev/null || true
      pactl set-default-sink "$SINK_HDMI" 2>/dev/null || true
      pactl set-sink-mute "$SINK_HDMI" 0 2>/dev/null || true
      pactl set-sink-volume "$SINK_HDMI" 100% 2>/dev/null || true
      for inp in $(pactl list sink-inputs short 2>/dev/null | awk '{print $1}'); do
        pactl move-sink-input "$inp" "$SINK_HDMI" 2>/dev/null || true
      done
    else
      xrandr --output LVDS-1 --primary --mode 1280x800 --output DP-1 --off 2>/dev/null || true

      pactl set-card-profile "$CARD" "$PROFILE_ANALOG" 2>/dev/null || true
      pactl set-default-sink "$SINK_ANALOG" 2>/dev/null || true
      pactl set-sink-mute "$SINK_ANALOG" 0 2>/dev/null || true
      pactl set-sink-volume "$SINK_ANALOG" 100% 2>/dev/null || true
      for inp in $(pactl list sink-inputs short 2>/dev/null | awk '{print $1}'); do
        pactl move-sink-input "$inp" "$SINK_ANALOG" 2>/dev/null || true
      done
    fi
    LAST_STATE="$CURRENT_STATE"
  fi

  sleep 2
done
