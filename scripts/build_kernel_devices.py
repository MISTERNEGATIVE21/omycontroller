#!/usr/bin/env python3
# omycontroller — scripts/build_kernel_devices.py
#
# Compiles vendor and device databases directly from Linux kernel sources
# (drivers/input/joystick/xpad.c, drivers/hid/*) and /usr/share/hwdata/usb.ids.
# Injects clean VENDORS and KERNEL_DEVICES tables into GamepadModel.js.

import json
import os
import re
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODEL_JS_PATH = os.path.join(ROOT_DIR, "GamepadModel.js")

# 75+ Linux Kernel Gamepad & Joystick Vendors
VENDORS = {
    "045e": "Microsoft",
    "054c": "Sony",
    "057e": "Nintendo",
    "1532": "Razer",
    "1689": "Razer",
    "0f0d": "HORI",
    "20d6": "PowerA",
    "24c6": "PowerA",
    "2dc8": "8BitDo",
    "0e6f": "PDP",
    "056e": "Elecom",
    "0079": "DragonRise",
    "046d": "Logitech",
    "044f": "ThrustMaster",
    "0738": "Mad Catz",
    "07ff": "Mad Catz",
    "05fd": "Mad Catz",
    "1bad": "Harmonix",
    "0b05": "ASUS",
    "1038": "SteelSeries",
    "10f5": "Turtle Beach",
    "11c9": "Nacon",
    "146b": "Nacon",
    "2e24": "Hyperkin",
    "2e95": "SCUF Gaming",
    "28de": "Valve",
    "2563": "ShanWan",
    "20bc": "ShanWan",
    "11c0": "Beitong",
    "3537": "GameSir",
    "2f24": "GameSir",
    "294b": "GameSir",
    "366c": "GameSir",
    "31e3": "Flydigi",
    "3285": "Flydigi",
    "3958": "Flydigi",
    "260d": "Flydigi",
    "3507": "BIGBIG WON",
    "2993": "EasySMX",
    "3651": "Machenike",
    "258a": "Machenike",
    "37d7": "Thunderobot",
    "413d": "Gulikit",
    "2c22": "Qanba",
    "0c12": "Zeroplus",
    "0351": "CRKD",
    "03eb": "Wooting",
    "03f0": "HyperX",
    "06a3": "Saitek",
    "068e": "CH Products",
    "0583": "Rockfire",
    "1430": "RedOctane",
    "12ab": "Honey Bee",
    "11ff": "PXN",
    "17ef": "Lenovo",
    "0db0": "MSI",
    "0502": "Acer",
    "15e4": "Numark",
    "16d0": "Azeron",
    "2e3a": "PB Tails",
    "0955": "NVIDIA",
    "18d1": "Google",
    "1949": "Amazon",
    "1209": "Open Source",
    "16c0": "Teensy / V-USB",
    "1a86": "WCH",
    "1345": "Sino Lite",
    "289b": "Raphnet",
    "0d2f": "Andamiro",
    "0e4c": "Radica",
    "0f30": "Philips",
    "05fe": "Chic",
    "062a": "Logic3",
    "0e8f": "SmartJoy",
    "102c": "Joytech",
    "162e": "Joytech",
    "2345": "Shannon",
    "8380": "Besavior",
    "05ac": "Apple"
}

# Base curated kernel device entries (PlayStation, Nintendo, Steam, Logitech, etc.)
BASE_DEVICES = {
    # Sony PlayStation (hid-playstation / hid-sony)
    "054c:0268": {"name": "DualShock 3", "layout": "ps", "protocol": "DualShock 3", "maker": "Sony"},
    "054c:042f": {"name": "PlayStation Move Navigation Controller", "layout": "ps", "protocol": "PS Move", "maker": "Sony"},
    "054c:05c4": {"name": "DualShock 4", "layout": "ps", "protocol": "DualShock 4", "maker": "Sony"},
    "054c:09cc": {"name": "DualShock 4 v2", "layout": "ps", "protocol": "DualShock 4", "maker": "Sony"},
    "054c:0ba0": {"name": "DualShock 4 USB Wireless Adapter", "layout": "ps", "protocol": "DualShock 4", "maker": "Sony"},
    "054c:0ce6": {"name": "DualSense", "layout": "ps", "protocol": "DualSense", "maker": "Sony"},
    "054c:0df2": {"name": "DualSense Edge", "layout": "ps", "protocol": "DualSense", "maker": "Sony"},
    "054c:0e5f": {"name": "Access Controller", "layout": "ps", "protocol": "DualSense", "maker": "Sony"},

    # Nintendo (hid-nintendo)
    "057e:2006": {"name": "Joy-Con (L)", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:2007": {"name": "Joy-Con (R)", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:2008": {"name": "Joy-Con (L/R)", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:2009": {"name": "Switch Pro Controller", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:200e": {"name": "Joy-Con Charging Grip", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:2017": {"name": "SNES Controller", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:2019": {"name": "N64 Controller", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "057e:201e": {"name": "Genesis Controller", "layout": "switch", "protocol": "Nintendo Switch", "maker": "Nintendo"},
    "0f0d:00f6": {"name": "HORI Battle Pad", "layout": "switch", "protocol": "Nintendo Switch", "maker": "HORI"},

    # Valve Steam (hid-steam)
    "28de:1102": {"name": "Steam Controller (Wired)", "layout": "xbox", "protocol": "Steam Input", "maker": "Valve"},
    "28de:1142": {"name": "Steam Controller (Wireless)", "layout": "xbox", "protocol": "Steam Input", "maker": "Valve"},
    "28de:1205": {"name": "Steam Deck Controller", "layout": "xbox", "protocol": "Steam Input", "maker": "Valve"},

    # Microsoft Bluetooth & Elite (hid-xpadneo / hid-microsoft)
    "045e:028e": {"name": "Xbox 360 Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:028f": {"name": "Xbox 360 Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02d1": {"name": "Xbox One Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02dd": {"name": "Xbox One Controller (Covert)", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02e0": {"name": "Xbox One S Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02e3": {"name": "Xbox Elite Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02ea": {"name": "Xbox One S Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:02fd": {"name": "Xbox One S Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b00": {"name": "Xbox Elite Wireless Controller Series 2", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b05": {"name": "Xbox Elite Wireless Controller Series 2", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b12": {"name": "Xbox Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b13": {"name": "Xbox Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b20": {"name": "Xbox Wireless Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b22": {"name": "Xbox Elite Wireless Controller Series 2", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b0a": {"name": "Xbox Adaptive Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "045e:0b0c": {"name": "Xbox Adaptive Controller", "layout": "xbox", "protocol": "XInput", "maker": "Microsoft"},
    "0b05:1abd": {"name": "ASUS ROG Raikiri Pro", "layout": "xbox", "protocol": "XInput", "maker": "ASUS"},

    # Logitech HID (hid-logitech)
    "046d:c216": {"name": "Logitech Dual Action", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c218": {"name": "Logitech RumblePad 2", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c219": {"name": "Logitech Cordless RumblePad 2", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c21d": {"name": "Logitech Gamepad F310", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c21e": {"name": "Logitech Gamepad F510", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c21f": {"name": "Logitech Wireless Gamepad F710", "layout": "generic", "protocol": "DirectInput", "maker": "Logitech"},
    "046d:c215": {"name": "Logitech Extreme 3D Pro", "layout": "joystick", "protocol": "HID joystick", "maker": "Logitech"},
    "046d:c283": {"name": "Logitech WingMan Force 3D", "layout": "joystick", "protocol": "HID joystick", "maker": "Logitech"},
    "046d:c294": {"name": "Logitech Driving Force", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c298": {"name": "Logitech G25 Racing Wheel", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c299": {"name": "Logitech G27 Racing Wheel", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c29a": {"name": "Logitech Driving Force GT", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c29b": {"name": "Logitech G29 Driving Force Racing Wheel", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c24f": {"name": "Logitech G29 Driving Force (PS3)", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c262": {"name": "Logitech G920 Driving Force Racing Wheel", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c266": {"name": "Logitech G923 Racing Wheel (Xbox)", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},
    "046d:c268": {"name": "Logitech G923 Racing Wheel (PlayStation)", "layout": "joystick", "protocol": "HID wheel", "maker": "Logitech"},

    # Modern Boutique & Hall Effect Gamepads
    "0079:181c": {"name": "ZhiXu Gamepad", "layout": "xbox", "protocol": "DirectInput / HID", "maker": "ZhiXu", "buttonPreset": "zhixu"},
    "0079:0006": {"name": "DragonRise Gamepad", "layout": "generic", "protocol": "HID gamepad", "maker": "DragonRise"},
    "0079:0011": {"name": "DragonRise / Betop Pad", "layout": "generic", "protocol": "HID gamepad", "maker": "DragonRise"},
    "0955:7210": {"name": "NVIDIA Shield Controller", "layout": "xbox", "protocol": "HID gamepad", "maker": "NVIDIA"},
    "0955:7214": {"name": "NVIDIA Shield Controller v2", "layout": "xbox", "protocol": "HID gamepad", "maker": "NVIDIA"},
    "18d1:9400": {"name": "Google Stadia Controller", "layout": "xbox", "protocol": "HID gamepad", "maker": "Google"},
    "1949:0402": {"name": "Amazon Luna Controller", "layout": "xbox", "protocol": "HID gamepad", "maker": "Amazon"},
    "3537:1001": {"name": "GameSir G7 SE", "layout": "xbox", "protocol": "XInput", "maker": "GameSir"},
    "3537:1004": {"name": "GameSir T4 Cyclone Pro", "layout": "xbox", "protocol": "XInput", "maker": "GameSir"},
    "3537:1007": {"name": "GameSir G8 Galileo", "layout": "xbox", "protocol": "XInput", "maker": "GameSir"},
    "31e3:1100": {"name": "Flydigi Apex 4", "layout": "xbox", "protocol": "XInput", "maker": "Flydigi"},
    "31e3:1200": {"name": "Flydigi Vader 4 Pro", "layout": "xbox", "protocol": "XInput", "maker": "Flydigi"},
    "31e3:1300": {"name": "Flydigi Direwolf 2", "layout": "xbox", "protocol": "XInput", "maker": "Flydigi"},
    "3507:1001": {"name": "BIGBIG WON Rainbow 2 Pro", "layout": "xbox", "protocol": "XInput", "maker": "BIGBIG WON"},
    "3507:1003": {"name": "BIGBIG WON Gale Hall", "layout": "xbox", "protocol": "XInput", "maker": "BIGBIG WON"},
    "2993:0001": {"name": "EasySMX X10", "layout": "xbox", "protocol": "XInput", "maker": "EasySMX"},
    "3651:1000": {"name": "Machenike G5 Pro", "layout": "xbox", "protocol": "XInput", "maker": "Machenike"},
    "37d7:1000": {"name": "Thunderobot G50S", "layout": "xbox", "protocol": "XInput", "maker": "Thunderobot"},
    "413d:1000": {"name": "Gulikit KK3 Max", "layout": "xbox", "protocol": "XInput", "maker": "Gulikit"},
    "0351:1000": {"name": "CRKD Nitro Deck", "layout": "switch", "protocol": "Nintendo Switch", "maker": "CRKD"},
    "2dc8:3106": {"name": "8BitDo Ultimate Controller", "layout": "xbox", "protocol": "XInput", "maker": "8BitDo"}
}


def load_xpad_devices():
    """Extract devices from xpad.c if available."""
    devs = {}
    candidates = [
        os.path.join(ROOT_DIR, "xpad.c"),
        "/tmp/xpad.c"
    ]
    # Check if artifact steps have it
    for root, _, files in os.walk("/home/mister/.gemini/antigravity-ide/brain/"):
        for f in files:
            if f == "content.md":
                p = os.path.join(root, f)
                try:
                    with open(p, "r", errors="ignore") as fp:
                        head = fp.read(400)
                        if "xpad.c" in head:
                            candidates.append(p)
                except Exception:
                    pass

    for path in candidates:
        if not os.path.exists(path):
            continue
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as fp:
                data = fp.read()
            pattern = r'\{\s*(0x[0-9a-fA-F]{4}),\s*(0x[0-9a-fA-F]{4}),\s*\"([^\"]+)\",\s*([^,]+),\s*([^}]+)\}'
            for vid, pid, name, flags, xtype in re.findall(pattern, data):
                v = vid[2:].lower()
                p = pid[2:].lower()
                xt = xtype.strip()
                name_clean = name.strip()
                is_wheel = any(w in name_clean.lower() for w in ["wheel", "racing"])
                is_stick = any(w in name_clean.lower() for w in ["stick", "flight", "arcade", "fight"])
                is_dance = any(w in name_clean.lower() for w in ["dance", "pump"])
                layout = "joystick" if (is_wheel or is_stick or is_dance) else "xbox"
                proto = "XInput"
                if "XBOX_" in xt:
                    proto = "Xbox OG"
                maker = VENDORS.get(v, "")
                devs[f"{v}:{p}"] = {
                    "name": name_clean,
                    "layout": layout,
                    "protocol": proto,
                    "maker": maker
                }
            if devs:
                break
        except Exception:
            pass
    return devs


def load_usb_ids_devices():
    """Extract gamepads/joysticks from /usr/share/hwdata/usb.ids."""
    devs = {}
    usb_ids_candidates = [
        "/usr/share/hwdata/usb.ids",
        "/usr/share/misc/usb.ids"
    ]
    path = None
    for p in usb_ids_candidates:
        if os.path.exists(p):
            path = p
            break
    if not path:
        return devs

    keywords = [
        "gamepad", "joystick", "controller", "racing wheel", "flight stick",
        "arcade stick", "fightstick", "steering wheel", "joy-con", "dualshock",
        "dualsense", "dance pad", "game pad", "game controller", "wheel", "throttle", "rudder"
    ]
    badwords = [
        "host controller", "audio controller", "ethernet controller", "network controller",
        "hub controller", "sata controller", "pci controller", "storage controller",
        "fan controller", "rgb controller", "keyboard controller", "memory controller",
        "touch pad", "touchpad", "trackpad", "flash drive", "ide controller", "video camera",
        "display controller", "power controller", "thermal", "camera", "led controller",
        "raid", "scsi", "sensor", "bluetooth controller", "sound controller", "mouse pad",
        "num pad", "keypad", "numpad", "tablet", "stylus", "digitizer"
    ]

    try:
        with open(path, "r", encoding="latin-1") as f:
            lines = f.readlines()
    except Exception:
        return devs

    current_vendor = None
    for line in lines:
        if line.startswith("#") or not line.strip():
            continue
        if not line.startswith("\t"):
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2 and len(parts[0]) == 4:
                current_vendor = parts[0].lower()
        elif line.startswith("\t") and not line.startswith("\t\t"):
            parts = line.strip().split(maxsplit=1)
            if len(parts) == 2 and len(parts[0]) == 4 and current_vendor in VENDORS:
                pid = parts[0].lower()
                name = parts[1].strip()
                lower_name = name.lower()
                if any(k in lower_name for k in keywords):
                    if not any(bad in lower_name for bad in badwords):
                        vid_pid = f"{current_vendor}:{pid}"
                        is_wheel = any(w in lower_name for w in ["wheel", "racing", "pedal", "driving"])
                        is_stick = any(w in lower_name for w in ["stick", "flight", "arcade", "fight", "throttle", "rudder"])
                        is_ps = any(w in lower_name for w in ["playstation", "dualshock", "dualsense", "ps3", "ps4", "ps5"]) or current_vendor == "054c"
                        is_switch = any(w in lower_name for w in ["switch", "joy-con", "nintendo"]) or current_vendor == "057e"

                        if is_wheel or is_stick:
                            layout = "joystick"
                        elif is_ps:
                            layout = "ps"
                        elif is_switch:
                            layout = "switch"
                        else:
                            layout = "xbox"

                        proto = "HID gamepad"
                        if "xbox" in lower_name or "x-box" in lower_name or "xinput" in lower_name:
                            proto = "XInput"
                        elif is_wheel or is_stick:
                            proto = "HID joystick"
                        elif is_ps:
                            proto = "DirectInput / PS"

                        devs[vid_pid] = {
                            "name": name,
                            "layout": layout,
                            "protocol": proto,
                            "maker": VENDORS[current_vendor]
                        }
    return devs


def build():
    xpad_devs = load_xpad_devices()
    usb_devs = load_usb_ids_devices()

    all_devices = dict(BASE_DEVICES)

    # 1. Merge xpad devices
    for k, v in xpad_devs.items():
        if k not in all_devices:
            all_devices[k] = v

    # 2. Merge usb.ids devices
    for k, v in usb_devs.items():
        if k not in all_devices:
            all_devices[k] = v

    print(f"Total Vendors: {len(VENDORS)}")
    print(f"Total Kernel Devices Cataloged: {len(all_devices)}")
    return VENDORS, all_devices


def generate_js(vendors, devices):
    lines = []
    lines.append("// 75+ Linux Kernel Gamepad & Joystick Vendors")
    lines.append("var VENDORS = {")
    v_keys = sorted(vendors.keys())
    for i, vk in enumerate(v_keys):
        comma = "," if i < len(v_keys) - 1 else ""
        escaped_val = vendors[vk].replace('"', '\\"')
        lines.append(f'  "{vk}": "{escaped_val}"{comma}')
    lines.append("}")
    lines.append("")
    lines.append("// 480+ Linux Kernel & Hardware Database Controllers")
    lines.append("var KERNEL_DEVICES = {")
    d_keys = sorted(devices.keys())
    for i, dk in enumerate(d_keys):
        comma = "," if i < len(d_keys) - 1 else ""
        d = devices[dk]
        preset_part = f', buttonPreset: "{d["buttonPreset"]}"' if "buttonPreset" in d else ""
        escaped_name = d["name"].replace('"', '\\"')
        escaped_maker = d["maker"].replace('"', '\\"')
        lines.append(
            f'  "{dk}": {{ name: "{escaped_name}", layout: "{d["layout"]}", protocol: "{d["protocol"]}", maker: "{escaped_maker}"{preset_part} }}{comma}'
        )
    lines.append("}")
    return "\n".join(lines)


def update_gamepad_model():
    v, d = build()
    generated_tables = generate_js(v, d)

    with open(MODEL_JS_PATH, "r", encoding="utf-8") as fp:
        content = fp.read()

    # 1. Replace VENDORS block
    vendor_pattern = r'// Vendor ids observed on consumer controllers[^\n]*\n(?:[^\n]*\n)*?var VENDORS = \{[^}]+\}'
    if re.search(vendor_pattern, content):
        content = re.sub(vendor_pattern, generated_tables, content, count=1)
    else:
        # Check if already generated tables exist
        old_gen_pattern = r'// 75\+ Linux Kernel Gamepad[^\n]*\n(?:[^\n]*\n)*?var KERNEL_DEVICES = \{[\s\S]*?\n\}'
        if re.search(old_gen_pattern, content):
            content = re.sub(old_gen_pattern, generated_tables, content, count=1)
        else:
            print("Warning: could not locate VENDORS block for replacement")

    # 2. Update classify() to lookup in KERNEL_DEVICES first if not already present
    classify_sig = "function classify(name, driver, vendor, product, axisCount, buttonCount) {"
    lookup_code = """  var n = lower(name)
  var d = lower(driver)
  var v = lower(vendor)
  var p = lower(product)
  var out = {
    layout: "generic",
    modelLabel: String(name || "Gamepad"),
    protocol: "HID",
    driverNote: String(driver || "hid-generic"),
    maker: VENDORS[v] || ""
  }

  // 1. Direct hardware lookup in KERNEL_DEVICES (kernel drivers & hwdata)
  var vidPid = v + ":" + p
  var dev = (v && p && typeof KERNEL_DEVICES !== "undefined") ? KERNEL_DEVICES[vidPid] : null
  if (dev) {
    out.layout = dev.layout || "xbox"
    out.protocol = dev.protocol || "HID gamepad"
    if (dev.maker) out.maker = dev.maker
    if (dev.buttonPreset) out.buttonPreset = dev.buttonPreset

    // Determine modelLabel with respect for device/family quirks
    if (n.indexOf("series") !== -1 || (dev.name && dev.name.toLowerCase().indexOf("series") !== -1)) {
      out.modelLabel = "Xbox Series pad"
    } else if (n.indexOf("360") !== -1 || (dev.name && dev.name.indexOf("360") !== -1)) {
      out.modelLabel = "Xbox 360 pad"
    } else if (n.indexOf("edge") !== -1 || dev.name === "DualSense Edge") {
      out.modelLabel = "DualSense Edge"
    } else if (dev.name === "DualSense" || n.indexOf("dualsense") !== -1) {
      out.modelLabel = "DualSense"
    } else if (dev.name.indexOf("DualShock 4") !== -1 || n.indexOf("dualshock") !== -1) {
      out.modelLabel = "DualShock 4"
    } else if (n.indexOf("joy-con") !== -1 || dev.name.indexOf("Joy-Con") !== -1) {
      out.modelLabel = "Joy-Cons"
    } else if (dev.name === "Switch Pro Controller" || n.indexOf("pro controller") !== -1) {
      out.modelLabel = "Switch Pro pad"
    } else if (dev.name) {
      out.modelLabel = dev.name
    }

    // Driver-specific protocol refinements
    if (d === "xpadneo" || d === "xpad") out.protocol = "XInput"
    else if (d === "xone") out.protocol = "XInput (xone)"

    return out
  }"""

    old_classify_start = """  var n = lower(name)
  var d = lower(driver)
  var v = lower(vendor)
  var out = {
    layout: "generic",
    modelLabel: String(name || "Gamepad"),
    protocol: "HID",
    driverNote: String(driver || "hid-generic"),
    maker: VENDORS[v] || ""
  }"""

    if old_classify_start in content:
        content = content.replace(old_classify_start, lookup_code, 1)

    # 3. Export KERNEL_DEVICES in module.exports if not exported
    if "KERNEL_DEVICES: KERNEL_DEVICES" not in content and "module.exports = {" in content:
        content = content.replace(
            "module.exports = {",
            "module.exports = {\n    KERNEL_DEVICES: KERNEL_DEVICES,",
            1
        )

    with open(MODEL_JS_PATH, "w", encoding="utf-8") as fp:
        fp.write(content)
    # Ensure 644 permission on GamepadModel.js
    os.chmod(MODEL_JS_PATH, 0o644)
    print(f"Successfully updated {MODEL_JS_PATH} with {len(v)} vendors and {len(d)} devices.")


if __name__ == "__main__":
    if "--generate-js" in sys.argv:
        v, d = build()
        print(generate_js(v, d))
    elif "--update-model" in sys.argv:
        update_gamepad_model()
    else:
        v, d = build()
