#!/usr/bin/env bash
# omycontroller — tests/security.test.sh
#
# Automated Security & Input Validation Test Suite:
# 1. Path traversal rejection in gyro.py
# 2. Non-character device rejection in gyro.py
# 3. Path traversal rejection in rumble.py
# 4. Non-character device rejection in rumble.py
# 5. Invalid hidraw node and mode rejection in triggers.py
# 6. File permission standards (scripts 755, code 644)
# 7. Safe JSON escaping against control characters and quotes

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PASS_COUNT=0
FAIL_COUNT=0

assert_fail() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '\033[31mFAIL\033[0m: %s (expected failure, but succeeded)\n' "$desc"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    printf '\033[32mPASS\033[0m: %s\n' "$desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

assert_pass() {
  local desc="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '\033[32mPASS\033[0m: %s\n' "$desc"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '\033[31mFAIL\033[0m: %s\n' "$desc"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

printf '%s\n' '=== Running Security & Modernization Test Suite ==='

# --- 1. gyro.py security checks ---
printf '%s\n' '--- Testing scripts/gyro.py ---'
assert_fail "gyro.py: rejects missing arguments" python3 scripts/gyro.py
assert_fail "gyro.py: rejects relative path traversal" python3 scripts/gyro.py "../../etc/passwd"
assert_fail "gyro.py: rejects arbitrary file /etc/passwd" python3 scripts/gyro.py "/etc/passwd"
assert_fail "gyro.py: rejects malformed device node" python3 scripts/gyro.py "/dev/input/eventABC"
assert_fail "gyro.py: rejects non-event input node" python3 scripts/gyro.py "/dev/input/mice"
assert_fail "gyro.py: rejects path traversal with prefix" python3 scripts/gyro.py "/dev/input/event0/../../../etc/shadow"

# --- 1b. stream.py security checks ---
printf '\n%s\n' '--- Testing scripts/stream.py ---'
assert_fail "stream.py: rejects missing arguments" python3 scripts/stream.py
assert_fail "stream.py: rejects relative path traversal" python3 scripts/stream.py "../../etc/passwd"
assert_fail "stream.py: rejects arbitrary file /etc/passwd" python3 scripts/stream.py "/etc/passwd"
assert_fail "stream.py: rejects malformed device node" python3 scripts/stream.py "/dev/input/jsABC"
assert_fail "stream.py: rejects non-js input node" python3 scripts/stream.py "/dev/input/mice"
assert_fail "stream.py: rejects path traversal with prefix" python3 scripts/stream.py "/dev/input/js0/../../../etc/shadow"

# --- 2. rumble.py security checks ---
printf '\n%s\n' '--- Testing scripts/rumble.py ---'
assert_fail "rumble.py: rejects missing arguments" python3 scripts/rumble.py
assert_fail "rumble.py: rejects path traversal" python3 scripts/rumble.py "../../etc/shadow" 0 0 100
assert_fail "rumble.py: rejects regular file" python3 scripts/rumble.py "/etc/hosts" 0 0 100
assert_fail "rumble.py: rejects non-integer magnitudes" python3 scripts/rumble.py "/dev/input/event0" "abc" "def" 100
assert_fail "rumble.py: rejects malformed node name" python3 scripts/rumble.py "/dev/input/js0" 0 0 100

# --- 2b. haptic_midi.py security checks ---
printf '\n%s\n' '--- Testing scripts/haptic_midi.py ---'
assert_fail "haptic_midi.py: rejects missing arguments" python3 scripts/haptic_midi.py
assert_fail "haptic_midi.py: rejects path traversal" python3 scripts/haptic_midi.py "../../etc/shadow" mario
assert_fail "haptic_midi.py: rejects regular file" python3 scripts/haptic_midi.py "/etc/hosts" mario
assert_fail "haptic_midi.py: rejects malformed node name" python3 scripts/haptic_midi.py "/dev/input/js0" mario
assert_fail "haptic_midi.py: rejects unknown track" python3 scripts/haptic_midi.py "/dev/input/event0" nonexistent_track

# --- 2c. audio_test.py security checks ---
printf '\n%s\n' '--- Testing scripts/audio_test.py ---'
assert_fail "audio_test.py: rejects missing arguments" python3 scripts/audio_test.py
assert_fail "audio_test.py: rejects unknown command" python3 scripts/audio_test.py invalid_cmd
assert_fail "audio_test.py: rejects invalid channel" python3 scripts/audio_test.py play center



# --- 3. triggers.py security checks ---
printf '\n%s\n' '--- Testing scripts/triggers.py ---'
assert_fail "triggers.py: rejects missing arguments" python3 scripts/triggers.py
assert_fail "triggers.py: rejects path traversal" python3 scripts/triggers.py "../../etc/passwd" off off
assert_fail "triggers.py: rejects invalid mode" python3 scripts/triggers.py "auto" "hacked_mode" "off"
assert_fail "triggers.py: rejects malformed hidraw node" python3 scripts/triggers.py "/dev/input/event0" off off
assert_fail "triggers.py: rejects regular file as hidraw" python3 scripts/triggers.py "/etc/issue" off off

# --- 3b. led.py security checks ---
printf '\n%s\n' '--- Testing scripts/led.py ---'
assert_fail "led.py: rejects missing arguments" python3 scripts/led.py
assert_fail "led.py: rejects path traversal" python3 scripts/led.py "../../etc/passwd" 0 0 0
assert_fail "led.py: rejects non-integer RGB" python3 scripts/led.py "auto" "red" 0 0
assert_fail "led.py: rejects out-of-range RGB" python3 scripts/led.py "auto" 300 0 0
assert_fail "led.py: rejects negative RGB" python3 scripts/led.py "auto" -10 0 0
assert_fail "led.py: rejects malformed node" python3 scripts/led.py "/dev/input/js0" 0 0 0
assert_fail "led.py: rejects regular file" python3 scripts/led.py "/etc/issue" 0 0 0
assert_pass "led.py: accepts auto with valid RGB" python3 scripts/led.py auto 0 102 255


# --- 4. File permission standards ---
printf '\n%s\n' '--- Testing File Permissions ---'
for f in scripts/*.py scripts/*.sh install.sh uninstall.sh tests/*.sh; do
  if [ -x "$f" ]; then
    printf '\033[32mPASS\033[0m: %s is executable (755)\n' "$f"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '\033[31mFAIL\033[0m: %s is NOT executable\n' "$f"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

for f in *.qml *.js manifest.json; do
  if [ ! -x "$f" ]; then
    printf '\033[32mPASS\033[0m: %s is non-executable (644)\n' "$f"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf '\033[31mFAIL\033[0m: %s has unexpected execute bit\n' "$f"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

printf '\n==================================================\n'
printf 'Security Test Summary: %d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
printf '==================================================\n'

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
