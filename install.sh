#!/usr/bin/env bash
# omycontroller — install.sh
#
# Automated installation and system wiring for omycontroller:
#   1. Symlinks this repository into ~/.config/omarchy/plugins/omycontroller
#   2. Configures SUPER+G keybind in ~/.config/hypr/bindings.conf
#   3. Generates ~/.local/share/applications/omycontroller.desktop
#   4. Notifies omarchy-shell to rescan plugins
#   5. Enables omycontroller in the status bar (right section)

set -euo pipefail

PLUGIN_ID="omycontroller"
KEYBIND='bind = SUPER, G, exec, omarchy-shell shell toggle '"$PLUGIN_ID"' '\''{}'\'''
MARKER="# omycontroller:gamepad"

info() { printf '\033[1;34momycontroller\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33momycontroller\033[0m %s\n' "$1"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Plugin symlink -----------------------------------------------------
PLUGINS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
TARGET_LINK="$PLUGINS_DIR/$PLUGIN_ID"

mkdir -p "$PLUGINS_DIR"
if [ "$REPO_DIR" != "$TARGET_LINK" ]; then
  ln -sfn "$REPO_DIR" "$TARGET_LINK"
  info "symlinked $REPO_DIR -> $TARGET_LINK"
else
  info "running directly inside $TARGET_LINK"
fi

# --- 2. Hyprland keybind ---------------------------------------------------
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.conf"

if [ -f "$BINDINGS" ]; then
  # Clean up legacy marker if present
  if grep -q "# quatro:gamepad" "$BINDINGS" 2>/dev/null; then
    sed -i '/^# quatro:gamepad$/,/\(quatro\.gamepad\|quatro:gamepad\)/d' "$BINDINGS" 2>/dev/null || true
  fi

  if grep -q "$MARKER" "$BINDINGS" 2>/dev/null; then
    info "keybind already present in bindings.conf"
  elif grep -qE '^\s*bind\s*=\s*\S*,\s*G\s*,' "$BINDINGS" 2>/dev/null; then
    warn "SUPER+G already bound to something else — add manually:"
    warn "  $KEYBIND"
  else
    {
      printf '\n%s\n%s\n' "$MARKER" "$KEYBIND"
    } >> "$BINDINGS"
    info "added SUPER+G toggle to $BINDINGS"
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
  fi
else
  mkdir -p "$(dirname "$BINDINGS")"
  {
    printf '%s\n%s\n' "$MARKER" "$KEYBIND"
  } > "$BINDINGS"
  info "created $BINDINGS with SUPER+G toggle"
  command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1 || true
fi

# --- 3. Desktop entry and Icon ---------------------------------------------
ICONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/hicolor/scalable/apps"
mkdir -p "$ICONS_DIR"
if [ -f "$REPO_DIR/assets/icon.svg" ]; then
  cp -f "$REPO_DIR/assets/icon.svg" "$ICONS_DIR/omycontroller.svg"
  info "icon installed: $ICONS_DIR/omycontroller.svg"
fi

APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/omycontroller.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=omycontroller
GenericName=Pro Gamepad Control Center
Comment=Gamepadla circularity radar, latency benchmark, battery, deadzones, rumble, and DualSense haptics
Exec=omarchy-shell shell toggle $PLUGIN_ID '{}'
Terminal=false
Categories=Game;Utility;Settings;
Keywords=gamepad;controller;omycontroller;gamepadla;rumble;deadzone;
Icon=omycontroller
NoDisplay=false
EOF
info "desktop entry installed: $APPS_DIR/omycontroller.desktop"

# Clean up legacy desktop entry if present
if [ -f "$APPS_DIR/quatro-gamepads.desktop" ]; then
  rm -f "$APPS_DIR/quatro-gamepads.desktop"
fi

# --- 4. Rescan and enable plugin ------------------------------------------
if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  info "notified omarchy-shell to rescan plugins"
fi

if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin enable "$PLUGIN_ID" --section right >/dev/null 2>&1 || true
  info "enabled $PLUGIN_ID in bar (section: right)"
fi

info "done. Open the deck with SUPER+G, the bar pill, or app launcher → 'omycontroller'."
