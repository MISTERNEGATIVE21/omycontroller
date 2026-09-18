# Quatro — gamepad control center for Omarchy

A Quattro shell plugin (Quickshell-based, standard Omarchy plugin contract)
that turns the Omarchy bar into a small gamepad control center: live
controller view, battery, connection mode, input protocol, real input
latency, rumble tests, DualSense adaptive triggers and per-pad deadzones —
for up to four pads (P1–P4), as the name suggests. Every joypad *and*
joystick is covered: gamepads render as their real silhouette (Xbox /
PlayStation / Switch / generic), while flight sticks, arcade sticks and
yokes get a dedicated single-stick view with a live hat switch and
throttle lever.

```
┌ QUATRO ─────────────────────────── 1 pad ─┐
│ ● P1  Xbox Series pad          87% · BT  │   ← device menu (4 slots)
│───────────────────────────────────────────│
│        [live model-accurate art]          │   ← buttons/sticks/triggers
│ ┌Mode / protocol─────┐ ┌Connection──────┐ │      light up as you press
│ │ XInput · xpadneo   │ │ Bluetooth      │ │
│ └────────────────────┘ └/dev/input/js0─┘ │
│ ┌Input latency───────┐ ┌Battery─────────┐ │
│ │ 1.4 ms · 710 Hz    │ │ 87%  healthy   │ │
│ └────────────────────┘ └────────────────┘ │
│ RUMBLE TEST   [Weak] [Strong] [Both 0.5s] │
│ ADAPTIVE TRIGGERS   L2 [Medium] R2 [Off]  │
│ DEADZONES                                 │
│  Left stick   ────●──────      12%        │
│  Right stick  ───●───────      10%        │
│  Left trigger ──●────────       5%        │
│  Right trigger ─●────────       5%        │
└───────────────────────────────────────────┘
```

## What it shows

| Data          | Source                                                                 |
|---------------|------------------------------------------------------------------------|
| Battery %     | kernel `power_supply` node bound to the pad's HID device              |
| Connection    | Wired USB / USB Dongle / Bluetooth — from bus type + device topology  |
| Mode/protocol | XInput, Switch Pro, DualSense, DInput, Steam Input… from driver+name  |
| Model + art   | Xbox / DualSense / Switch Pro / joystick / generic layout, drawn live in QML |
| Hardware      | axis + button count from the jstest header, silhouette label (gamepad vs joystick) |
| Latency       | rolling average of evdev event intervals (ms) + effective poll rate   |
| Deadzones     | per-pad profiles, persisted across replug, live preview rings         |
| Rumble        | one-shot FF_RUMBLE via evdev (weak / strong / both)                   |
| Haptics       | DualSense adaptive-trigger modes via hidraw (wired)                   |

## Install

### Standard Omarchy way (recommended)

The plugin is a plain git repo with a `manifest.json` at the root:

```bash
omarchy plugin add https://github.com/YOURNAME/omarchy-quatro.git --enable --yes
```

(or interactively: `omarchy plugin add <url>`, review the code, then enable).

Manual install:

```bash
git clone <this-repo> ~/.config/omarchy/plugins/quatro.gamepad
omarchy-shell shell rescanPlugins
omarchy plugin enable quatro.gamepad
```

The bar widget lands in the right bar section (`defaultSection`). Move it
with `omarchy bar move` or drag it on the bar.

### Entry points (all three included)

1. **Bar pill** — click the controller glyph in the bar to toggle the panel.
2. **SUPER+G** — run `install.sh` (below) to add the keybind, or add by hand:

   ```
   # ~/.config/hypr/bindings.conf
   bind = SUPER, G, exec, omarchy-shell shell toggle quatro.gamepad '{}'
   ```

3. **Fuzzel** — `install.sh` adds a `Quatro Gamepads` desktop entry.

```bash
bash ~/.config/omarchy/plugins/quatro.gamepad/install.sh
```

`install.sh` is idempotent, never uses sudo, and only touches your own
`bindings.conf` and `~/.local/share/applications/`. `uninstall.sh` reverts it.

## Optional dependencies

Quatro degrades gracefully — everything scans and displays without any
extra package; two features light up when these are present:

```bash
sudo pacman -S --needed linuxconsole python-evdev
```

- `linuxconsole` (`jstest`) — live button/axis tester + input latency
- `python-evdev` — rumble test playback

DualSense adaptive triggers need only write access to the pad's hidraw
node (wired connection recommended; the kernel driver blocks the Bluetooth
effect report from user space). Add your user to the `input` group if
writes are denied.

## Settings

Per-widget settings live inline in `~/.config/omarchy/shell.json`
(edit the widget's entry, or use `omarchy bar set`):

```json
{ "id": "quatro.gamepad", "lowBatteryThreshold": 20, "showLatency": true }
```

| Key                   | Default | Meaning                                   |
|-----------------------|---------|-------------------------------------------|
| `lowBatteryThreshold` | `15`    | % under which the pill paints urgent      |
| `showLatency`         | `true`  | latency chip + tooltip figure             |

## Architecture

```
quatro.gamepad/
├── manifest.json        plugin contract (kinds: service + bar-widget)
├── Service.qml          headless singleton: sysfs scan, jstest streams,
│                        latency math, profiles, rumble/haptics dispatch
├── BarWidget.qml        bar pill + panel lifecycle (open/close/toggle)
├── Panel.qml            popout UI: menu, live art, chips, tuning controls
├── ControllerArt.qml    theme-aware controller rendering, 5 layouts
│                        (Xbox / PS / Switch / joystick / generic)
├── GamepadModel.js      pure classification logic (driver→model/protocol)
└── scripts/
    ├── scan.sh          sysfs walk → one JSON line per pad (no deps)
    ├── rumble.py        FF_RUMBLE one-shot (python-evdev)
    └── triggers.py      DualSense adaptive-trigger hidraw writer (stdlib)
```

Design notes:

- **One process.** Everything runs inside the long-running `omarchy-shell`
  (Quattro) instance — no second Quickshell process, ever. The service kind
  keeps the scan alive while the panel is closed; the bar widget and panel
  attach to the same service through the host facade
  (`shell.serviceFor("quatro.gamepad")`, scoped to this plugin).
- **Theme tokens only.** Player colors are `Color.accent / foreground /
  urgent / muted`, surfaces come from `Color.popups.*`, spacing from
  `Style.*` — Quatro follows whatever Omarchy theme is active (Catppuccin
  Mocha by default) instead of hardcoding a palette.
- **Hot-reload friendly.** No SVG/asset plugins to register; the art is
  pure QML primitives. Saving a file under `plugins/` reloads Quatro live.
- **Honest latency.** The ms figure is the real average evdev event
  interval observed on this pad right now — not a made-up "1 ms" badge.
  Idle pads report `idle` until events flow.

## Validate / develop

```bash
omarchy plugin validate ~/.config/omarchy/plugins/quatro.gamepad
qmllint -I "$OMARCHY_PATH/shell" \
  ~/.config/omarchy/plugins/quatro.gamepad/{BarWidget,Panel,Service,ControllerArt}.qml
```

Clone-and-edit workflow works as with any Omarchy plugin:
`omarchy plugin clone quatro.gamepad` (third-party clones become
`<username>.gamepad`).

## Troubleshooting

- **Pill shows "—"** — no pads bound to a joystick node. Check
  `ls /dev/input/js*`; many pads need `xpadneo`, `xone` or work out of the
  box via `hid-*`.
- **No latency / no live art** — `jstest` missing: `pacman -S linuxconsole`,
  then it appears within one scan tick (2 s).
- **Rumble fails with a permission error** — add yourself to `input`:
  `sudo usermod -aG input $USER` (re-login), and install `python-evdev`.
- **Panel does not open from fuzzel** — ensure `omarchy-shell` is on PATH
  (it ships with Omarchy in `$OMARCHY_PATH/bin`).

## License

MIT — see `LICENSE`.
