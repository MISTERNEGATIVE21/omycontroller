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
// Args:
//   name/driver/vendor/product — sysfs facts
//   axisCount/buttonCount      — optional shape facts (0 = unknown yet; they
//                                arrive later from the jstest header, at
//                                which point Service re-classifies)
//
// Returns:
//   {
//     layout:    "xbox" | "ps" | "switch" | "joystick" | "generic" (drives art)
//     modelLabel:          e.g. "DualSense", "Xbox pad", "Switch Pro pad"
//     protocol:            e.g. "XInput", "Switch Pro", "DualSense"
//     driverNote:          kernel driver actually bound, e.g. "xpadneo"
//     maker:               vendor string when known
//   }
// ---------------------------------------------------------------------------
// Names that describe single-stick hardware (flight/arcade sticks, yokes,
// throttle quadrants). These get the dedicated joystick silhouette instead
// of a full gamepad body.
var JOYSTICK_WORDS = [
  "joystick", "flight stick", "arcade stick", "fightstick", "fighting",
  "yoke", "rudder", "throttle", "hotas", "t.flight", "x52", "x56",
  "twist lock", "aviator", "qanba", "mayflash", "mad catz"
]

function looksLikeJoystick(name) {
  var n = lower(name)
  for (var i = 0; i < JOYSTICK_WORDS.length; i++) {
    if (n.indexOf(JOYSTICK_WORDS[i]) !== -1) return true
  }
  return false
}

function classify(name, driver, vendor, product, axisCount, buttonCount) {
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

  // Plain joysticks -------------------------------------------------------
  // Either the name says so, or the shape does (few axes, few buttons, and
  // no gamepad-ish name). Shape facts only apply once the jstest header
  // told us the real counts (axisCount > 0).
  var ac = Number(axisCount) || 0
  var bc = Number(buttonCount) || 0
  var shapeSaysJoystick = ac > 0 && ac <= 4 && bc <= 8 &&
                          n.indexOf("gamepad") === -1 &&
                          n.indexOf("controller") === -1 &&
                          n.indexOf("wireless controller") === -1
  if (looksLikeJoystick(name) || shapeSaysJoystick) {
    out.layout = "joystick"
    out.protocol = "HID joystick"
    if (n.indexOf("hotas") !== -1) out.modelLabel = "HOTAS stick"
    else if (n.indexOf("arcade") !== -1 || n.indexOf("fight") !== -1) out.modelLabel = "Arcade stick"
    else if (n.indexOf("flight") !== -1 || n.indexOf("yoke") !== -1) out.modelLabel = "Flight stick"
    return out
  }

  // Sony ---------------------------------------------------------------
  if (d === "hid-playstation" || n.indexOf("wiimote") === 0) {
    // hid-playstation covers both DualShock 4 and DualSense — and both
    // name themselves "Wireless Controller", so the product id decides:
    //   0ce6 = DualSense (and Edge), 05c4/09cc = DualShock 4.
    var p = String(product || "").toLowerCase()
    var isDs = n.indexOf("dualsense") !== -1 || (v === "054c" && p === "0ce6")
    var isDs4 = n.indexOf("dualshock") !== -1 || (v === "054c" && (p === "05c4" || p === "09cc"))
    if (isDs) {
      out.layout = "ps"
      out.modelLabel = n.indexOf("edge") !== -1 ? "DualSense Edge" : "DualSense"
      out.protocol = "DualSense"
    } else if (isDs4) {
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
  if (bt === "0005" || bt === "bluetooth") return "Bluetooth"
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
  for (var prop in src) {
    out[prop] = src[prop]
  }
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
function buttonTables(layout, profile) {
  var t;
  if (layout === "xbox") {
    // xpad / xpadneo: A0 B1 X2 Y3, LB4 RB5, back6 start7 guide8,
    // TL9 TR10, dpad 11..14
    t = {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 4, bumperR: 5,
      stickL: 9, stickR: 10,
      dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
      centerTop: 8, centerLeft: 6, centerRight: 7, centerExtra: -1,
      triggerL: -1, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    };
  } else if (layout === "ps") {
    // hid-playstation: ×0 ○1 □2 △3, create4 options5 PS6 touchpad7,
    // L3 8, R3 9, L1 10, R1 11
    t = {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 10, bumperR: 11,
      stickL: 8, stickR: 9,
      dpadUp: 12, dpadDown: 13, dpadLeft: 14, dpadRight: 15,
      centerTop: 6, centerLeft: 4, centerRight: 5, centerExtra: 7,
      triggerL: -1, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    };
  } else if (layout === "switch") {
    // hid-nintendo pro: B0 A1 Y2 X3, L4 R5, ZL6 ZR7, -8 +9,
    // stick presses 10/11, home12 capture13
    t = {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 4, bumperR: 5,
      stickL: 10, stickR: 11,
      dpadUp: 14, dpadDown: 15, dpadLeft: 16, dpadRight: 17,
      centerTop: 12, centerLeft: 8, centerRight: 9, centerExtra: 13,
      triggerL: 6, triggerR: 7,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    };
  } else if (layout === "joystick") {
    // Conventional single-stick ordering: trigger = button 0, then the
    // base/grip cluster 1..6. The hat switch is NOT buttons — it reports
    // as ABS_HAT0X/Y axes (indices 16/17), handled by joystickExtras().
    t = {
      faceTop: 2, faceBottom: 1, faceLeft: 4, faceRight: 3,
      bumperL: 5, bumperR: 6,
      stickL: 9, stickR: -1,
      dpadUp: -1, dpadDown: -1, dpadLeft: -1, dpadRight: -1,
      centerTop: 7, centerLeft: -1, centerRight: -1, centerExtra: 8,
      triggerL: 0, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
    };
  } else {
    // generic: 1..4 diamond, bumpers 4/5, sticks 9/10, center 6/7
    t = {
      faceTop: 3, faceBottom: 0, faceLeft: 2, faceRight: 1,
      bumperL: 4, bumperR: 5,
      stickL: 9, stickR: 10,
      dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
      centerTop: 8, centerLeft: 6, centerRight: 7, centerExtra: -1,
      triggerL: -1, triggerR: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    };
  }

  // Profile-based button remapping
  if (profile) {
    if (profile.remapPreset === "nintendo_swap" || profile.swapFace) {
      var tmpBottom = t.faceBottom;
      t.faceBottom = t.faceRight;
      t.faceRight = tmpBottom;
      var tmpTop = t.faceTop;
      t.faceTop = t.faceLeft;
      t.faceLeft = tmpTop;
    }
    if (profile.buttonMap && typeof profile.buttonMap === "object") {
      for (var k in profile.buttonMap) {
        if (t.hasOwnProperty(k) && typeof profile.buttonMap[k] === "number") {
          t[k] = profile.buttonMap[k];
        }
      }
    }
  }

  return t;
}

// Axis map — js axis index per art element, heuristics per driver family.
// Most pads report LX, LY, RX, RY on axes 0..3 and analog triggers after.
// For joysticks the jstest header's axis-name list (when available) picks
// the real Throttle axis; without names we fall back to index 2.
function axesMap(layout, axisCount, axisNames) {
  if (layout === "joystick") {
    var thr = throttleIndex(axisNames)
    if (thr === -1 && axisCount >= 3) thr = 2   // nameless fallback: first extra axis
    return { lx: 0, ly: 1, rx: -1, ry: -1, lt: thr, rt: -1 }
  }
  if (axisCount >= 6) return { lx: 0, ly: 1, rx: 2, ry: 3, lt: 4, rt: 5 }
  if (layout === "xbox" && axisCount >= 4) return { lx: 0, ly: 1, rx: -1, ry: -1, lt: 2, rt: 3 }
  return { lx: 0, ly: 1, rx: 2, ry: 3, lt: -1, rt: -1 }
}

// ---------------------------------------------------------------------------
// Joystick axis-name helpers. jstest prints the header as
//   "... has 6 axes (    X,     Y,  Throttle,   Rudder,   Hat0X,   Hat0Y) ..."
// so Service can hand us the trimmed name list. Matching is lowercase.
// ---------------------------------------------------------------------------
function axisNameList(axisNames) {
  if (!axisNames) return []
  if (axisNames.join) return axisNames.map(function (s) { return lower(s) })
  return []
}

// The lever: prefer a real "Throttle" axis, else the first non-hat extra
// axis (twist/rudder — still a useful live lever bar).
function throttleIndex(axisNames) {
  var names = axisNameList(axisNames)
  if (names.length === 0) return -1
  var t = names.indexOf("throttle")
  if (t !== -1) return t
  for (var i = 2; i < names.length; i++) {
    if (names[i].indexOf("hat") !== 0) return i
  }
  return -1
}

// HAT0 pair indices (any hat number) from the name list.
function hatIndices(axisNames) {
  var names = axisNameList(axisNames)
  var out = { x: -1, y: -1 }
  for (var i = 0; i < names.length; i++) {
    if (/^hat\d*x$/.test(names[i])) out.x = i
    else if (/^hat\d*y$/.test(names[i])) out.y = i
  }
  return out
}

// ---------------------------------------------------------------------------
// Joystick extras — hat switch + throttle from the raw axis array.
// With the header's axis names we bind exactly (Throttle / Hat0X / Hat0Y);
// without names we fall back to evdev conventions (ABS_HAT0X/Y = indices
// 16/17, first extra analog axis = lever).
//   hatX/hatY : -1 | 0 | 1   (0 = centered)
//   throttle  : 0..1         (-1 when the stick has no extra analog axis)
// ---------------------------------------------------------------------------
function joystickExtras(axes, axisNames) {
  var out = { hatX: 0, hatY: 0, hasHat: false, throttle: -1, hasThrottle: false }
  if (!axes) return out
  var hat = hatIndices(axisNames)
  var thrIdx = throttleIndex(axisNames)
  for (var i = 0; i < axes.length; i++) {
    var v = Number(axes[i])
    if (!isFinite(v)) continue
    if (hat.x === i || hat.y === i) {
      if (hat.x === i) out.hatX = v
      else out.hatY = v
      out.hasHat = true
    } else if (thrIdx === i) {
      out.throttle = (v + 1) / 2
      out.hasThrottle = true
    } else if (thrIdx === -1 && hat.x === -1 && i >= 2 && i < 16) {
      // No names available: evdev-convention fallback, first extra axis.
      out.throttle = (v + 1) / 2
      out.hasThrottle = true
    }
  }
  // Hat by position when names were missing (HAT0X/Y = 16/17).
  if (!out.hasHat && axes.length > 17) {
    out.hatX = Number(axes[16]) || 0
    out.hatY = Number(axes[17]) || 0
    out.hasHat = true
  }
  return out
}

// ---------------------------------------------------------------------------
// ControllerImage (Kenney, CC0) button-cap art resolution.
//
// The vendored sets live in assets/input/<set>/ and mirror ControllerImage's
// SDL3 physical-button naming: n/s/w/e = top/bottom/left/right face positions
// (Y/A/X/B letters on the Xbox caps, △/×/□/○ glyphs on the PS3 set). Paths are
// returned relative to the plugin root; callers pass them through
// Qt.resolvedUrl so the panel/bar can load them from any component.
// ---------------------------------------------------------------------------
function artSet(layout) {
  if (layout === "xbox") return "xbox360"
  if (layout === "ps") return "ps3"
  if (layout === "switch") return "switchpro"
  return ""
}

function artPath(set, name) {
  return set ? "assets/input/" + set + "/" + name + ".svg" : ""
}

// Face cap for a diamond position ("top"/"bottom"/"left"/"right").
function faceArt(layout, pos, profile) {
  if (layout !== "xbox" && layout !== "ps") return ""
  var map = { top: "n", bottom: "s", left: "w", right: "e" }
  if (profile) {
    if (profile.remapPreset === "nintendo_swap" || profile.swapFace) {
      map = { top: "w", bottom: "e", left: "n", right: "s" }
    }
    if (profile.buttonMap && typeof profile.buttonMap === "object") {
      var tBase = buttonTables(layout, null)
      var tRemapped = buttonTables(layout, profile)
      var targetRole = pos === "top" ? "faceTop" : pos === "bottom" ? "faceBottom" : pos === "left" ? "faceLeft" : "faceRight"
      var physIdx = tRemapped[targetRole]
      for (var r in tBase) {
        if (r.indexOf("face") === 0 && tBase[r] === physIdx) {
          if (r === "faceTop") map[pos] = "n"
          else if (r === "faceBottom") map[pos] = "s"
          else if (r === "faceLeft") map[pos] = "w"
          else if (r === "faceRight") map[pos] = "e"
          break
        }
      }
    }
  }
  return artPath(artSet(layout), map[pos])
}

// Generic button SVG art resolver for any role ("faceBottom", "bumperL", etc.)
function buttonArt(layout, role, profile) {
  var set = artSet(layout || "xbox") || "xbox360"
  var activeRole = role
  if (profile && profile.buttonMap && typeof profile.buttonMap === "object") {
    var tBase = buttonTables(layout, null)
    var tRemapped = buttonTables(layout, profile)
    var physIdx = tRemapped[role]
    if (physIdx !== undefined && physIdx !== -1) {
      for (var r in tBase) {
        if (tBase[r] === physIdx) {
          activeRole = r
          break
        }
      }
    }
  }

  var roleMap = {
    faceBottom: "s",
    faceRight: "e",
    faceLeft: "w",
    faceTop: "n",
    bumperL: "leftshoulder",
    bumperR: "rightshoulder",
    triggerL: "lefttrigger",
    triggerR: "righttrigger",
    stickL: set === "ps3" ? "leftstick" : "",
    stickR: set === "ps3" ? "rightstick" : "",
    dpadUp: "dpup",
    dpadDown: "dpdown",
    dpadLeft: "dpleft",
    dpadRight: "dpright",
    centerLeft: "back",
    centerRight: "start"
  }
  if (profile && (profile.remapPreset === "nintendo_swap" || profile.swapFace)) {
    if (activeRole === "faceBottom") return artPath(set, "e")
    if (activeRole === "faceRight") return artPath(set, "s")
    if (activeRole === "faceLeft") return artPath(set, "n")
    if (activeRole === "faceTop") return artPath(set, "w")
  }
  if (roleMap[activeRole]) {
    return artPath(set, roleMap[activeRole])
  }
  return ""
}

// Logical button label given layout, role and profile
function buttonLabel(layout, role, profile) {
  var isPs = layout === "ps"
  var isSwitch = layout === "switch"
  var swapped = profile && (profile.remapPreset === "nintendo_swap" || profile.swapFace)

  var activeRole = role
  if (profile && profile.buttonMap && typeof profile.buttonMap === "object") {
    var tBase = buttonTables(layout, null)
    var tRemapped = buttonTables(layout, profile)
    var physIdx = tRemapped[role]
    if (physIdx !== undefined && physIdx !== -1) {
      for (var r in tBase) {
        if (tBase[r] === physIdx) {
          activeRole = r
          break
        }
      }
    }
  }

  if (activeRole === "faceBottom") {
    if (isPs) return swapped ? "○" : "×"
    if (isSwitch) return "B"
    return swapped ? "B" : "A"
  }
  if (activeRole === "faceRight") {
    if (isPs) return swapped ? "×" : "○"
    if (isSwitch) return "A"
    return swapped ? "A" : "B"
  }
  if (activeRole === "faceLeft") {
    if (isPs) return swapped ? "△" : "□"
    if (isSwitch) return "Y"
    return swapped ? "Y" : "X"
  }
  if (activeRole === "faceTop") {
    if (isPs) return swapped ? "□" : "△"
    if (isSwitch) return "X"
    return swapped ? "X" : "Y"
  }
  if (activeRole === "bumperL") return isPs ? "L1" : isSwitch ? "L" : "LB"
  if (activeRole === "bumperR") return isPs ? "R1" : isSwitch ? "R" : "RB"
  if (activeRole === "triggerL") return isPs ? "L2" : isSwitch ? "ZL" : "LT"
  if (activeRole === "triggerR") return isPs ? "R2" : isSwitch ? "ZR" : "RT"
  if (activeRole === "stickL") return isPs ? "L3" : "LS"
  if (activeRole === "stickR") return isPs ? "R3" : "RS"
  if (activeRole === "dpadUp") return "▲"
  if (activeRole === "dpadDown") return "▼"
  if (activeRole === "dpadLeft") return "◀"
  if (activeRole === "dpadRight") return "▶"
  if (activeRole === "centerLeft") return isPs ? "Create" : isSwitch ? "–" : "View"
  if (activeRole === "centerRight") return isPs ? "Options" : isSwitch ? "+" : "Menu"
  return activeRole
}

// Shoulder (bumper) cap for a side, empty for sets without shoulder art.
function bumperArt(layout, side) {
  if (layout !== "xbox" && layout !== "ps") return ""
  return artPath(artSet(layout), (side === "l" ? "left" : "right") + "shoulder")
}

// Analog trigger cap for a side, empty for sets without trigger art.
function triggerArt(layout, side) {
  if (layout !== "xbox" && layout !== "ps") return ""
  return artPath(artSet(layout), (side === "l" ? "left" : "right") + "trigger")
}

// Center key cap: "left" = back/create/share, "right" = start/options/menu.
function centerArt(layout, side) {
  if (layout !== "xbox" && layout !== "ps") return ""
  return artPath(artSet(layout), side === "left" ? "back" : "start")
}

// Human word for a layout, shown in the Hardware chip + device menu.
function shapeLabel(layout) {
  if (layout === "xbox") return "gamepad · Xbox shape"
  if (layout === "ps") return "gamepad · PlayStation shape"
  if (layout === "switch") return "gamepad · Switch shape"
  if (layout === "joystick") return "joystick · single stick"
  return "gamepad · generic"
}

// Trigger axis conventions differ: xpad family idles at -1 (0..255 range),
// hid-playstation and hid-nintendo idle at 0. Normalize both to 0..1.
function triggerNorm(layout, raw) {
  var v = Number(raw)
  if (!isFinite(v)) return 0
  if (layout === "ps" || layout === "switch" || layout === "joystick") return Math.min(1, Math.max(0, v))
  return Math.min(1, Math.max(0, (v + 1) / 2))
}

// ---------------------------------------------------------------------------
// Connection Icon Resolver
// Resolves hardware bus/phys or connection name into Gamepadla SVG assets
// ---------------------------------------------------------------------------
function connectionIcon(busType, phys) {
  var bt = lower(busType)
  var ph = lower(phys)

  // Check dongles / wireless adapters first — looksLikeDongle folds both
  // fields against KNOWN_DONGLES, so a single call covers every wording.
  if (looksLikeDongle(busType, phys)) {
    return "assets/icon_dongle.svg"
  }

  // Check Bluetooth
  if (bt === "0005" || bt === "5" || bt === "bluetooth" || bt.indexOf("bt") !== -1 ||
      ph.indexOf("bluetooth") !== -1 || (phys && /^[0-9a-f]{2}(:[0-9a-f]{2}){5}/i.test(phys))) {
    return "assets/icon_bt.svg"
  }

  // Wired USB / default
  return "assets/icon_cable.svg"
}

// ---------------------------------------------------------------------------
// Response Curves & Deadzone Tuning
// Supports scalar axis values and {x, y} coordinate vectors.
// Presets: linear, dynamic (exponential cubic blend), smooth (sinusoidal S-curve),
// and aggressive (concave quick ramp).
// ---------------------------------------------------------------------------
function applyCurve(value, curveType, deadzone, outerDeadzone) {
  if (value !== null && typeof value === "object" && ("x" in value || "y" in value)) {
    var vx = Number(value.x) || 0
    var vy = Number(value.y) || 0
    var r = Math.sqrt(vx * vx + vy * vy)
    if (r === 0) return { x: 0, y: 0 }
    var curvedR = applyCurveScalar(r, curveType, deadzone, outerDeadzone)
    var factor = curvedR / r
    return { x: vx * factor, y: vy * factor }
  }
  return applyCurveScalar(value, curveType, deadzone, outerDeadzone)
}

function applyCurveScalar(value, curveType, deadzone, outerDeadzone) {
  var val = Number(value) || 0
  var sign = val < 0 ? -1 : 1
  var abs = Math.abs(val)
  var innerDz = Number(deadzone) || 0
  var outerDz = (outerDeadzone !== undefined && outerDeadzone !== null && isFinite(Number(outerDeadzone)))
    ? Number(outerDeadzone) : 1.0
  if (outerDz <= innerDz) outerDz = 1.0

  if (abs <= innerDz) return 0
  if (abs >= outerDz) return sign * 1.0

  var u = (abs - innerDz) / (outerDz - innerDz)
  u = Math.min(1.0, Math.max(0.0, u))

  var c = String(curveType || "linear").toLowerCase()
  var out = u
  if (c === "dynamic") {
    // Exponential cubic blend for precision center + fast outer
    out = 0.35 * u + 0.65 * Math.pow(u, 3)
  } else if (c === "smooth") {
    // Sinusoidal S-curve
    out = 0.5 * (1 - Math.cos(Math.PI * u))
  } else if (c === "aggressive") {
    // Aggressive curve: quick activation near center
    out = 0.5 * u + 0.5 * Math.sqrt(u)
  } else {
    // Linear
    out = u
  }

  return sign * out
}

// ---------------------------------------------------------------------------
// Gamepadla Circularity Radar & Drift Diagnostics
// Computes radial magnitude r, center resting drift %, and tracks perimeter
// bounds to measure deviation from the ideal unit circle (r = 1.0).
// ---------------------------------------------------------------------------
function circularityMetrics(x, y, history) {
  var nx = Number(x) || 0
  var ny = Number(y) || 0
  var r = Math.sqrt(nx * nx + ny * ny)

  var pts = []
  if (Array.isArray(history)) {
    pts = history.slice()
  } else if (history && Array.isArray(history.history)) {
    pts = history.history.slice()
  } else if (history && Array.isArray(history.points)) {
    pts = history.points.slice()
  }

  var currentPt = { x: nx, y: ny, r: r }
  if (pts.length >= 500) {
    pts.shift()
  }
  pts.push(currentPt)

  // 32-sector perimeter tracking
  var sectorMax = {}
  for (var i = 0; i < pts.length; i++) {
    var p = pts[i]
    var pr = p.r !== undefined ? p.r : Math.sqrt(p.x * p.x + p.y * p.y)
    if (pr > 0.5) {
      var angle = Math.atan2(p.y, p.x)
      var normAngle = angle < 0 ? angle + 2 * Math.PI : angle
      var sector = Math.floor((normAngle / (2 * Math.PI)) * 32) % 32
      sectorMax[sector] = Math.max(sectorMax[sector] || 0, pr)
    }
  }

  var sectors = Object.keys(sectorMax)
  var error = 0
  if (sectors.length > 0) {
    var totalDev = 0
    for (var s = 0; s < sectors.length; s++) {
      totalDev += Math.abs(sectorMax[sectors[s]] - 1.0)
    }
    error = (totalDev / sectors.length) * 100
  }

  var centerDrift = Math.round(r * 1000) / 10
  var circError = Math.round(error * 10) / 10

  return {
    x: nx,
    y: ny,
    r: r,
    magnitude: r,
    centerDrift: centerDrift,
    centerDriftPercent: centerDrift,
    circularityError: circError,
    error: circError,
    history: pts,
    sectorMax: sectorMax
  }
}

// ---------------------------------------------------------------------------
// Polling Rate & Latency Benchmark Calculations
// ---------------------------------------------------------------------------
function formatHz(ms) {
  var n = Number(ms)
  if (!isFinite(n) || n <= 0) return "0 Hz"
  var hz = Math.round(1000 / n)
  return hz + " Hz"
}

function latencyMetrics(eventIntervals) {
  if (!eventIntervals || !eventIntervals.length) {
    return {
      avg: 0,
      min: 0,
      max: 0,
      jitter: 0,
      hz: 0,
      pollingRate: 0,
      formattedHz: "0 Hz",
      label: "idle"
    }
  }

  var count = 0
  var sum = 0
  var min = Infinity
  var max = -Infinity
  for (var i = 0; i < eventIntervals.length; i++) {
    var v = Number(eventIntervals[i])
    if (!isFinite(v) || v <= 0) continue
    sum += v
    count++
    if (v < min) min = v
    if (v > max) max = v
  }

  if (count === 0) {
    return {
      avg: 0,
      min: 0,
      max: 0,
      jitter: 0,
      hz: 0,
      pollingRate: 0,
      formattedHz: "0 Hz",
      label: "idle"
    }
  }

  var avg = sum / count
  var varianceSum = 0
  for (var j = 0; j < eventIntervals.length; j++) {
    var val = Number(eventIntervals[j])
    if (!isFinite(val) || val <= 0) continue
    var diff = val - avg
    varianceSum += diff * diff
  }
  var jitter = Math.sqrt(varianceSum / count)
  var hz = avg > 0 ? Math.round(1000 / avg) : 0

  return {
    avg: avg,
    min: min,
    max: max,
    jitter: jitter,
    hz: hz,
    pollingRate: hz,
    formattedHz: formatHz(avg),
    label: latencyLabel(avg, hz)
  }
}

// ---------------------------------------------------------------------------
// CommonJS exports for Node.js test runner while preserving QML compatibility
// ---------------------------------------------------------------------------
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    KNOWN_DONGLES: KNOWN_DONGLES,
    VENDORS: VENDORS,
    JOYSTICK_WORDS: JOYSTICK_WORDS,
    DEFAULT_PROFILE: DEFAULT_PROFILE,
    lower: lower,
    looksLikeDongle: looksLikeDongle,
    looksLikeJoystick: looksLikeJoystick,
    classify: classify,
    connection: connection,
    connectionShort: connectionShort,
    connectionIcon: connectionIcon,
    batteryBucket: batteryBucket,
    batteryText: batteryText,
    playerColor: playerColor,
    batteryLabel: batteryLabel,
    latencyLabel: latencyLabel,
    formatHz: formatHz,
    latencyMetrics: latencyMetrics,
    profileKey: profileKey,
    normalizeProfile: normalizeProfile,
    applyStickDeadzone: applyStickDeadzone,
    applyCurve: applyCurve,
    circularityMetrics: circularityMetrics,
    buttonTables: buttonTables,
    axesMap: axesMap,
    axisNameList: axisNameList,
    throttleIndex: throttleIndex,
    hatIndices: hatIndices,
    joystickExtras: joystickExtras,
    shapeLabel: shapeLabel,
    artSet: artSet,
    artPath: artPath,
    faceArt: faceArt,
    buttonArt: buttonArt,
    buttonLabel: buttonLabel,
    bumperArt: bumperArt,
    triggerArt: triggerArt,
    centerArt: centerArt,
    triggerNorm: triggerNorm
  }
}

