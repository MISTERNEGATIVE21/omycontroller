#!/usr/bin/env bash
# Quatro — install.sh
#
# Optional convenience wiring AFTER the plugin is installed and enabled
# through the standard Omarchy plugin commands. It never runs plugin code,
# never uses sudo, and only touches user-owned config files:
#
#   1. SUPER+G keybind → toggles the Quatro panel (bindings.conf)
#   2. "Quatro Gamepads" fuzzel desktop entry
#
# The plugin itself is installed with:
#   omarchy plugin add <this-repo-url> --enable --yes
#   # or by hand: copy to ~/.config/omarchy/plugins/quatro.gamepad/, then
#   omarchy-shell shell rescanPlugins && omarchy plugin enable quatro.gamepad

set -euo pipefail

PLUGIN_ID="quatro.gamepad"
KEYBIND='bind = SUPER, G, exec, omarchy-shell shell toggle '"$PLUGIN_ID"' '\''{}'\'''
MARKER="# quatro:gamepad"

info() { printf '\033[1;34mquatro\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mquatro\033[0m %s\n' "$1"; }

# --- 1. Hyprland keybind ---------------------------------------------------
BINDINGS="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.conf"

if [ -f "$BINDINGS" ]; then
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
  warn "no bindings.conf found — add this keybind manually:"
  warn "  $KEYBIND"
fi

# --- 2. Fuzzel desktop entry ------------------------------------------------
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$APPS_DIR"
cat > "$APPS_DIR/quatro-gamepads.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Quatro Gamepads
GenericName=Gamepad Control Center
Comment=Battery, latency, deadzones, rumble and haptics for your controllers
Exec=omarchy-shell shell toggle $PLUGIN_ID '{}'
Terminal=false
Categories=Game;Utility;Settings;
Keywords=gamepad;controller;quatro;rumble;deadzone;
Icon=applications-games
NoDisplay=false
EOF
info "fuzzel entry installed: $APPS_DIR/quatro-gamepads.desktop"

info "done. Open the panel with SUPER+G, the bar pill, or fuzzel → 'Quatro Gamepads'."
