// Quatro — GamepadModel.js
//
// Pure functions that turn raw kernel facts (device name, evdev driver,
// bustype, vendor/product ids) into the presentation model the panel and
// bar widget render: which physical model a pad is, which input protocol /
// mode it is currently speaking, and how it is linked to the machine
// (wired USB, wireless USB dongle, or Bluetooth).
//
// Everything here is side-effect free so it stays trivially testable and
// safe to import from both the service and the UI components.

var KNOWN_DONGLES = [
  "receiver", "dongle", "adapter", "wireless adapter",
  "xbox one pads", "8bitdo usb", "wireless receiver"
]

// Vendor ids observed on consumer controllers (USB hid quirks aside they
// also show up over Bluetooth HID on many pads).
var VENDORS = {
  "045e": "Microsoft",
  "054c": "Sony",
  "057e": "Nintendo",
  "1532": "Razer",
  "0f0d": "HORI",
  "20d6": "PowerA",
  "2dc8": "8BitDo",
  "0e6f": "PDP",
  "056e": "Elecom",
  "0079": "Generic USB pad"
}

function lower(s) {
  return String(s || "").toLowerCase()
}

function looksLikeDongle(name, phys) {
  var hay = lower(name) + " " + lower(phys)
  for (var i = 0; i < KNOWN_DONGLES.length; i++) {
    if (hay.indexOf(KNOWN_DONGLES[i]) !== -1) return true
  }
  return false
}

// ---------------------------------------------------------------------------
// Model + protocol classification
//
// Returns:
//   {
//     layout:    "xbox" | "ps" | "switch" | "generic"   (drives the art)
//     modelLabel:          e.g. "DualSense", "Xbox pad", "Switch Pro pad"
//     protocol:            e.g. "XInput", "Switch Pro", "DualSense"
//     driverNote:          kernel driver actually bound, e.g. "xpadneo"
//     maker:               vendor string when known
//   }
// ---------------------------------------------------------------------------
function classify(name, driver, vendor, product) {
  var n = lower(name)
  var d = lower(driver)
  var v = lower(vendor)
  var out = {
    layout: "generic",
    modelLabel: String(name || "Gamepad"),
    protocol: "HID",
    driverNote: String(driver || "hid-generic"),
    maker: VENDORS[v] || ""
  }

  // Sony ---------------------------------------------------------------
  if (d === "hid-playstation" || n.indexOf("wiimote") === 0) {
    // hid-playstation covers both DualShock 4 and DualSense.
    if (n.indexOf("dualsense") !== -1 || n.indexOf("wireless controller") !== -1) {
      out.layout = "ps"
      out.modelLabel = n.indexOf("edge") !== -1 ? "DualSense Edge" : "DualSense"
      out.protocol = "DualSense"
    } else if (n.indexOf("wireless controller") !== -1 || n.indexOf("dualshock") !== -1) {
      out.layout = "ps"
      out.modelLabel = "DualShock 4"
      out.protocol = "DualShock 4"
    } else {
      out.layout = "ps"
      out.protocol = "PS HID"
    }
    return out
  }

  // Nintendo -----------------------------------------------------------
  if (d === "hid-nintendo" || n.indexOf("nintendo switch") !== -1 ||
      n.indexOf("pro controller") !== -1 || n.indexOf("joy-con") !== -1) {
    out.layout = "switch"
    out.modelLabel = n.indexOf("joy-con") !== -1 ? "Joy-Cons" : "Switch Pro pad"
    out.protocol = "Nintendo Switch"
    return out
  }

  // Xbox-family drivers --------------------------------------------------
  if (d === "xpadneo" || d === "hid-microsoft" || d === "xpad" ||
      d === "xone" || n.indexOf("xbox") !== -1 || v === "045e") {
    out.layout = "xbox"
    if (d === "xpadneo") out.protocol = "XInput"
    else if (d === "xpad") out.protocol = "XInput"
    else if (d === "xone") out.protocol = "XInput (xone)"
    else out.protocol = "XInput"
    if (n.indexOf("series") !== -1) out.modelLabel = "Xbox Series pad"
    else if (n.indexOf("360") !== -1) out.modelLabel = "Xbox 360 pad"
    else out.modelLabel = "Xbox pad"
    return out
  }

  // Steam ----------------------------------------------------------------
  if (n.indexOf("steam") !== -1) {
    out.layout = "xbox"
    out.protocol = "Steam Input"
    out.maker = "Valve"
    return out
  }

  // 8BitDo and friends — mode often leaks into the product string --------
  if (n.indexOf("8bitdo") !== -1 || v === "2dc8") {
    out.maker = "8BitDo"
    if (n.indexOf("switch") !== -1 || n.indexOf("sfc30") !== -1 || n.indexOf("sn30") !== -1) {
      out.layout = "switch"
      out.protocol = "Switch mode"
    } else if (n.indexOf("xinput") !== -1 || n.indexOf("x-box") !== -1) {
      out.layout = "xbox"
      out.protocol = "XInput mode"
    } else if (n.indexOf("dinput") !== -1) {
      out.layout = "generic"
      out.protocol = "DInput mode"
    } else {
      out.layout = "xbox"
      out.protocol = "HID gamepad"
    }
    out.modelLabel = String(name || "8BitDo pad")
    return out
  }

  // Everything else — keep the maker string short and honest --------------
  if (n.indexOf("gamepad") !== -1 || n.indexOf("controller") !== -1 || n.indexOf("joystick") !== -1) {
    out.protocol = "HID gamepad"
  }
  return out
}

// ---------------------------------------------------------------------------
// Link classification. bustype comes from the kernel input id:
//   0x0003 = USB, 0x0005 = Bluetooth, 0x0011 = virtual, ...
// ---------------------------------------------------------------------------
function connection(bustype, name, phys) {
  var bt = String(bustype || "").toLowerCase()
  if (bt === "0005" || bt === "bluetooth" || bt === "0005 ") return "Bluetooth"
  var n = lower(name)
  if (n.indexOf("bluetooth") !== -1 || n.indexOf(" bt ") !== -1 || n.indexOf(" wireless") !== -1) {
    // Wireless pads that ride a vendor dongle name themselves "wireless";
    // the dongle check below wins because it runs first for receivers.
    if (looksLikeDongle(name, phys)) return "USB Dongle"
    return "Bluetooth"
  }
  if (looksLikeDongle(name, phys)) return "USB Dongle"
  return "Wired USB"
}

function connectionShort(conn) {
  if (conn === "Bluetooth") return "BT"
  if (conn === "USB Dongle") return "Dongle"
  if (conn === "Wired USB") return "USB"
  return conn
}

// ---------------------------------------------------------------------------
// Battery bucket → color token consumed by the UI (token names match the
// Omarchy Color singleton roles, no hex leaks into components).
// ---------------------------------------------------------------------------
function batteryBucket(percent, threshold) {
  if (percent === null || percent === undefined || percent < 0) return "unknown"
  if (percent <= threshold) return "low"
  if (percent <= 35) return "warn"
  return "ok"
}

// Text color for a battery figure. Tokens come from the shell theme
// singleton (passed in as `C`), so Quatro tracks every Omarchy theme.
function batteryText(foreground, C, percent, threshold) {
  var bucket = batteryBucket(percent, threshold)
  if (bucket === "low") return C.urgent
  if (bucket === "warn") return C.accent
  if (bucket === "unknown") return Qt.darker(foreground, 1.4)
  return foreground
}

// Quatro player palette. Deliberately theme-token based (accent, foreground,
// urgent, muted) instead of hardcoded hex — on Catppuccin Mocha P1 reads as
// blue, P2 white, P3 red, P4 gray; on any other theme it stays coherent.
function playerColor(slot, C) {
  switch (Number(slot)) {
    case 1: return C.accent
    case 2: return C.foreground
    case 3: return C.urgent
    case 4: return C.muted
    default: return C.accent
  }
}

function batteryLabel(percent, charging) {
  if (percent === null || percent === undefined || percent < 0) return "—"
  var base = percent + "%"
  return charging ? base + " ⚡" : base
}

// ---------------------------------------------------------------------------
// Latency formatting. The service feeds a rolling average of evdev event
// intervals in milliseconds plus an events-per-second figure.
// ---------------------------------------------------------------------------
function latencyLabel(avgMs, eps) {
  if (avgMs === null || avgMs === undefined || !isFinite(avgMs) || avgMs <= 0) return "idle"
  var ms = avgMs < 10 ? avgMs.toFixed(1) : Math.round(avgMs)
  var rate = eps >= 1000 ? Math.round(eps / 1000) + " kHz" : Math.round(eps) + " Hz"
  return ms + " ms · " + rate
}

// ---------------------------------------------------------------------------
// Deadzone profiles. Keys must survive replug, so they are built from
// vendor+product+name rather than the volatile jsN index.
// ---------------------------------------------------------------------------
function profileKey(vendor, product, name) {
  var raw = String(vendor || "????") + ":" + String(product || "????") + ":" + String(name || "pad")
  return raw.replace(/[^A-Za-z0-9._:+-]/g, "_")
}

var DEFAULT_PROFILE = {
  stickL: 0.10,
  stickR: 0.10,
  trigL: 0.05,
  trigR: 0.05
}

function normalizeProfile(p) {
  var out = {}
  var src = (p && typeof p === "object") ? p : {}
  var keys = ["stickL", "stickR", "trigL", "trigR"]
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i]
    var n = Number(src[k])
    out[k] = isFinite(n) ? Math.min(0.5, Math.max(0, n)) : DEFAULT_PROFILE[k]
  }
  return out
}

// Apply a radial deadzone to a normalized stick vector (-1..1). Returns the
// corrected vector so the live art mirrors what games actually receive when
// the correction is enforced in hardware (xpadneo) or by a shim.
function applyStickDeadzone(x, y, dz) {
  var mag = Math.sqrt(x * x + y * y)
  if (mag <= dz || mag === 0) return { x: 0, y: 0 }
  var scaled = (mag - dz) / (1 - dz)
  var factor = scaled / mag
  return { x: x * factor, y: y * factor }
}

// ---------------------------------------------------------------------------
// Button tables — js button index per art element, following the kernel
// drivers' common order (xpad/xpadneo, hid-playstation, hid-nintendo).
// A -1 means "no analog axis" or "no button" for that element; the art
// degrades gracefully (body outline flashes for unmapped indices).
// ---------------------------------------------------------------------------
function buttonTables(layout) {
  if (layout === "xbox") {
    // xpad / xpadneo: A0 B1 X2 Y3, LB4 RB5, back6 start7 guide8,
    // TL9 TR10, dpad 11..14
    return {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 4, bumperR: 5,
      stickL: 9, stickR: 10,
      dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
      centerTop: 8, centerLeft: 6, centerRight: 7, centerExtra: -1,
      triggerL: -1, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    }
  }
  if (layout === "ps") {
    // hid-playstation: ×0 ○1 □2 △3, create4 options5 PS6 touchpad7,
    // L3 8, R3 9, L1 10, R1 11
    return {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 10, bumperR: 11,
      stickL: 8, stickR: 9,
      dpadUp: 12, dpadDown: 13, dpadLeft: 14, dpadRight: 15,
      centerTop: 6, centerLeft: 4, centerRight: 5, centerExtra: 7,
      triggerL: -1, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    }
  }
  if (layout === "switch") {
    // hid-nintendo pro: B0 A1 Y2 X3, L4 R5, ZL6 ZR7, -8 +9,
    // stick presses 10/11, home12 capture13
    return {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 4, bumperR: 5,
      stickL: 10, stickR: 11,
      dpadUp: 14, dpadDown: 15, dpadLeft: 16, dpadRight: 17,
      centerTop: 12, centerLeft: 8, centerRight: 9, centerExtra: 13,
      triggerL: 6, triggerR: 7,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    }
  }
  // generic: 1..4 diamond, bumpers 4/5, sticks 9/10, center 6/7
  return {
    faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
    bumperL: 4, bumperR: 5,
    stickL: 9, stickR: 10,
    dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
    centerTop: 8, centerLeft: 6, centerRight: 7, centerExtra: -1,
    triggerL: -1, triggerR: -1,
    known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
  }
}

// Axis map — js axis index per art element, heuristics per driver family.
// Most pads report LX, LY, RX, RY on axes 0..3 and analog triggers after.
function axesMap(layout, axisCount) {
  if (axisCount >= 6) return { lx: 0, ly: 1, rx: 2, ry: 3, lt: 4, rt: 5 }
  if (layout === "xbox" && axisCount >= 4) return { lx: 0, ly: 1, rx: -1, ry: -1, lt: 2, rt: 3 }
  return { lx: 0, ly: 1, rx: 2, ry: 3, lt: -1, rt: -1 }
}

// Trigger axis conventions differ: xpad family idles at -1 (0..255 range),
// hid-playstation and hid-nintendo idle at 0. Normalize both to 0..1.
function triggerNorm(layout, raw) {
  var v = Number(raw)
  if (!isFinite(v)) return 0
  if (layout === "ps" || layout === "switch") return Math.min(1, Math.max(0, v))
  return Math.min(1, Math.max(0, (v + 1) / 2))
}
