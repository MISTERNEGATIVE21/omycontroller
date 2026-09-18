#!/usr/bin/env bash
# tests/scan.test.sh — Validates scripts/scan.sh against mock sysfs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCAN_SH="$REPO_DIR/scripts/scan.sh"

if [ ! -f "$SCAN_SH" ]; then
  echo "Error: $SCAN_SH not found" >&2
  exit 1
fi

MOCK_SYS="$(mktemp -d /tmp/omycontroller-sysfs-mock.XXXXXX)"
trap 'rm -rf "$MOCK_SYS"' EXIT

# -----------------------------------------------------------------------------
# Setup Mock Device 1: Bluetooth Xbox Wireless Controller (js0, input5, event22)
# With motion sensor (event23) and battery (85%, Discharging)
# -----------------------------------------------------------------------------
DEV1_PARENT="$MOCK_SYS/devices/pci0000:00/0000:00:14.0/bluetooth/hci0/hci0:1/0005:045E:0B12.0001"
DEV1_INPUT="$DEV1_PARENT/input/input5"
DEV1_MOTION="$DEV1_PARENT/input/input6"
DEV1_PS="$DEV1_PARENT/power_supply/battery"

mkdir -p "$DEV1_PARENT/id" "$DEV1_INPUT/event22" "$DEV1_MOTION/event23" "$DEV1_PS"
printf '0005' > "$DEV1_PARENT/id/bustype"
printf '045e' > "$DEV1_PARENT/id/vendor"
printf '0b12' > "$DEV1_PARENT/id/product"
printf 'Xbox Wireless Controller\n' > "$DEV1_PARENT/name"
printf 'e4:17:d8:12:34:56\n' > "$DEV1_PARENT/phys"

# Driver symlink
mkdir -p "$MOCK_SYS/bus/hid/drivers/xpadneo"
ln -sfn "$MOCK_SYS/bus/hid/drivers/xpadneo" "$DEV1_PARENT/driver"

# Input nodes
printf 'Xbox Wireless Controller\n' > "$DEV1_INPUT/name"
ln -sfn "$DEV1_PARENT" "$DEV1_INPUT/device"

# Motion companion input node
printf 'Xbox Wireless Controller Motion Sensors\n' > "$DEV1_MOTION/name"
ln -sfn "$DEV1_PARENT" "$DEV1_MOTION/device"

# Power supply
printf '85\n' > "$DEV1_PS/capacity"
printf 'Discharging\n' > "$DEV1_PS/status"

# Class input registration for js0
mkdir -p "$MOCK_SYS/class/input/js0"
ln -sfn "$DEV1_INPUT" "$MOCK_SYS/class/input/js0/device"

# -----------------------------------------------------------------------------
# Setup Mock Device 2: Wired DualSense Controller (js1, input8, event15)
# No motion sensor companion, charging battery (100%, Full)
# -----------------------------------------------------------------------------
DEV2_PARENT="$MOCK_SYS/devices/pci0000:00/0000:00:14.0/usb1/1-1/1-1:1.0/0003:054C:0CE6.0002"
DEV2_INPUT="$DEV2_PARENT/input/input8"
DEV2_PS="$DEV2_PARENT/power_supply/ps-controller-battery"

mkdir -p "$DEV2_PARENT/id" "$DEV2_INPUT/event15" "$DEV2_PS"
printf '0003' > "$DEV2_PARENT/id/bustype"
printf '054c' > "$DEV2_PARENT/id/vendor"
printf '0ce6' > "$DEV2_PARENT/id/product"
printf 'Sony Interactive Entertainment Wireless Controller\n' > "$DEV2_PARENT/name"
printf 'usb-0000:00:14.0-1/input0\n' > "$DEV2_PARENT/phys"

mkdir -p "$MOCK_SYS/bus/hid/drivers/hid-playstation"
ln -sfn "$MOCK_SYS/bus/hid/drivers/hid-playstation" "$DEV2_PARENT/driver"

printf 'Sony Interactive Entertainment Wireless Controller\n' > "$DEV2_INPUT/name"
ln -sfn "$DEV2_PARENT" "$DEV2_INPUT/device"

printf '100\n' > "$DEV2_PS/capacity"
printf 'Full\n' > "$DEV2_PS/status"

mkdir -p "$MOCK_SYS/class/input/js1"
ln -sfn "$DEV2_INPUT" "$MOCK_SYS/class/input/js1/device"

# -----------------------------------------------------------------------------
# Execute scan.sh with OMYCONTROLLER_SYSFS
# -----------------------------------------------------------------------------
echo "Testing scripts/scan.sh against mock sysfs..."
OUTPUT="$(OMYCONTROLLER_SYSFS="$MOCK_SYS" bash "$SCAN_SH")"

if [ -z "$OUTPUT" ]; then
  echo "FAIL: No output returned from scan.sh" >&2
  exit 1
fi

# Verify JSON structure and fields using node
node -e '
const fs = require("fs");
const lines = process.argv[1].trim().split("\n").filter(Boolean);
if (lines.length !== 2) {
  console.error(`Expected 2 device entries, got ${lines.length}`);
  process.exit(1);
}

const devices = lines.map(line => {
  try {
    return JSON.parse(line);
  } catch (err) {
    console.error("Invalid JSON line:", line);
    process.exit(1);
  }
});

const js0 = devices.find(d => d.id === "js0");
const js1 = devices.find(d => d.id === "js1");

if (!js0) {
  console.error("Missing js0 in scan output");
  process.exit(1);
}

// Verify js0 fields
const expectedJs0 = {
  id: "js0",
  input: "input5",
  event: "event22",
  name: "Xbox Wireless Controller",
  driver: "xpadneo",
  bus: "0005",
  vendor: "045e",
  product: "0b12",
  motion: "event23",
  percent: 85,
  charging: false
};

for (const [key, val] of Object.entries(expectedJs0)) {
  if (js0[key] !== val) {
    console.error(`js0 mismatch for ${key}: expected ${val} (${typeof val}), got ${js0[key]} (${typeof js0[key]})`);
    process.exit(1);
  }
}

if (!js1) {
  console.error("Missing js1 in scan output");
  process.exit(1);
}

// Verify js1 fields
const expectedJs1 = {
  id: "js1",
  input: "input8",
  event: "event15",
  name: "Sony Interactive Entertainment Wireless Controller",
  driver: "hid-playstation",
  bus: "0003",
  vendor: "054c",
  product: "0ce6",
  motion: "",
  percent: 100,
  charging: true
};

for (const [key, val] of Object.entries(expectedJs1)) {
  if (js1[key] !== val) {
    console.error(`js1 mismatch for ${key}: expected ${val} (${typeof val}), got ${js1[key]} (${typeof js1[key]})`);
    process.exit(1);
  }
}

console.log("All JSON fields verified successfully for js0 and js1!");
' "$OUTPUT"

# Test backward compatibility with QUATRO_SYSFS
QUATRO_OUT="$(QUATRO_SYSFS="$MOCK_SYS" bash "$SCAN_SH")"
if [ "$OUTPUT" != "$QUATRO_OUT" ]; then
  echo "FAIL: QUATRO_SYSFS output did not match OMYCONTROLLER_SYSFS output" >&2
  exit 1
fi

echo "scan.test.sh: PASS"
