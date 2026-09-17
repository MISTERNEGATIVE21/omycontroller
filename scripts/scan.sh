#!/usr/bin/env bash
# Quatro — scripts/scan.sh
#
# Enumerates every joystick device the kernel exposes (/dev/input/js*) and
# prints one JSON object per device on its own line:
#
#   {"id":"js0","input":"input5","event":"event22","name":"...","driver":"...",
#    "bus":"0005","vendor":"045e","product":"0b12","phys":"...",
#    "battery":{"percent":87,"status":"Discharging"}}
#
# Pure sysfs walking — no required external tools. Lines are consumed by
# Service.qml with a SplitParser, so output must be newline-safe JSON only.
# Battery is best-effort: pads without a power_supply node report -1.

set -u

emit_json() {
  # Minimal key:value string emitter; values are pre-escaped.
  printf '{"id":"%s","input":"%s","event":"%s","name":"%s","driver":"%s","bus":"%s","vendor":"%s","product":"%s","phys":"%s","percent":%s,"charging":%s}\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}"
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

for js in /sys/class/input/js*; do
  id="$(basename "$js")"
  dev_dir="$js/device"                 # .../inputX  (joystick char dev)
  parent="$dev_dir/device"             # .../inputX/device (hardware node)

  name="$(cat "$dev_dir/name" 2>/dev/null || printf '')"
  [ -n "$name" ] || name="$(cat "$parent/name" 2>/dev/null || printf '%s' "$id")"

  driver="?"
  if [ -L "$parent/driver" ]; then
    driver="$(basename "$(readlink -f "$parent/driver")")"
  fi

  bustype="$(cat "$parent/id/bustype" 2>/dev/null || printf '0000')"
  vendor="$(cat "$parent/id/vendor" 2>/dev/null || printf '0000')"
  product="$(cat "$parent/id/product" 2>/dev/null || printf '0000')"
  phys="$(cat "$parent/phys" 2>/dev/null || printf '')"
  phys="$(basename "$phys" 2>/dev/null || printf '')"

  input_name="$(basename "$(readlink -f "$dev_dir")" 2>/dev/null || printf '')"

  # Matching evdev node — required for rumble/trigger control.
  event=""
  for ev in "$dev_dir"/event*; do
    [ -d "$ev" ] || continue
    event="$(basename "$ev")"
    break
  done

  IFS='|' read -r percent status <<<"$(battery_for_input "$(readlink -f "$dev_dir")")"
  [ -n "$percent" ] || percent=-1
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
    "$charging"
done

exit 0
