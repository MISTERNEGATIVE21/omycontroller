#!/usr/bin/env bash
# omycontroller — uninstall.sh
#
# Cleans up user-owned wiring, desktop entry, keybinding, and plugin link
# for omycontroller.

set -euo pipefail

PLUGIN_ID="omycontroller"
MARKER="# omycontroller:gamepad"
info() { printf '\033[1;34momycontroller\033[0m %s\n' "$1"; }

# --- 1. Disable plugin -----------------------------------------------------
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin disable "$PLUGIN_ID" >/dev/null 2>&1 || true
  info "disabled $PLUGIN_ID plugin"
fi

# --- 2. Keybind ------------------------------------------------------------
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.conf"
if [ -f "$BINDINGS" ]; then
  if grep -q "$MARKER" "$BINDINGS" 2>/dev/null; then
    sed -i "/^${MARKER}$/,+1d" "$BINDINGS"
    info "keybind removed from $BINDINGS"
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
  fi
  # Clean up legacy marker if present
  if grep -q "# quatro:gamepad" "$BINDINGS" 2>/dev/null; then
    sed -i "/^# quatro:gamepad$/,/\(quatro\.gamepad\|quatro:gamepad\)/d" "$BINDINGS" 2>/dev/null || true
  fi
fi

# --- 3. Desktop entry and Icon ---------------------------------------------
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
if [ -f "$APPS_DIR/omycontroller.desktop" ]; then
  rm -f "$APPS_DIR/omycontroller.desktop"
  info "desktop entry removed: $APPS_DIR/omycontroller.desktop"
fi
if [ -f "$APPS_DIR/quatro-gamepads.desktop" ]; then
  rm -f "$APPS_DIR/quatro-gamepads.desktop"
fi

ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
if [ -f "$ICONS_DIR/omycontroller.svg" ]; then
  rm -f "$ICONS_DIR/omycontroller.svg"
  info "icon removed: $ICONS_DIR/omycontroller.svg"
fi

# --- 4. Plugin folder / symlink --------------------------------------------
TARGET_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$PLUGIN_ID"
if [ -L "$TARGET_LINK" ]; then
  rm -f "$TARGET_LINK"
  info "removed symlink: $TARGET_LINK"
elif [ -d "$TARGET_LINK" ]; then
  rm -rf "$TARGET_LINK"
  info "removed directory: $TARGET_LINK"
fi

# Clean up legacy link if present
LEGACY_LINK="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/quatro.gamepad"
if [ -L "$LEGACY_LINK" ] || [ -d "$LEGACY_LINK" ]; then
  rm -rf "$LEGACY_LINK"
fi

# --- 5. Rescan plugins -----------------------------------------------------
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  info "notified omarchy-shell to rescan plugins"
fi

info "omycontroller uninstalled successfully."
