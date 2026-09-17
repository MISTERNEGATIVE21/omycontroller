#!/usr/bin/env bash
# Quatro — uninstall.sh
#
# Removes only the user-owned wiring install.sh created. The plugin folder
# itself is removed through the standard Omarchy command:
#
#   omarchy plugin remove quatro.gamepad

set -euo pipefail

PLUGIN_ID="quatro.gamepad"
MARKER="# quatro:gamepad"
info() { printf '\033[1;34mquatro\033[0m %s\n' "$1"; }

# Keybind
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.conf"
if [ -f "$BINDINGS" ] && grep -q "$MARKER" "$BINDINGS"; then
  sed -i "/^${MARKER}$/,+1d" "$BINDINGS"
  info "keybind removed from $BINDINGS"
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

# Fuzzel entry
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
if [ -f "$APPS_DIR/quatro-gamepads.desktop" ]; then
  rm -f "$APPS_DIR/quatro-gamepads.desktop"
  info "fuzzel entry removed"
fi

info "plugin folder (if installed via omarchy): omarchy plugin remove $PLUGIN_ID"
