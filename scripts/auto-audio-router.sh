#!/usr/bin/env bash
# ==============================================================================
# MacBookPro7,1 (2010 Mid) Ultra-Reliable Smart Audio, Display & Power Daemon
# - TV detection: reads /sys/class/drm/card0-DP-1/status & /proc/asound/card0/eld*
#   (Zero xrandr DDC polling in background -> zero I2C collisions -> zero GPU faults)
# - TV Connected & Active (Truly ON):
#   * DP-1 Primary (1080p60 + 16:9 underscan), LVDS-1 OFF (backlight 0)
#   * NoMachine lands cleanly on the 1080p TV screen
#   * Refresh IceWM (icesh restart) to dock taskbar at bottom of 1080p TV
#   * Permanent DPMS disabled (xset -dpms): TV never receives "No Signal"
# - TV Turned Off / Standby / Disconnected:
#   * Immediately returns LVDS-1 to PRIMARY 1280x800, turns off DP-1
#   * Restores LVDS-1 backlight to 40
#   * Refresh IceWM (icesh restart) to dock taskbar at bottom of 1280x800 internal screen
#   * Switches audio back to internal analog speakers
#   * Grace Period Protection: Prevents stale pre-wake idle time from blacking out screen
#   * Inactivity (3m fresh idle): Internal LCD backlight to 0
#   * Inactivity (5m fresh idle): If no audio playing -> enters S3 sleep (pm-suspend)
#   * NoMachine lands cleanly on the 1280x800 laptop screen
# - Watchdog & Post-Wake Resilience:
#   * Automatically checks and restores NoMachine server on boot, post-wake, or failure
# ==============================================================================
trap '' HUP

export XDG_RUNTIME_DIR="/run/user/$(id -u 2>/dev/null || echo 1000)"
export DISPLAY="${DISPLAY:-:0.0}"
export XAUTHORITY="${XAUTHORITY:-/home/namobuddha/.Xauthority}"

# Permanently disable Xorg DPMS timeout & screen blanking
xset -dpms s off s noblank 2>/dev/null || true

CARD="alsa_card.pci-0000_00_08.0"
SINK_HDMI="alsa_output.pci-0000_00_08.0.hdmi-stereo-extra1"
SINK_ANALOG="alsa_output.pci-0000_00_08.0.analog-stereo"
PROFILE_HDMI="output:hdmi-stereo-extra1+input:analog-stereo"
PROFILE_ANALOG="output:analog-stereo+input:analog-stereo"

BACKLIGHT_FILE="/sys/class/backlight/nv_backlight/brightness"
DEFAULT_BRIGHTNESS=40

LAST_STATE=""
LAST_LID=""
BLANKED=0
LAST_SUSPEND_TIME=$(date +%s)
LAST_WAKE_OR_MODE_CHANGE=$(date +%s)
CHECK_NX_COUNTER=0

is_tv_active() {
  local status_file="/sys/class/drm/card0-DP-1/status"
  if [ -r "$status_file" ] && [ "$(cat "$status_file" 2>/dev/null)" = "connected" ]; then
    # Verify TV HDMI audio receiver is actually alive and powered on (not in standby)
    # Both eld_valid=1 and non-empty monitor_name must be present
    if grep -q 'eld_valid[[:space:]]*1' /proc/asound/card0/eld*.0 2>/dev/null && \
       grep -E -q 'monitor_name[[:space:]]+[A-Za-z0-9]' /proc/asound/card0/eld*.0 2>/dev/null; then
      return 0
    fi
  fi
  return 1
}

set_hdmi_display() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting TV single-display mode (DP-1 primary 1080p, LVDS-1 off)..."

  # 1. First ensure DP-1 is enabled as Primary and turn LVDS-1 off
  xrandr --output DP-1 --primary --mode 1920x1080 --rate 60.00 --output LVDS-1 --off 2>/dev/null || \
  xrandr --output DP-1 --primary --auto --output LVDS-1 --off 2>/dev/null || true

  # 2. Dim backlight to 0 (completely dark, zero power)
  if [ -w "$BACKLIGHT_FILE" ]; then
    echo 0 > "$BACKLIGHT_FILE" 2>/dev/null || true
  fi

  # 3. Apply 16:9 proportional underscan (hborder 48, vborder 27)
  xrandr --output DP-1 --set underscan on --set "underscan hborder" 48 --set "underscan vborder" 27 2>/dev/null || true

  # 4. Guarantee DPMS is off on external display
  xset -dpms s off s noblank 2>/dev/null || true

  # 5. Refresh IceWM to immediately dock taskbar at bottom of 1920x1080
  DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" icesh restart 2>/dev/null || true

  LAST_WAKE_OR_MODE_CHANGE=$(date +%s)
  BLANKED=0
}

set_standalone_display() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] TV inactive -> Setting internal display LVDS-1 primary 1280x800..."

  # 1. Unconditionally restore LVDS-1 as the sole primary display at native 1280x800, turn off DP-1
  xrandr --output LVDS-1 --primary --mode 1280x800 --output DP-1 --off 2>/dev/null || true

  # 2. Ensure backlight is restored to default
  if [ -w "$BACKLIGHT_FILE" ]; then
    echo "$DEFAULT_BRIGHTNESS" > "$BACKLIGHT_FILE" 2>/dev/null || true
  fi

  # 3. Ensure DPMS is off
  xset -dpms s off s noblank 2>/dev/null || true

  # 4. Refresh IceWM to immediately dock taskbar at bottom of 1280x800
  DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" icesh restart 2>/dev/null || true

  LAST_WAKE_OR_MODE_CHANGE=$(date +%s)
  BLANKED=0
}

# Initial synchronization on startup
if is_tv_active; then
  CURRENT_STATE="HDMI"
  set_hdmi_display
else
  CURRENT_STATE="ANALOG"
  set_standalone_display
fi
LAST_STATE="$CURRENT_STATE"

while true; do
  if is_tv_active; then
    CURRENT_STATE="HDMI"
  else
    CURRENT_STATE="ANALOG"
  fi

  CURRENT_LID=$(grep -oE 'open|closed' /proc/acpi/button/lid/*/state 2>/dev/null || echo "open")

  # Detect TV Power On/Off transition or Lid switch
  if [ "$CURRENT_STATE" != "$LAST_STATE" ] || ([ "$CURRENT_STATE" = "HDMI" ] && [ "$CURRENT_LID" != "$LAST_LID" ]); then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Display State Change: $LAST_STATE -> $CURRENT_STATE (Lid: $CURRENT_LID)"

    if [ "$CURRENT_STATE" = "HDMI" ]; then
      set_hdmi_display

      pactl set-card-profile "$CARD" "$PROFILE_HDMI" 2>/dev/null || true
      pactl set-default-sink "$SINK_HDMI" 2>/dev/null || true
      pactl set-sink-mute "$SINK_HDMI" 0 2>/dev/null || true
      pactl set-sink-volume "$SINK_HDMI" 100% 2>/dev/null || true
      for inp in $(pactl list sink-inputs short 2>/dev/null | awk '{print $1}'); do
        pactl move-sink-input "$inp" "$SINK_HDMI" 2>/dev/null || true
      done
    else
      set_standalone_display

      pactl set-card-profile "$CARD" "$PROFILE_ANALOG" 2>/dev/null || true
      pactl set-default-sink "$SINK_ANALOG" 2>/dev/null || true
      pactl set-sink-mute "$SINK_ANALOG" 0 2>/dev/null || true
      pactl set-sink-volume "$SINK_ANALOG" 100% 2>/dev/null || true
      for inp in $(pactl list sink-inputs short 2>/dev/null | awk '{print $1}'); do
        pactl move-sink-input "$inp" "$SINK_ANALOG" 2>/dev/null || true
      done
    fi

    LAST_STATE="$CURRENT_STATE"
    LAST_LID="$CURRENT_LID"
    BLANKED=0
  fi

  # ============================================================================
  # Non-Destructive Power Management (Hardware Backlight & S3 Auto-Suspend)
  # ============================================================================
  IDLE_MS=$(DISPLAY="$DISPLAY" XAUTHORITY="$XAUTHORITY" xprintidle 2>/dev/null || echo 0)
  NOW=$(date +%s)
  SINCE_WAKE=$((NOW - LAST_WAKE_OR_MODE_CHANGE))

  AUDIO_PLAYING=0
  if pactl list sinks 2>/dev/null | grep -q 'State: RUNNING'; then
    AUDIO_PLAYING=1
  fi

  # In HDMI Mode: LVDS-1 is off and backlight is locked to 0
  if [ "$CURRENT_STATE" = "HDMI" ]; then
    if [ -w "$BACKLIGHT_FILE" ] && [ "$(cat "$BACKLIGHT_FILE" 2>/dev/null)" != "0" ]; then
      echo 0 > "$BACKLIGHT_FILE" 2>/dev/null || true
    fi
  else
    # In Standalone Mode (TV off / standby):
    # 1. 3-Min (180s) Inactivity -> dim LVDS-1 backlight to 0
    # Must also respect SINCE_WAKE >= 180 so stale pre-wake idle time doesn't extinguish screen on wake!
    if [ "$SINCE_WAKE" -ge 180 ] && [ "$IDLE_MS" -ge 180000 ]; then
      if [ "$BLANKED" -eq 0 ]; then
        if [ -w "$BACKLIGHT_FILE" ]; then
          echo 0 > "$BACKLIGHT_FILE" 2>/dev/null || true
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Idle 3m -> dimmed LVDS-1 backlight to 0"
        fi
        BLANKED=1
      fi
    else
      # User active in Standalone mode or within wake grace period -> ensure backlight is on
      if [ "$BLANKED" -eq 1 ] && ([ "$IDLE_MS" -lt 180000 ] || [ "$SINCE_WAKE" -lt 180 ]); then
        if [ -w "$BACKLIGHT_FILE" ]; then
          echo "$DEFAULT_BRIGHTNESS" > "$BACKLIGHT_FILE" 2>/dev/null || true
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] User active (${IDLE_MS}ms) or wake -> restored LVDS-1 backlight to $DEFAULT_BRIGHTNESS"
        fi
        BLANKED=0
      fi
    fi

    # 2. 5-Min (300s) Inactivity -> Enter S3 sleep (pm-suspend) if no audio is playing
    # Must also respect SINCE_WAKE >= 300 to avoid immediate re-suspend loop!
    if [ "$SINCE_WAKE" -ge 300 ] && [ "$IDLE_MS" -ge 300000 ] && [ "$AUDIO_PLAYING" -eq 0 ]; then
      if [ $((NOW - LAST_SUSPEND_TIME)) -ge 300 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Idle 5m (TV off & no active audio) -> entering S3 sleep (pm-suspend)..."
        sync
        sudo /usr/sbin/pm-suspend
        LAST_SUSPEND_TIME=$(date +%s)
        LAST_WAKE_OR_MODE_CHANGE=$(date +%s)
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Resumed from S3 sleep, re-aligning displays, audio and NoMachine..."
        LAST_STATE=""
        LAST_LID=""
        BLANKED=0
        xset -dpms s off s noblank 2>/dev/null || true
        if is_tv_active; then
          CURRENT_STATE="HDMI"
          set_hdmi_display
        else
          CURRENT_STATE="ANALOG"
          set_standalone_display
        fi
        LAST_STATE="$CURRENT_STATE"

        # Post-wake recovery for NoMachine
        if ! pgrep -f "/usr/NX/bin/nxd" >/dev/null 2>&1; then
          echo "[$(date '+%Y-%m-%d %H:%M:%S')] Post-wake: Pulling up NoMachine server..."
          sudo /etc/NX/nxserver --startup 2>/dev/null || true
        fi
      fi
    fi
  fi

  # Periodic Watchdog for NoMachine (every ~60s = 30 * 2s)
  CHECK_NX_COUNTER=$((CHECK_NX_COUNTER + 1))
  if [ "$CHECK_NX_COUNTER" -ge 30 ]; then
    CHECK_NX_COUNTER=0
    if ! pgrep -f "/usr/NX/bin/nxd" >/dev/null 2>&1; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Watchdog: NoMachine down, pulling up..."
      sudo /etc/NX/nxserver --startup 2>/dev/null || true
    fi
  fi

  sleep 2
done
