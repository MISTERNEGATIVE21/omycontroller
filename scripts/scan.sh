#!/usr/bin/env bash
# omycontroller — scripts/scan.sh
#
# Enumerates every joystick device the kernel exposes (/dev/input/js*) and
# prints one JSON object per device on its own line:
#
#   {"id":"js0","input":"input5","event":"event22","name":"...","driver":"...",
#    "bus":"0005","vendor":"045e","product":"0b12","phys":"...",
#    "battery":{"percent":87,"status":"Discharging"},"motion":"event23"}
#
# "motion" is the companion motion-sensor evdev node (accelerometer + gyro)
# that hid-playstation / hid-sony / hid-nintendo expose as a sibling input
# device ("... Motion Sensors" / "... IMU"); empty when the pad has none.
#
# Pure sysfs walking — no required external tools. Lines are consumed by
# Service.qml with a SplitParser, so output must be newline-safe JSON only.
# Battery is best-effort: pads without a power_supply node report -1.
# OMYCONTROLLER_SYSFS or QUATRO_SYSFS overrides the sysfs root (used by tests).

set -u

SYS="${OMYCONTROLLER_SYSFS:-${QUATRO_SYSFS:-/sys}}"

emit_json() {
  # Minimal key:value string emitter; values are pre-escaped.
  printf '{"id":"%s","input":"%s","event":"%s","name":"%s","driver":"%s","bus":"%s","vendor":"%s","product":"%s","phys":"%s","percent":%s,"charging":%s,"motion":"%s","touchpad":"%s"}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}" "${13}"
}

json_escape() {
  # Escape for embedding inside a JSON string literal.
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  # Strip control characters entirely — jstest names never need them.
  s="$(printf '%s' "$s" | tr -d '\000-\037')"
  printf '%s' "$s"
}

battery_for_input() {
  # Walk up from an input class dir looking for a power_supply node that
  # hangs off the same HID/USB parent. Prints "<percent>|<status>" or "|".
  local input_dir="$1"
  local anc depth ps_dir capacity status
  anc="$input_dir"
  for depth in 1 2 3 4 5; do
    anc="$(dirname "$anc")"
    [ "$anc" = "/" ] && break
    for ps_dir in "$anc"/power_supply/*; do
      [ -d "$ps_dir" ] || continue
      capacity="$(cat "$ps_dir/capacity" 2>/dev/null || true)"
      case "$capacity" in ''|*[!0-9]*) continue ;; esac
      status="$(cat "$ps_dir/status" 2>/dev/null || printf 'Unknown')"
      printf '%s|%s' "$capacity" "$status"
      return 0
    done
  done
  printf '|'
}

shopt -s nullglob

for js in "$SYS"/class/input/js*; do
  id="$(basename "$js")"
  # Validate id must strictly be jsN
  case "$id" in
    js[0-9]*) ;;
    *) continue ;;
  esac

  dev_dir="$js/device"                 # .../inputX  (joystick char dev)
  parent="$dev_dir/device"             # .../inputX/device (hardware node)

  name="$(cat "$dev_dir/name" 2>/dev/null || printf '')"
  [ -n "$name" ] || name="$(cat "$parent/name" 2>/dev/null || printf '%s' "$id")"

  driver="?"
  if [ -L "$parent/driver" ] || [ -d "$parent/driver" ]; then
    driver="$(basename "$(readlink -f "$parent/driver" 2>/dev/null || printf '?')")"
  fi

  bustype="$(cat "$dev_dir/id/bustype" 2>/dev/null || cat "$parent/id/bustype" 2>/dev/null || printf '0000')"
  vendor="$(cat "$dev_dir/id/vendor" 2>/dev/null || cat "$parent/id/vendor" 2>/dev/null || printf '0000')"
  product="$(cat "$dev_dir/id/product" 2>/dev/null || cat "$parent/id/product" 2>/dev/null || printf '0000')"
  phys="$(cat "$dev_dir/phys" 2>/dev/null || cat "$parent/phys" 2>/dev/null || printf '')"
  phys="$(basename "$phys" 2>/dev/null || printf '')"

  # Detect USB parent device details (useful for 2.4G wireless dongles/adapters where xpad
  # overrides controller name to generic "Microsoft X-Box 360 pad")
  usb_parent="$parent"
  case "$usb_parent" in
    *:*.*) usb_parent="$(dirname "$usb_parent")" ;;
  esac
  usb_mfr="$(cat "$usb_parent/manufacturer" 2>/dev/null || printf '')"
  usb_prod="$(cat "$usb_parent/product" 2>/dev/null || printf '')"

  if [ -n "$usb_mfr" ] && [ "$usb_mfr" != "Microsoft" ] && [ "$vendor" = "045e" ] && [ "$product" = "028e" ]; then
    name="$usb_mfr $usb_prod (Wireless Receiver)"
  elif [ -n "$usb_prod" ]; then
    case "$usb_prod" in
      *[Rr]eceiver*|*[Dd]ongle*|*[Aa]dapter*)
        case "$name" in
          *[Rr]eceiver*|*[Dd]ongle*|*[Aa]dapter*) ;;
          *) name="$name ($usb_prod)" ;;
        esac
        ;;
    esac
  fi

  input_name="$(basename "$(readlink -f "$dev_dir" 2>/dev/null || printf '')" 2>/dev/null || printf '')"
  case "$input_name" in
    input[0-9]*) ;;
    *) input_name="" ;;
  esac

  # Matching evdev node — required for rumble/trigger control.
  event=""
  for ev in "$dev_dir"/event*; do
    [ -d "$ev" ] || continue
    ev_base="$(basename "$ev")"
    case "$ev_base" in
      event[0-9]*) event="$ev_base"; break ;;
    esac
  done

  # Companion motion-sensor node (gyro + accelerometer), paired by HID
  # parent: hid-playstation/hid-sony/hid-nintendo expose it as a sibling
  # input device named "... Motion Sensors" / "... IMU".
  motion=""
  touchpad=""
  for sib in "$parent"/input/input* "$parent"/input* "$parent"/../input*; do
    [ -d "$sib" ] || continue
    sib_name="$(cat "$sib/name" 2>/dev/null || printf '')"
    sib_name_lower="$(printf '%s' "$sib_name" | tr '[:upper:]' '[:lower:]')"
    if [ -z "$motion" ]; then
      case "$sib_name_lower" in
        *motion*|*imu*|*gyro*|*accelerometer*|*accel*)
          for ev in "$sib"/event*; do
            [ -d "$ev" ] || continue
            ev_base="$(basename "$ev")"
            case "$ev_base" in
              event[0-9]*) motion="$ev_base"; break ;;
            esac
          done
          ;;
      esac
    fi
    if [ -z "$touchpad" ]; then
      case "$sib_name_lower" in
        *touchpad*|*trackpad*)
          for ev in "$sib"/event*; do
            [ -d "$ev" ] || continue
            ev_base="$(basename "$ev")"
            case "$ev_base" in
              event[0-9]*) touchpad="$ev_base"; break ;;
            esac
          done
          ;;
      esac
    fi
    [ -n "$motion" ] && [ -n "$touchpad" ] && break
  done

  raw_battery="$(battery_for_input "$(readlink -f "$dev_dir" 2>/dev/null || printf '')")"
  IFS='|' read -r percent status <<<"$raw_battery"
  case "$percent" in
    ''|*[!0-9]*) percent=-1 ;;
  esac
  charging="false"
  case "$status" in
    Charging|Full) charging="true" ;;
  esac

  emit_json \
    "$(json_escape "$id")" \
    "$(json_escape "$input_name")" \
    "$(json_escape "$event")" \
    "$(json_escape "$name")" \
    "$(json_escape "$driver")" \
    "$(json_escape "$bustype")" \
    "$(json_escape "$vendor")" \
    "$(json_escape "$product")" \
    "$(json_escape "$phys")" \
    "$percent" \
    "$charging" \
    "$(json_escape "$motion")" \
    "$(json_escape "$touchpad")"
done

# Check if a 2.4G wireless receiver is connected in standby/pairing mode without an active pad node
for dev in "$SYS"/bus/usb/devices/*; do
  [ -f "$dev/idVendor" ] || continue
  v="$(cat "$dev/idVendor" 2>/dev/null || printf '')"
  p="$(cat "$dev/idProduct" 2>/dev/null || printf '')"
  prod="$(cat "$dev/product" 2>/dev/null || printf '')"
  case "$v:$p" in
    1a34:f517)
      printf '{"id":"dongle_standby","status":"standby","name":"ZhiXu / EasySMX Wireless Receiver","vendor":"%s","product":"%s"}\n' "$v" "$p"
      break
      ;;
  esac
  case "$prod" in
    *"Receiver Update"*|*"Wireless Receiver Standby"*)
      printf '{"id":"dongle_standby","status":"standby","name":"%s","vendor":"%s","product":"%s"}\n' "$(json_escape "$prod")" "$v" "$p"
      break
      ;;
  esac
done

exit 0
