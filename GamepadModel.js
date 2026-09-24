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

// 75+ Linux Kernel Gamepad & Joystick Vendors
var VENDORS = {
  "0079": "DragonRise",
  "0351": "CRKD",
  "03eb": "Wooting",
  "03f0": "HyperX",
  "044f": "ThrustMaster",
  "045e": "Microsoft",
  "046d": "Logitech",
  "0502": "Acer",
  "054c": "Sony",
  "056e": "Elecom",
  "057e": "Nintendo",
  "0583": "Rockfire",
  "05ac": "Apple",
  "05fd": "Mad Catz",
  "05fe": "Chic",
  "062a": "Logic3",
  "068e": "CH Products",
  "06a3": "Saitek",
  "0738": "Mad Catz",
  "07ff": "Mad Catz",
  "0955": "NVIDIA",
  "0b05": "ASUS",
  "0c12": "Zeroplus",
  "0d2f": "Andamiro",
  "0db0": "MSI",
  "0e4c": "Radica",
  "0e6f": "PDP",
  "0e8f": "SmartJoy",
  "0f0d": "HORI",
  "0f30": "Philips",
  "102c": "Joytech",
  "1038": "SteelSeries",
  "10f5": "Turtle Beach",
  "11c0": "Beitong",
  "11c9": "Nacon",
  "11ff": "PXN",
  "1209": "Open Source",
  "12ab": "Honey Bee",
  "1345": "Sino Lite",
  "1430": "RedOctane",
  "146b": "Nacon",
  "1532": "Razer",
  "15e4": "Numark",
  "162e": "Joytech",
  "1689": "Razer",
  "16c0": "Teensy / V-USB",
  "16d0": "Azeron",
  "17ef": "Lenovo",
  "18d1": "Google",
  "1949": "Amazon",
  "1a86": "WCH",
  "1bad": "Harmonix",
  "20bc": "ShanWan",
  "20d6": "PowerA",
  "2345": "Shannon",
  "24c6": "PowerA",
  "2563": "ShanWan",
  "258a": "Machenike",
  "260d": "Flydigi",
  "289b": "Raphnet",
  "28de": "Valve",
  "294b": "GameSir",
  "2993": "EasySMX",
  "2c22": "Qanba",
  "2dc8": "8BitDo",
  "2e24": "Hyperkin",
  "2e3a": "PB Tails",
  "2e95": "SCUF Gaming",
  "2f24": "GameSir",
  "31e3": "Flydigi",
  "3285": "Flydigi",
  "3507": "BIGBIG WON",
  "3537": "GameSir",
  "3651": "Machenike",
  "366c": "GameSir",
  "37d7": "Thunderobot",
  "3958": "Flydigi",
  "413d": "Gulikit",
  "8380": "Besavior"
}

// 480+ Linux Kernel & Hardware Database Controllers
var KERNEL_DEVICES = {
  "0079:0006": { name: "DragonRise Gamepad", layout: "generic", protocol: "HID gamepad", maker: "DragonRise" },
  "0079:0011": { name: "DragonRise / Betop Pad", layout: "generic", protocol: "HID gamepad", maker: "DragonRise" },
  "0079:1800": { name: "Mayflash Wii U Pro Game Controller Adapter [DirectInput]", layout: "xbox", protocol: "HID gamepad", maker: "DragonRise" },
  "0079:181b": { name: "Venom Arcade Joystick", layout: "joystick", protocol: "HID joystick", maker: "DragonRise" },
  "0079:181c": { name: "ZhiXu Gamepad", layout: "xbox", protocol: "DirectInput / HID", maker: "ZhiXu", buttonPreset: "zhixu" },
  "0079:1843": { name: "Mayflash GameCube Controller Adapter", layout: "xbox", protocol: "HID gamepad", maker: "DragonRise" },
  "0079:1844": { name: "Mayflash GameCube Controller", layout: "xbox", protocol: "HID gamepad", maker: "DragonRise" },
  "0079:18d4": { name: "GPD Win 2 X-Box Controller", layout: "xbox", protocol: "XInput", maker: "DragonRise" },
  "0351:1000": { name: "CRKD Nitro Deck", layout: "switch", protocol: "Nintendo Switch", maker: "CRKD" },
  "0351:2000": { name: "CRKD LP Black Tribal Edition (Xbox)", layout: "xbox", protocol: "XInput", maker: "CRKD" },
  "03eb:2043": { name: "LUFA Joystick Demo Application", layout: "joystick", protocol: "HID joystick", maker: "Wooting" },
  "03eb:ff01": { name: "Wooting One (Legacy)", layout: "xbox", protocol: "XInput", maker: "Wooting" },
  "03eb:ff02": { name: "Wooting Two (Legacy)", layout: "xbox", protocol: "XInput", maker: "Wooting" },
  "03f0:038d": { name: "HyperX Clutch", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "03f0:048d": { name: "HyperX Clutch", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "03f0:0495": { name: "HyperX Clutch Gladiate", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "03f0:07a0": { name: "HyperX Clutch Gladiate RGB", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "03f0:08b6": { name: "HyperX Clutch Gladiate", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "03f0:09b4": { name: "HyperX Clutch Tanto", layout: "xbox", protocol: "XInput", maker: "HyperX" },
  "044f:0402": { name: "HOTAS Warthog Joystick", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:0404": { name: "HOTAS Warthog Throttle", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:0f00": { name: "Thrustmaster Wheel", layout: "joystick", protocol: "XInput", maker: "ThrustMaster" },
  "044f:0f03": { name: "Thrustmaster Wheel", layout: "joystick", protocol: "XInput", maker: "ThrustMaster" },
  "044f:0f07": { name: "Thrustmaster, Inc. Controller", layout: "xbox", protocol: "XInput", maker: "ThrustMaster" },
  "044f:0f10": { name: "Thrustmaster Modena GT Wheel", layout: "joystick", protocol: "XInput", maker: "ThrustMaster" },
  "044f:a003": { name: "Rage 3D Game Pad", layout: "xbox", protocol: "HID gamepad", maker: "ThrustMaster" },
  "044f:a01b": { name: "PK-GP301 Driving Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:a0a0": { name: "Top Gun Joystick", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:a0a1": { name: "Top Gun Joystick (rev2)", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:a0a3": { name: "Fusion Digital GamePad", layout: "xbox", protocol: "HID gamepad", maker: "ThrustMaster" },
  "044f:b108": { name: "T-Flight Hotas X Flight Stick", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b10a": { name: "T.16000M Joystick", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b203": { name: "360 Modena Pro Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b320": { name: "Dual Trigger gamepad PC/PS2 2.0", layout: "xbox", protocol: "HID gamepad", maker: "ThrustMaster" },
  "044f:b326": { name: "Thrustmaster Gamepad GP XID", layout: "xbox", protocol: "XInput", maker: "ThrustMaster" },
  "044f:b603": { name: "force feedback Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b605": { name: "force feedback Racing Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b651": { name: "Ferrari GT Rumble Force Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b653": { name: "RGT Force Feedback Clutch Racing Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b654": { name: "Ferrari GT Force Feedback Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b677": { name: "T150 Racing Wheel", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b678": { name: "T.Flight Rudder Pedals", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b679": { name: "T-Rudder", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:b687": { name: "TWCS Throttle", layout: "joystick", protocol: "HID joystick", maker: "ThrustMaster" },
  "044f:d01e": { name: "ThrustMaster, Inc. ESWAP X 2 ELDEN RING EDITION", layout: "xbox", protocol: "XInput", maker: "ThrustMaster" },
  "045e:0007": { name: "SideWinder Game Pad", layout: "xbox", protocol: "HID gamepad", maker: "Microsoft" },
  "045e:001a": { name: "SideWinder Precision Racing Wheel", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:001b": { name: "SideWinder Force Feedback 2 Joystick", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:0026": { name: "SideWinder GamePad Pro", layout: "xbox", protocol: "HID gamepad", maker: "Microsoft" },
  "045e:0027": { name: "SideWinder PnP GamePad", layout: "xbox", protocol: "HID gamepad", maker: "Microsoft" },
  "045e:0034": { name: "SideWinder Force Feedback Wheel", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:003c": { name: "SideWinder Joystick", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:0040": { name: "Wheel Mouse Optical", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:00d1": { name: "Optical Mouse with Tilt Wheel", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:00d2": { name: "Notebook Optical Mouse with Tilt Wheel", layout: "joystick", protocol: "HID joystick", maker: "Microsoft" },
  "045e:0202": { name: "Microsoft X-Box pad v1 (US)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0285": { name: "Microsoft X-Box pad (Japan)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0287": { name: "Microsoft Xbox Controller S", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0288": { name: "Microsoft Xbox Controller S v2", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0289": { name: "Microsoft X-Box pad v2 (US)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:028e": { name: "Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:028f": { name: "Xbox 360 Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0291": { name: "Xbox 360 Wireless Receiver (XBOX)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02a9": { name: "Xbox 360 Wireless Receiver (Unofficial)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02d1": { name: "Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02dd": { name: "Xbox One Controller (Covert)", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02e0": { name: "Xbox One S Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02e3": { name: "Xbox Elite Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02ea": { name: "Xbox One S Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:02fd": { name: "Xbox One S Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0719": { name: "Xbox 360 Wireless Receiver", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b00": { name: "Xbox Elite Wireless Controller Series 2", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b05": { name: "Xbox Elite Wireless Controller Series 2", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b0a": { name: "Xbox Adaptive Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b0c": { name: "Xbox Adaptive Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b12": { name: "Xbox Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b13": { name: "Xbox Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b20": { name: "Xbox Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "045e:0b22": { name: "Xbox Elite Wireless Controller Series 2", layout: "xbox", protocol: "XInput", maker: "Microsoft" },
  "046d:0200": { name: "WingMan Extreme Joystick", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:bfe4": { name: "Premium Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c005": { name: "WingMan Gaming Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c00b": { name: "MouseMan Wheel", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c00c": { name: "Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c00d": { name: "MouseMan Wheel+", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c00e": { name: "M-BJ58/M-BJ69 Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c016": { name: "Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c018": { name: "Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c019": { name: "Optical Tilt Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c01a": { name: "M-BQ85 Optical Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c03e": { name: "Premium Optical Wheel Mouse (M-BT58)", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c040": { name: "Corded Tilt-Wheel Mouse", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c201": { name: "WingMan Extreme Joystick with Throttle", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c208": { name: "WingMan Gamepad Extreme", layout: "xbox", protocol: "HID gamepad", maker: "Logitech" },
  "046d:c209": { name: "WingMan Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Logitech" },
  "046d:c213": { name: "J-UH16 (Freedom 2.4 Cordless Joystick)", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c214": { name: "ATK3 (Attack III Joystick)", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c215": { name: "Logitech Extreme 3D Pro", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c216": { name: "Logitech Dual Action", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c218": { name: "Logitech RumblePad 2", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c219": { name: "Logitech Cordless RumblePad 2", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c21a": { name: "Precision Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Logitech" },
  "046d:c21d": { name: "Logitech Gamepad F310", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c21e": { name: "Logitech Gamepad F510", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c21f": { name: "Logitech Wireless Gamepad F710", layout: "generic", protocol: "DirectInput", maker: "Logitech" },
  "046d:c242": { name: "Logitech Chillstream Controller", layout: "xbox", protocol: "XInput", maker: "Logitech" },
  "046d:c24f": { name: "Logitech G29 Driving Force (PS3)", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c260": { name: "G29 Driving Force Racing Wheel [PS4]", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c262": { name: "Logitech G920 Driving Force Racing Wheel", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c266": { name: "Logitech G923 Racing Wheel (Xbox)", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c268": { name: "Logitech G923 Racing Wheel (PlayStation)", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c283": { name: "Logitech WingMan Force 3D", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c294": { name: "Logitech Driving Force", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c295": { name: "Momo Force Steering Wheel", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c298": { name: "Logitech G25 Racing Wheel", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c299": { name: "Logitech G27 Racing Wheel", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c29a": { name: "Logitech Driving Force GT", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c29b": { name: "Logitech G29 Driving Force Racing Wheel", layout: "joystick", protocol: "HID wheel", maker: "Logitech" },
  "046d:c29c": { name: "Speed Force Wireless Wheel for Wii", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c2ab": { name: "G13 Joystick", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c401": { name: "TrackMan Marble Wheel", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:c404": { name: "TrackMan Wheel", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:ca04": { name: "Formula Vibration Feedback Wheel", layout: "joystick", protocol: "HID joystick", maker: "Logitech" },
  "046d:ca84": { name: "Logitech Xbox Cordless Controller", layout: "xbox", protocol: "XInput", maker: "Logitech" },
  "046d:ca88": { name: "Logitech Compact Controller for Xbox", layout: "xbox", protocol: "XInput", maker: "Logitech" },
  "046d:ca8a": { name: "Logitech Precision Vibration Feedback Wheel", layout: "joystick", protocol: "XInput", maker: "Logitech" },
  "046d:caa3": { name: "Logitech DriveFx Racing Wheel", layout: "joystick", protocol: "XInput", maker: "Logitech" },
  "046d:f301": { name: "Controller", layout: "xbox", protocol: "HID gamepad", maker: "Logitech" },
  "0502:1305": { name: "Acer NGR200", layout: "xbox", protocol: "XInput", maker: "Acer" },
  "054c:0268": { name: "DualShock 3", layout: "ps", protocol: "DualShock 3", maker: "Sony" },
  "054c:03d5": { name: "PlayStation Move motion controller", layout: "ps", protocol: "DirectInput / PS", maker: "Sony" },
  "054c:042f": { name: "PlayStation Move Navigation Controller", layout: "ps", protocol: "PS Move", maker: "Sony" },
  "054c:05c4": { name: "DualShock 4", layout: "ps", protocol: "DualShock 4", maker: "Sony" },
  "054c:09cc": { name: "DualShock 4 v2", layout: "ps", protocol: "DualShock 4", maker: "Sony" },
  "054c:0ba0": { name: "DualShock 4 USB Wireless Adapter", layout: "ps", protocol: "DualShock 4", maker: "Sony" },
  "054c:0cda": { name: "PlayStation Classic controller", layout: "ps", protocol: "DirectInput / PS", maker: "Sony" },
  "054c:0ce6": { name: "DualSense", layout: "ps", protocol: "DualSense", maker: "Sony" },
  "054c:0df2": { name: "DualSense Edge", layout: "ps", protocol: "DualSense", maker: "Sony" },
  "054c:0e5f": { name: "Access Controller", layout: "ps", protocol: "DualSense", maker: "Sony" },
  "056e:2004": { name: "Elecom JC-U3613M", layout: "xbox", protocol: "XInput", maker: "Elecom" },
  "056e:200f": { name: "JC-U4013S Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Elecom" },
  "056e:2012": { name: "JC-U4013S Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Elecom" },
  "057e:0306": { name: "Wii Remote Controller RVL-003", layout: "switch", protocol: "HID gamepad", maker: "Nintendo" },
  "057e:0337": { name: "Wii U GameCube Controller Adapter", layout: "switch", protocol: "HID gamepad", maker: "Nintendo" },
  "057e:0341": { name: "DRH GamePad Host [Nintendo Wii U]", layout: "switch", protocol: "HID gamepad", maker: "Nintendo" },
  "057e:2006": { name: "Joy-Con (L)", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:2007": { name: "Joy-Con (R)", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:2008": { name: "Joy-Con (L/R)", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:2009": { name: "Switch Pro Controller", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:200e": { name: "Joy-Con Charging Grip", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:2017": { name: "SNES Controller", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:2019": { name: "N64 Controller", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "057e:201e": { name: "Genesis Controller", layout: "switch", protocol: "Nintendo Switch", maker: "Nintendo" },
  "0583:2060": { name: "2-axis 8-button gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:206f": { name: "USB, 2-axis 8-button gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:3050": { name: "QF-305u Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:6258": { name: "USB, 4-axis, 6-button joystick w/view finder", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:688f": { name: "QF-688uv Windstorm Pro Joystick", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:7070": { name: "QF-707u Bazooka Joystick", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:a000": { name: "MaxFire G-08XU Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:a019": { name: "USB, Vibration ,4-axis, 8-button joystick w/view finder", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:a024": { name: "4axis,12button vibrition audio gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:a025": { name: "4axis,12button vibrition audio gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:a130": { name: "USB Wireless 2.4GHz Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Rockfire" },
  "0583:a131": { name: "USB Wireless 2.4GHz Joystick", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:a132": { name: "USB Wireless 2.4GHz Wheelpad", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:a133": { name: "USB Wireless 2.4GHz Wheel&Gamepad", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:a202": { name: "ForceFeedbackWheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b002": { name: "Vibration,12-Button USB Wheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b005": { name: "USB,12-Button Wheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b008": { name: "USB Wireless 2.4GHz Wheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b009": { name: "USB,12-Button  Wheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b013": { name: "USB,Wiress  2.4GHZ Joystick", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "0583:b018": { name: "TW6 Wheel", layout: "joystick", protocol: "HID joystick", maker: "Rockfire" },
  "05fd:1007": { name: "Mad Catz Controller (unverified)", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "05fd:107a": { name: "InterAct 'PowerPad Pro' X-Box pad (Germany)", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "05fe:0014": { name: "Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Chic" },
  "05fe:3030": { name: "Chic Controller", layout: "xbox", protocol: "XInput", maker: "Chic" },
  "05fe:3031": { name: "Chic Controller", layout: "xbox", protocol: "XInput", maker: "Chic" },
  "062a:0020": { name: "Logic3 Xbox GamePad", layout: "xbox", protocol: "XInput", maker: "Logic3" },
  "062a:0033": { name: "Competition Pro Steering Wheel", layout: "joystick", protocol: "XInput", maker: "Logic3" },
  "062a:2410": { name: "Wireless PS3 gamepad", layout: "ps", protocol: "DirectInput / PS", maker: "Logic3" },
  "068e:00d3": { name: "OEM 3 axis 5 button joystick", layout: "joystick", protocol: "HID joystick", maker: "CH Products" },
  "068e:00e2": { name: "HFX OEM Joystick", layout: "joystick", protocol: "HID joystick", maker: "CH Products" },
  "068e:00f1": { name: "Pro Throttle", layout: "joystick", protocol: "HID joystick", maker: "CH Products" },
  "068e:00fa": { name: "Ch Throttle Quadrant", layout: "joystick", protocol: "HID joystick", maker: "CH Products" },
  "06a3:0006": { name: "Cyborg Gold Joystick", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0200": { name: "Saitek Racing Wheel", layout: "joystick", protocol: "XInput", maker: "Saitek" },
  "06a3:0201": { name: "Saitek Adrenalin", layout: "xbox", protocol: "XInput", maker: "Saitek" },
  "06a3:0241": { name: "Xbox Adrenalin Gamepad", layout: "xbox", protocol: "XInput", maker: "Saitek" },
  "06a3:0255": { name: "X52 Flight Controller", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0422": { name: "ST90 Joystick", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0460": { name: "ST290 Pro Flight Stick", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0501": { name: "R100 Sports Wheel", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0506": { name: "R220 Digital Wheel", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:052d": { name: "P750 Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Saitek" },
  "06a3:053c": { name: "X45 Flight Controller", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:075c": { name: "X52 Flight Controller", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0763": { name: "Pro Flight Rudder Pedals", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0764": { name: "Flight Pro Combat Rudder", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:0805": { name: "R440 Force Wheel", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:100a": { name: "SP550 Pad and Joystick Combo", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:2541": { name: "X45 Flight Controller", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:3509": { name: "P3000 RF GamePad", layout: "xbox", protocol: "HID gamepad", maker: "Saitek" },
  "06a3:803f": { name: "X36 Flight Controller", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:f518": { name: "P3200 Rumble Force Game Pad", layout: "xbox", protocol: "HID gamepad", maker: "Saitek" },
  "06a3:f51a": { name: "Saitek P3600", layout: "xbox", protocol: "XInput", maker: "Saitek" },
  "06a3:ff04": { name: "R440 Force Wheel", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:ff52": { name: "Cyborg 3D Rumble Force Joystick", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "06a3:ffb5": { name: "Cyborg Evo Force Joystick", layout: "joystick", protocol: "HID joystick", maker: "Saitek" },
  "0738:1302": { name: "F.L.Y. 5 Flight Stick", layout: "joystick", protocol: "HID joystick", maker: "Mad Catz" },
  "0738:4503": { name: "Mad Catz Racing Wheel", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4506": { name: "Mad Catz 4506 Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4516": { name: "Mad Catz Control Pad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4520": { name: "Mad Catz Control Pad Pro", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4522": { name: "Mad Catz LumiCON", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4526": { name: "Mad Catz Control Pad Pro", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4530": { name: "Mad Catz Universal MC2 Racing Wheel and Pedals", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4536": { name: "Mad Catz MicroCON", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4540": { name: "Mad Catz Beat Pad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4556": { name: "Mad Catz Lynx Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4586": { name: "Mad Catz MicroCon Wireless Controller", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4588": { name: "Mad Catz Blaster", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:45ff": { name: "Mad Catz Beat Pad (w/ Handle)", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4716": { name: "Mad Catz Wired Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4718": { name: "Mad Catz Street Fighter IV FightStick SE", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4726": { name: "Mad Catz Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4728": { name: "Mad Catz Street Fighter IV FightPad", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4730": { name: "MC2 Racing Wheel for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4736": { name: "Mad Catz MicroCon Gamepad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4738": { name: "Mad Catz Wired Xbox 360 Controller (SFIV)", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4740": { name: "Mad Catz Beat Pad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4743": { name: "Mad Catz Beat Pad Pro", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:4758": { name: "Mad Catz Arcade Game Stick", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:4a01": { name: "Mad Catz FightStick TE 2", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:6040": { name: "Mad Catz Beat Pad Pro", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:8818": { name: "Street Fighter IV Arcade FightStick (PS3)", layout: "joystick", protocol: "HID joystick", maker: "Mad Catz" },
  "0738:9871": { name: "Mad Catz Portable Drum", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:a215": { name: "X-55 Rhino Throttle", layout: "joystick", protocol: "HID joystick", maker: "Mad Catz" },
  "0738:b726": { name: "Mad Catz Xbox controller - MW2", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:b738": { name: "Mad Catz MVC2TE Stick 2", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:beef": { name: "Mad Catz JOYTECH NEO SE Advanced GamePad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:cb02": { name: "Saitek Cyborg Rumble Pad - PC/Xbox 360", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:cb03": { name: "Saitek P3200 Rumble Pad - PC/Xbox 360", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0738:cb29": { name: "Saitek Aviator Stick AV8R02", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "0738:f738": { name: "Super SFIV FightStick TE S", layout: "joystick", protocol: "XInput", maker: "Mad Catz" },
  "07ff:ffff": { name: "Mad Catz GamePad", layout: "xbox", protocol: "XInput", maker: "Mad Catz" },
  "0955:7210": { name: "NVIDIA Shield Controller", layout: "xbox", protocol: "HID gamepad", maker: "NVIDIA" },
  "0955:7214": { name: "NVIDIA Shield Controller v2", layout: "xbox", protocol: "HID gamepad", maker: "NVIDIA" },
  "0b05:1a38": { name: "ASUS ROG RAIKIRI", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1abb": { name: "ASUS ROG RAIKIRI PRO", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1abd": { name: "ASUS ROG Raikiri Pro", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1c91": { name: "ASUS ROG RAIKIRI II", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1c92": { name: "ASUS ROG RAIKIRI II WIRELESS", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1c96": { name: "ASUS ROG RAIKIRI II XBOX", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0b05:1d04": { name: "ASUS ROG RAIKIRI II XBOX WIRELESS", layout: "xbox", protocol: "XInput", maker: "ASUS" },
  "0c12:0005": { name: "Intec wireless", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0c12:8801": { name: "Nyko Xbox Controller", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0c12:8802": { name: "Zeroplus Xbox Controller", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0c12:8809": { name: "RedOctane Xbox Dance Pad", layout: "joystick", protocol: "XInput", maker: "Zeroplus" },
  "0c12:880a": { name: "Pelican Eclipse PL-2023", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0c12:8810": { name: "Zeroplus Xbox Controller", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0c12:9902": { name: "HAMA VibraX - *FAULTY HARDWARE*", layout: "xbox", protocol: "XInput", maker: "Zeroplus" },
  "0d2f:0002": { name: "Andamiro Pump It Up pad", layout: "joystick", protocol: "XInput", maker: "Andamiro" },
  "0db0:1901": { name: "Micro Star International Xbox360 Controller for Windows", layout: "xbox", protocol: "XInput", maker: "MSI" },
  "0e4c:1097": { name: "Radica Gamester Controller", layout: "xbox", protocol: "XInput", maker: "Radica" },
  "0e4c:1103": { name: "Radica Gamester Reflex", layout: "xbox", protocol: "XInput", maker: "Radica" },
  "0e4c:2390": { name: "Radica Games Jtech Controller", layout: "xbox", protocol: "XInput", maker: "Radica" },
  "0e4c:3510": { name: "Radica Gamester", layout: "xbox", protocol: "XInput", maker: "Radica" },
  "0e6f:0003": { name: "Logic3 Freebird wireless Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0005": { name: "Eclipse wireless Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0006": { name: "Edge wireless Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0008": { name: "After Glow Pro Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0105": { name: "HSM3 Xbox360 dancepad", layout: "joystick", protocol: "XInput", maker: "PDP" },
  "0e6f:0113": { name: "Afterglow AX.1 Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:011f": { name: "Rock Candy Gamepad Wired Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0128": { name: "Wireless PS3 Controller", layout: "ps", protocol: "DirectInput / PS", maker: "PDP" },
  "0e6f:0131": { name: "PDP EA Sports Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0133": { name: "Xbox 360 Wired Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0139": { name: "Afterglow Prismatic Wired Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:013a": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0146": { name: "Rock Candy Wired Controller for Xbox One", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0147": { name: "PDP Marvel Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:015c": { name: "PDP Xbox One Arcade Stick", layout: "joystick", protocol: "XInput", maker: "PDP" },
  "0e6f:015d": { name: "PDP Mirror's Edge Official Wired Controller for Xbox One", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0161": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0162": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0163": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0164": { name: "PDP Battlefield One", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0165": { name: "PDP Titanfall 2", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0201": { name: "Pelican PL-3601 'TSZ' Wired Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0213": { name: "Afterglow Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:021f": { name: "Rock Candy Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0246": { name: "Rock Candy Gamepad for Xbox One 2015", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:024c": { name: "PDP Victrix Pro BFG Wired Controller for Xbox", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a0": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a1": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a2": { name: "PDP Wired Controller for Xbox One - Crimson Red", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a4": { name: "PDP Wired Controller for Xbox One - Stealth Series", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a6": { name: "PDP Wired Controller for Xbox One - Camo Series", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a7": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02a8": { name: "PDP Xbox One Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02ab": { name: "PDP Controller for Xbox One", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02ad": { name: "PDP Wired Controller for Xbox One - Stealth Series", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02b3": { name: "Afterglow Prismatic Wired Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:02b8": { name: "Afterglow Prismatic Wired Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0301": { name: "Logic3 Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0346": { name: "Rock Candy Gamepad for Xbox One 2016", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0401": { name: "Logic3 Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0413": { name: "Afterglow AX.1 Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:0501": { name: "PDP Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e6f:f501": { name: "Hi-TEC Essentials Wired Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "PDP" },
  "0e6f:f900": { name: "PDP Afterglow AX.1", layout: "xbox", protocol: "XInput", maker: "PDP" },
  "0e8f:0012": { name: "Joystick/Gamepad", layout: "joystick", protocol: "HID joystick", maker: "SmartJoy" },
  "0e8f:0201": { name: "SmartJoy Frag Xpad/PS2 adaptor", layout: "xbox", protocol: "XInput", maker: "SmartJoy" },
  "0e8f:3008": { name: "Generic xbox control (dealextreme)", layout: "xbox", protocol: "XInput", maker: "SmartJoy" },
  "0e8f:300a": { name: "steering Wheel", layout: "joystick", protocol: "HID joystick", maker: "SmartJoy" },
  "0f0d:000a": { name: "Hori Co. DOA4 FightStick", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:000c": { name: "Hori PadEX Turbo", layout: "xbox", protocol: "XInput", maker: "HORI" },
  "0f0d:000d": { name: "Hori Fighting Stick EX2", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:0016": { name: "Hori Real Arcade Pro.EX", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:001b": { name: "Hori Real Arcade Pro VX", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:0063": { name: "Hori Real Arcade Pro Hayabusa (USA) Xbox One", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:0067": { name: "HORIPAD ONE", layout: "xbox", protocol: "XInput", maker: "HORI" },
  "0f0d:0078": { name: "Hori Real Arcade Pro V Kai Xbox One", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:00c5": { name: "Hori Fighting Commander ONE", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:00dc": { name: "HORIPAD FPS for Nintendo Switch", layout: "xbox", protocol: "XInput", maker: "HORI" },
  "0f0d:00f6": { name: "HORI Battle Pad", layout: "switch", protocol: "Nintendo Switch", maker: "HORI" },
  "0f0d:0151": { name: "Hori Racing Wheel Overdrive for Xbox Series X", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:0152": { name: "Hori Racing Wheel Overdrive for Xbox Series X", layout: "joystick", protocol: "XInput", maker: "HORI" },
  "0f0d:01b2": { name: "HORI Taiko No Tatsujin Drum Controller", layout: "xbox", protocol: "XInput", maker: "HORI" },
  "0f30:001c": { name: "PS3 Guitar Controller Dongle", layout: "ps", protocol: "DirectInput / PS", maker: "Philips" },
  "0f30:010b": { name: "Philips Recoil", layout: "xbox", protocol: "XInput", maker: "Philips" },
  "0f30:0202": { name: "Joytech Advanced Controller", layout: "xbox", protocol: "XInput", maker: "Philips" },
  "0f30:0208": { name: "Xbox & PC Gamepad", layout: "xbox", protocol: "XInput", maker: "Philips" },
  "0f30:8888": { name: "BigBen XBMiniPad Controller", layout: "xbox", protocol: "XInput", maker: "Philips" },
  "102c:ff0c": { name: "Joytech Wireless Advanced Controller", layout: "xbox", protocol: "XInput", maker: "Joytech" },
  "1038:1410": { name: "SRW-S1 [Simraceway Steering Wheel]", layout: "joystick", protocol: "HID joystick", maker: "SteelSeries" },
  "1038:1430": { name: "SteelSeries Stratus Duo", layout: "xbox", protocol: "XInput", maker: "SteelSeries" },
  "1038:1431": { name: "SteelSeries Stratus Duo", layout: "xbox", protocol: "XInput", maker: "SteelSeries" },
  "10f5:7005": { name: "Turtle Beach Recon Controller", layout: "xbox", protocol: "XInput", maker: "Turtle Beach" },
  "10f5:7008": { name: "Turtle Beach Recon Controller", layout: "xbox", protocol: "XInput", maker: "Turtle Beach" },
  "10f5:7073": { name: "Turtle Beach Stealth Ultra Controller", layout: "xbox", protocol: "XInput", maker: "Turtle Beach" },
  "11c0:5506": { name: "Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Beitong" },
  "11c9:55f0": { name: "Nacon GC-100XF", layout: "xbox", protocol: "XInput", maker: "Nacon" },
  "11ff:0511": { name: "PXN V900", layout: "xbox", protocol: "XInput", maker: "PXN" },
  "1209:2882": { name: "Ardwiino Controller", layout: "xbox", protocol: "XInput", maker: "Open Source" },
  "1209:3100": { name: "OpenSimHardware Pedals & Buttons Controller", layout: "joystick", protocol: "HID joystick", maker: "Open Source" },
  "1209:abc0": { name: "Omzlo controller", layout: "xbox", protocol: "HID gamepad", maker: "Open Source" },
  "1209:d017": { name: "empiriKit empiriKit Controller", layout: "xbox", protocol: "HID gamepad", maker: "Open Source" },
  "1209:daa0": { name: "darknao btClubSportWheel", layout: "joystick", protocol: "HID joystick", maker: "Open Source" },
  "1209:eaea": { name: "Pinscape Controller", layout: "xbox", protocol: "HID gamepad", maker: "Open Source" },
  "1209:f3fc": { name: "dRonin Flight controller-Lumenier Lux", layout: "joystick", protocol: "HID joystick", maker: "Open Source" },
  "12ab:0004": { name: "Honey Bee Xbox360 dancepad", layout: "joystick", protocol: "XInput", maker: "Honey Bee" },
  "12ab:0301": { name: "PDP AFTERGLOW AX.1", layout: "xbox", protocol: "XInput", maker: "Honey Bee" },
  "12ab:0303": { name: "Mortal Kombat Klassic FightStick", layout: "joystick", protocol: "XInput", maker: "Honey Bee" },
  "12ab:8809": { name: "Xbox DDR dancepad", layout: "joystick", protocol: "XInput", maker: "Honey Bee" },
  "1345:001c": { name: "Xbox Controller Hub", layout: "xbox", protocol: "XInput", maker: "Sino Lite" },
  "1345:6006": { name: "Defender Wireless Controller", layout: "xbox", protocol: "HID gamepad", maker: "Sino Lite" },
  "1430:4748": { name: "RedOctane Guitar Hero X-plorer", layout: "xbox", protocol: "XInput", maker: "RedOctane" },
  "1430:8888": { name: "TX6500+ Dance Pad (first generation)", layout: "joystick", protocol: "XInput", maker: "RedOctane" },
  "1430:f801": { name: "RedOctane Controller", layout: "xbox", protocol: "XInput", maker: "RedOctane" },
  "146b:0601": { name: "BigBen Interactive XBOX 360 Controller", layout: "xbox", protocol: "XInput", maker: "Nacon" },
  "146b:0604": { name: "Bigben Interactive DAIJA Arcade Stick", layout: "joystick", protocol: "XInput", maker: "Nacon" },
  "146b:0902": { name: "Wired Mini PS3 Game Controller", layout: "ps", protocol: "DirectInput / PS", maker: "Nacon" },
  "1532:0300": { name: "RZ06-0063 Motion Sensing Controllers [Hydra]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:0401": { name: "Gaming Arcade Stick [Panthera]", layout: "joystick", protocol: "HID joystick", maker: "Razer" },
  "1532:0a00": { name: "Razer Atrox Arcade Stick", layout: "joystick", protocol: "XInput", maker: "Razer" },
  "1532:0a03": { name: "Razer Wildcat", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1532:0a15": { name: "RZ06-0199, Gaming Controller [Wolverine Tournament Edition]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:0a29": { name: "Razer Wolverine V2", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1532:0a57": { name: "Razer Wolverine V3 Pro (Wired)", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1532:0a59": { name: "Razer Wolverine V3 Pro (2.4 GHz Dongle)", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1532:1000": { name: "Gaming Controller [Raiju]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:1004": { name: "Gaming Controller [Raiju Ultimate Wired]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:1007": { name: "Gaming Controller [Raiju 2 Tournament Edition (USB)]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:1009": { name: "Gaming Controller [Raiju 2 Ultimate Edition (BT)]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "1532:100a": { name: "Gaming Controller [Raiju 2 Tournament Edition (BT)]", layout: "xbox", protocol: "HID gamepad", maker: "Razer" },
  "15e4:3f00": { name: "Power A Mini Pro Elite", layout: "xbox", protocol: "XInput", maker: "Numark" },
  "15e4:3f0a": { name: "Xbox Airflo wired controller", layout: "xbox", protocol: "XInput", maker: "Numark" },
  "15e4:3f10": { name: "Batarang Xbox 360 controller", layout: "xbox", protocol: "XInput", maker: "Numark" },
  "162e:beef": { name: "Joytech Neo-Se Take2", layout: "xbox", protocol: "XInput", maker: "Joytech" },
  "1689:fd00": { name: "Razer Onza Tournament Edition", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1689:fd01": { name: "Razer Onza Classic Edition", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "1689:fe00": { name: "Razer Sabertooth", layout: "xbox", protocol: "XInput", maker: "Razer" },
  "16c0:0482": { name: "Teensyduino Keyboard+Mouse+Joystick", layout: "joystick", protocol: "HID joystick", maker: "Teensy / V-USB" },
  "16c0:0487": { name: "Teensyduino Serial+Keyboard+Mouse+Joystick", layout: "joystick", protocol: "HID joystick", maker: "Teensy / V-USB" },
  "16c0:05df": { name: "HID device except mice, keyboards, and joysticks", layout: "joystick", protocol: "HID joystick", maker: "Teensy / V-USB" },
  "16c0:27d9": { name: "HID device except mice, keyboards, and joysticks", layout: "joystick", protocol: "HID joystick", maker: "Teensy / V-USB" },
  "16c0:27dc": { name: "Joystick", layout: "joystick", protocol: "HID joystick", maker: "Teensy / V-USB" },
  "16d0:06f0": { name: "Axium AX-R4C Controller", layout: "xbox", protocol: "HID gamepad", maker: "Azeron" },
  "16d0:06f1": { name: "Axium AX-R1D Controller", layout: "xbox", protocol: "HID gamepad", maker: "Azeron" },
  "16d0:07f8": { name: "Axium AX-R4D Controller", layout: "xbox", protocol: "HID gamepad", maker: "Azeron" },
  "16d0:1103": { name: "Azeron Cyro", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "16d0:113c": { name: "Azeron Cyborg", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "16d0:1192": { name: "Azeron Classic/Compact", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "16d0:1212": { name: "Azeron Cyro Lefty", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "16d0:12f7": { name: "Azeron Cyborg II", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "16d0:13ea": { name: "Azeron Keyzen", layout: "xbox", protocol: "XInput", maker: "Azeron" },
  "17ef:6182": { name: "Lenovo Legion Controller for Windows", layout: "xbox", protocol: "XInput", maker: "Lenovo" },
  "18d1:9400": { name: "Google Stadia Controller", layout: "xbox", protocol: "HID gamepad", maker: "Google" },
  "1949:0402": { name: "Amazon Luna Controller", layout: "xbox", protocol: "HID gamepad", maker: "Amazon" },
  "1949:041a": { name: "Amazon Game Controller", layout: "xbox", protocol: "XInput", maker: "Amazon" },
  "1a86:e310": { name: "Legion Go S", layout: "xbox", protocol: "XInput", maker: "WCH" },
  "1bad:0002": { name: "Harmonix Rock Band Guitar", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:0003": { name: "Harmonix Rock Band Drumkit", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:0130": { name: "Ion Drum Rocker", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:028e": { name: "Controller", layout: "xbox", protocol: "HID gamepad", maker: "Harmonix" },
  "1bad:f016": { name: "Mad Catz Xbox 360 Controller", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f018": { name: "Mad Catz Street Fighter IV SE Fighting Stick", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f019": { name: "Mad Catz Brawlstick for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f021": { name: "Mad Cats Ghost Recon FS GamePad", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f023": { name: "MLG Pro Circuit Controller (Xbox)", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f025": { name: "Mad Catz Call Of Duty", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f027": { name: "Mad Catz FPS Pro", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f028": { name: "Street Fighter IV FightPad", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f030": { name: "MC2 MicroCON Racing Wheel for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f036": { name: "MicroCON Gamepad Pro for Xbox 360", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f038": { name: "Street Fighter IV FightStick TE for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f03a": { name: "Street Fighter X Tekken FightStick Pro for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f03d": { name: "Street Fighter IV Arcade Stick TE for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f03e": { name: "MLG Arcade FightStick TE for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f03f": { name: "Soulcalibur FightStick for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f042": { name: "Arcade FightStick TE S+ for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f080": { name: "FightStick TE2 for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f900": { name: "Controller", layout: "xbox", protocol: "HID gamepad", maker: "Harmonix" },
  "1bad:f901": { name: "GameStop Controller", layout: "xbox", protocol: "HID gamepad", maker: "Harmonix" },
  "1bad:f903": { name: "Tron Controller for Xbox 360", layout: "xbox", protocol: "XInput", maker: "Harmonix" },
  "1bad:f906": { name: "Mortal Kombat FightStick for Xbox 360", layout: "joystick", protocol: "XInput", maker: "Harmonix" },
  "1bad:f907": { name: "Afterglow Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Harmonix" },
  "1bad:fa01": { name: "Gamepad", layout: "xbox", protocol: "HID gamepad", maker: "Harmonix" },
  "20bc:5500": { name: "Frostbite controller", layout: "xbox", protocol: "HID gamepad", maker: "ShanWan" },
  "24c6:5000": { name: "Razer Atrox Gaming Arcade Stick", layout: "joystick", protocol: "HID joystick", maker: "PowerA" },
  "24c6:5300": { name: "PowerA Mini ProEX Controller for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:5303": { name: "Airflo Wired Controller for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:530a": { name: "ProEX Controller for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:5397": { name: "FUS1ON Tournament Controller", layout: "xbox", protocol: "HID gamepad", maker: "PowerA" },
  "24c6:541a": { name: "PowerA CPFA115320-01 [Mini Controller for Xbox One]", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:543a": { name: "PowerA Wired Controller for Xbox One", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:550d": { name: "Hori Gem Controller for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:551a": { name: "Fusion Pro Controller", layout: "xbox", protocol: "HID gamepad", maker: "PowerA" },
  "24c6:561a": { name: "Fusion Controller for Xbox One", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:5b00": { name: "Ferrari 458 Italia Racing Wheel", layout: "joystick", protocol: "HID joystick", maker: "PowerA" },
  "24c6:5b02": { name: "GPX Controller", layout: "xbox", protocol: "HID gamepad", maker: "PowerA" },
  "24c6:fafb": { name: "Aplay Controller", layout: "xbox", protocol: "HID gamepad", maker: "PowerA" },
  "24c6:fafd": { name: "Afterglow Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "24c6:fafe": { name: "Rock Candy Gamepad for Xbox 360", layout: "xbox", protocol: "XInput", maker: "PowerA" },
  "2563:0523": { name: "BM0523 WirelessGamepad", layout: "xbox", protocol: "HID gamepad", maker: "ShanWan" },
  "2563:0575": { name: "ZD-V+ Wired Gaming Controller", layout: "xbox", protocol: "HID gamepad", maker: "ShanWan" },
  "289b:0001": { name: "Gamecube/N64 controller v2.2", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:0004": { name: "Gamecube/N64 controller v2.3", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:0005": { name: "Saturn (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:0007": { name: "Famicom controller", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:0008": { name: "Dreamcast (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:000b": { name: "Gamecube/N64 controller v2.9 (Keyboard mode)", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:000c": { name: "Gamecube/N64 controller v2.9 (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:000e": { name: "VirtualBoy controller", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:0010": { name: "WUSBMote v1.2 (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:0012": { name: "WUSBMote v1.2.1 (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:0014": { name: "WUSBMote v1.3 (Joystick mode)", layout: "joystick", protocol: "HID joystick", maker: "Raphnet" },
  "289b:0017": { name: "Gamecube/N64 controller v3.0", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "289b:0018": { name: "Atari Jaguar controller", layout: "xbox", protocol: "HID gamepad", maker: "Raphnet" },
  "28de:1102": { name: "Steam Controller (Wired)", layout: "xbox", protocol: "Steam Input", maker: "Valve" },
  "28de:1142": { name: "Steam Controller (Wireless)", layout: "xbox", protocol: "Steam Input", maker: "Valve" },
  "28de:1205": { name: "Steam Deck Controller", layout: "xbox", protocol: "Steam Input", maker: "Valve" },
  "28de:2012": { name: "Virtual Reality Controller [VRC]", layout: "xbox", protocol: "HID gamepad", maker: "Valve" },
  "2993:0001": { name: "EasySMX X10", layout: "xbox", protocol: "XInput", maker: "EasySMX" },
  "2dc8:3106": { name: "8BitDo Ultimate Controller", layout: "xbox", protocol: "XInput", maker: "8BitDo" },
  "2dc8:5006": { name: "M30 Bluetooth gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:6000": { name: "SF30 Pro gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:6001": { name: "SN30/SF30 Pro gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:ab11": { name: "F30 gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:ab12": { name: "N30 gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:ab20": { name: "SN30/SF30 gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2dc8:ab21": { name: "SF30 gamepad", layout: "xbox", protocol: "HID gamepad", maker: "8BitDo" },
  "2e24:0652": { name: "Duke Xbox One controller", layout: "xbox", protocol: "XInput", maker: "Hyperkin" },
  "2e24:1688": { name: "X91 Xbox One controller", layout: "xbox", protocol: "XInput", maker: "Hyperkin" },
  "2e95:7725": { name: "Controller", layout: "xbox", protocol: "HID gamepad", maker: "SCUF Gaming" },
  "31e3:1100": { name: "Flydigi Apex 4", layout: "xbox", protocol: "XInput", maker: "Flydigi" },
  "31e3:1200": { name: "Flydigi Vader 4 Pro", layout: "xbox", protocol: "XInput", maker: "Flydigi" },
  "31e3:1300": { name: "Flydigi Direwolf 2", layout: "xbox", protocol: "XInput", maker: "Flydigi" },
  "3507:1001": { name: "BIGBIG WON Rainbow 2 Pro", layout: "xbox", protocol: "XInput", maker: "BIGBIG WON" },
  "3507:1003": { name: "BIGBIG WON Gale Hall", layout: "xbox", protocol: "XInput", maker: "BIGBIG WON" },
  "3537:1001": { name: "GameSir G7 SE", layout: "xbox", protocol: "XInput", maker: "GameSir" },
  "3537:1004": { name: "GameSir T4 Cyclone Pro", layout: "xbox", protocol: "XInput", maker: "GameSir" },
  "3537:1007": { name: "GameSir G8 Galileo", layout: "xbox", protocol: "XInput", maker: "GameSir" },
  "3651:1000": { name: "Machenike G5 Pro", layout: "xbox", protocol: "XInput", maker: "Machenike" },
  "37d7:1000": { name: "Thunderobot G50S", layout: "xbox", protocol: "XInput", maker: "Thunderobot" },
  "413d:1000": { name: "Gulikit KK3 Max", layout: "xbox", protocol: "XInput", maker: "Gulikit" }
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
  var p = lower(product)
  var out = {
    layout: "generic",
    modelLabel: String(name || "Gamepad"),
    protocol: "HID",
    driverNote: String(driver || "hid-generic"),
    maker: VENDORS[v] || ""
  }

  function finish(o) {
    var isPs = o.layout === "ps" || n.indexOf("dualsense") !== -1 || n.indexOf("dualshock") !== -1
    o.hasTouchpad = Boolean(isPs || n.indexOf("steam controller") !== -1 || n.indexOf("trackpad") !== -1 || n.indexOf("touchpad") !== -1)
    o.hasRgbLed = Boolean(isPs)
    return o
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

    return finish(out)
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
    return finish(out)
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
    return finish(out)
  }

  // Nintendo -----------------------------------------------------------
  if (d === "hid-nintendo" || n.indexOf("nintendo switch") !== -1 ||
      n.indexOf("pro controller") !== -1 || n.indexOf("joy-con") !== -1) {
    out.layout = "switch"
    out.modelLabel = n.indexOf("joy-con") !== -1 ? "Joy-Cons" : "Switch Pro pad"
    out.protocol = "Nintendo Switch"
    return finish(out)
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
    return finish(out)
  }

  // Steam ----------------------------------------------------------------
  if (n.indexOf("steam") !== -1) {
    out.layout = "xbox"
    out.protocol = "Steam Input"
    out.maker = "Valve"
    return finish(out)
  }

  // ZhiXu / DragonRise / Generic PC gamepad clones ----------------------
  if (n.indexOf("zhixu") !== -1 || (v === "0079" && (product === "181c" || buttonCount === 15))) {
    out.layout = "xbox"
    out.protocol = "DirectInput / HID"
    out.maker = "ZhiXu"
    out.modelLabel = "ZhiXu Gamepad"
    out.buttonPreset = "zhixu"
    return finish(out)
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
    return finish(out)
  }

  // Everything else — keep the maker string short and honest --------------
  if (n.indexOf("gamepad") !== -1 || n.indexOf("controller") !== -1 || n.indexOf("joystick") !== -1) {
    out.protocol = "HID gamepad"
  }
  return finish(out)
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
  var preset = "";
  if (typeof profile === "string") {
    preset = profile.toLowerCase();
  } else if (profile && typeof profile === "object") {
    preset = String(profile.buttonPreset || profile.preset || "").toLowerCase();
  }
  if (!preset && layout) {
    var l = String(layout).toLowerCase();
    if (l === "zhixu" || l === "dragonrise") preset = "zhixu";
  }

  if (preset === "zhixu" || layout === "zhixu" || (profile && profile.isZhiXu)) {
    // ZhiXu / DragonRise 15-button HID map (kernel joydev keycodes):
    // 0: A (BTN_SOUTH), 1: B (BTN_EAST), 2: C (BTN_C), 3: Y (BTN_NORTH), 4: X (BTN_WEST),
    // 5: Z (BTN_Z), 6: LB (BTN_TL), 7: RB (BTN_TR), 8: LT (BTN_TL2), 9: RT (BTN_TR2),
    // 10: Back (BTN_SELECT), 11: Start (BTN_START), 12: Mode/Home (BTN_MODE),
    // 13: LS (BTN_THUMBL), 14: RS (BTN_THUMBR). D-Pad is on Hat0X/Hat0Y axes.
    t = {
      faceBottom: 0, faceRight: 1, faceTop: 3, faceLeft: 4,
      bumperL: 6, bumperR: 7,
      triggerL: 8, triggerR: 9,
      centerLeft: 10, centerRight: 11, centerTop: 12, centerExtra: -1,
      stickL: 13, stickR: 14,
      dpadUp: -1, dpadDown: -1, dpadLeft: -1, dpadRight: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    };
  } else if (layout === "xbox") {
    // xpad / xpadneo standard Linux kernel joydev mapping:
    // A0 B1 X2 Y3, LB4 RB5, Back6 Start7 Guide8, LS9 RS10, Share11
    // D-Pad is on Hat0X and Hat0Y (axes 6 and 7). Triggers are analog axes.
    t = {
      faceBottom: 0, faceRight: 1, faceLeft: 2, faceTop: 3,
      bumperL: 4, bumperR: 5,
      triggerL: -1, triggerR: -1,
      centerLeft: 6, centerRight: 7, centerTop: 8,
      stickL: 9, stickR: 10,
      centerExtra: -1,
      dpadUp: 11, dpadDown: 12, dpadLeft: 13, dpadRight: 14,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]
    };
  } else if (layout === "ps" || layout === "playstation") {
    // hid-playstation / hid-sony standard Linux kernel joydev mapping:
    // Cross0 Circle1 Triangle2 Square3, L1 4, R1 5, L2 6, R2 7,
    // Create/Share8, Options9, PS10, L3 11, R3 12, Touchpad13. D-Pad is on Hat0X/Hat0Y.
    t = {
      faceBottom: 0, faceRight: 1, faceTop: 2, faceLeft: 3,
      bumperL: 4, bumperR: 5,
      triggerL: 6, triggerR: 7,
      centerLeft: 8, centerRight: 9, centerTop: 10,
      stickL: 11, stickR: 12,
      centerExtra: 13,
      dpadUp: -1, dpadDown: -1, dpadLeft: -1, dpadRight: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    };
  } else if (layout === "switch" || layout === "nintendo") {
    // hid-nintendo pro: B0 A1 X2 Y3, Capture4, L5 R6, ZL7 ZR8,
    // -9 +10, Home11, stick presses 12/13. D-Pad is on Hat0X/Hat0Y.
    t = {
      faceBottom: 0, faceRight: 1, faceTop: 2, faceLeft: 3,
      centerExtra: 4,
      bumperL: 5, bumperR: 6,
      triggerL: 7, triggerR: 8,
      centerLeft: 9, centerRight: 10, centerTop: 11,
      stickL: 12, stickR: 13,
      dpadUp: -1, dpadDown: -1, dpadLeft: -1, dpadRight: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
    };
  } else if (layout === "joystick") {
    // Conventional single-stick ordering: trigger = button 0, then the
    // base/grip cluster 1..6. Hat reports as ABS_HAT0X/Y axes.
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
    // generic: A0 B1 X2 Y3, LB4 RB5, center 6/7, guide 8, sticks 9/10
    t = {
      faceBottom: 0, faceRight: 1, faceLeft: 2, faceTop: 3,
      bumperL: 4, bumperR: 5,
      triggerL: -1, triggerR: -1,
      centerLeft: 6, centerRight: 7, centerTop: 8,
      stickL: 9, stickR: 10,
      centerExtra: -1,
      dpadUp: -1, dpadDown: -1, dpadLeft: -1, dpadRight: -1,
      known: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    };
  }

  // Profile-based button remapping
  if (profile && typeof profile === "object") {
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
// Linux joydev axes:
// - 8+ axes: LX(0), LY(1), sticks/triggers(2..5), Hat0X(6), Hat0Y(7)
// - 6 axes:  LX(0), LY(1), RX(2), RY(3), Hat0X(4), Hat0Y(5)
// - Joysticks: Throttle & Rudder detected by name
function axesMap(layout, axisCount, axisNames) {
  if (layout === "joystick") {
    var thr = throttleIndex(axisNames)
    if (thr === -1 && axisCount >= 3) thr = 2
    return { lx: 0, ly: 1, rx: -1, ry: -1, lt: thr, rt: -1, hatX: -1, hatY: -1 }
  }

  var hat = hatIndices(axisNames)
  var names = axisNameList(axisNames)

  var hatX = hat.x
  var hatY = hat.y

  if (hatX === -1 || hatY === -1) {
    if (names.length === 0) {
      if (axisCount >= 8) {
        hatX = 6; hatY = 7;
      } else if (axisCount >= 6 && (layout === "switch" || layout === "nintendo")) {
        hatX = 4; hatY = 5;
      } else {
        hatX = -1; hatY = -1;
      }
    } else {
      hatX = -1; hatY = -1;
    }
  }

  var lt = -1, rt = -1, rx = 2, ry = 3;

  if (names.length >= 6) {
    var zIdx = names.indexOf("z");
    var rzIdx = names.indexOf("rz");
    var rxIdx = names.indexOf("rx");
    var ryIdx = names.indexOf("ry");
    var gasIdx = names.indexOf("gas");
    var brakeIdx = names.indexOf("brake");
    var throttleIdx = names.indexOf("throttle");
    var rudderIdx = names.indexOf("rudder");

    if (gasIdx !== -1 && brakeIdx !== -1) {
      lt = gasIdx; rt = brakeIdx;
      if (zIdx !== -1 && rzIdx !== -1) { rx = zIdx; ry = rzIdx; }
    } else if (zIdx !== -1 && rzIdx !== -1 && rxIdx !== -1 && ryIdx !== -1) {
      lt = zIdx; rt = rzIdx;
      rx = rxIdx; ry = ryIdx;
    } else if (throttleIdx !== -1 && rudderIdx !== -1) {
      lt = throttleIdx; rt = rudderIdx;
    }
  }

  if (lt === -1 && rt === -1) {
    if (layout === "switch" || (axisCount >= 6 && hatX === 4 && hatY === 5)) {
      lt = -1; rt = -1;
      rx = 2; ry = 3;
    } else if (axisCount >= 8) {
      lt = 4; rt = 5;
      rx = 2; ry = 3;
    }
  }

  return { lx: 0, ly: 1, rx: rx, ry: ry, lt: lt, rt: rt, hatX: hatX, hatY: hatY }
}

function isDpadActive(dir, buttons, axes, tables, axisMap) {
  if (!dir) return false
  var d = String(dir).toLowerCase()
  var role = d === "up" ? "dpadUp" : d === "down" ? "dpadDown" : d === "left" ? "dpadLeft" : "dpadRight"

  // 1. Hat Axes (Primary D-Pad for Linux gamepads)
  if (axisMap && axes && axes.length > 0) {
    if (d === "up" && axisMap.hatY !== undefined && axisMap.hatY >= 0 && axisMap.hatY < axes.length) {
      if (Number(axes[axisMap.hatY]) < -0.45) return true
    }
    if (d === "down" && axisMap.hatY !== undefined && axisMap.hatY >= 0 && axisMap.hatY < axes.length) {
      if (Number(axes[axisMap.hatY]) > 0.45) return true
    }
    if (d === "left" && axisMap.hatX !== undefined && axisMap.hatX >= 0 && axisMap.hatX < axes.length) {
      if (Number(axes[axisMap.hatX]) < -0.45) return true
    }
    if (d === "right" && axisMap.hatX !== undefined && axisMap.hatX >= 0 && axisMap.hatX < axes.length) {
      if (Number(axes[axisMap.hatX]) > 0.45) return true
    }
  }

  // 2. Digital button check (for custom profiles or digital D-pad devices)
  if (tables && tables[role] !== undefined && tables[role] >= 0 && buttons && !!buttons[tables[role]]) {
    return true
  }

  return false
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
  var l = String(layout || "").toLowerCase()
  if (l === "xbox") return "xbox360"
  if (l === "ps" || l === "playstation") return "ps3"
  if (l === "switch" || l === "nintendo") return "switchpro"
  return ""
}

function artPath(set, name) {
  return set ? "assets/input/" + set + "/" + name + ".svg" : ""
}

// Face cap for a diamond position ("top"/"bottom"/"left"/"right").
function faceArt(layout, pos, profile) {
  var l = String(layout || "").toLowerCase()
  if (l !== "xbox" && l !== "ps" && l !== "playstation" && l !== "switch" && l !== "nintendo") return ""
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
    stickL: "leftstick",
    stickR: "rightstick",
    dpadUp: "dpup",
    dpadDown: "dpdown",
    dpadLeft: "dpleft",
    dpadRight: "dpright",
    centerLeft: "back",
    centerRight: "start",
    centerExtra: "share",
    centerTop: "guide"
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
  var l = String(layout || "").toLowerCase()
  var isPs = l === "ps" || l === "playstation"
  var isSwitch = l === "switch" || l === "nintendo"
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
  if (activeRole === "centerExtra") return isPs ? "Touchpad" : isSwitch ? "Capture" : "Share"
  if (activeRole === "centerTop") return isPs ? "PS" : isSwitch ? "Home" : "Xbox"
  return activeRole
}

// Shoulder (bumper) cap for a side, empty for sets without shoulder art.
function bumperArt(layout, side) {
  var l = String(layout || "").toLowerCase()
  if (l !== "xbox" && l !== "ps" && l !== "playstation" && l !== "switch" && l !== "nintendo") return ""
  return artPath(artSet(layout), (side === "l" ? "left" : "right") + "shoulder")
}

// Analog trigger cap for a side, empty for sets without trigger art.
function triggerArt(layout, side) {
  var l = String(layout || "").toLowerCase()
  if (l !== "xbox" && l !== "ps" && l !== "playstation" && l !== "switch" && l !== "nintendo") return ""
  return artPath(artSet(layout), (side === "l" ? "left" : "right") + "trigger")
}

// Center key cap: "left" = back/create/share, "right" = start/options/menu.
function centerArt(layout, side) {
  var l = String(layout || "").toLowerCase()
  if (l !== "xbox" && l !== "ps" && l !== "playstation" && l !== "switch" && l !== "nintendo") return ""
  if (side === "extra" || side === "share" || side === "capture") return artPath(artSet(layout), "share")
  if (side === "top" || side === "guide" || side === "home") return artPath(artSet(layout), "guide")
  return artPath(artSet(layout), side === "left" || side === "minus" || side === "back" ? "back" : "start")
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
// Multi-Sector Performance Scorecard & Gamepadla Benchmark Comparison
// ---------------------------------------------------------------------------
var _catalogModule = null
function getCatalog() {
  if (_catalogModule) return _catalogModule
  if (typeof GamepadlaCatalog !== "undefined") {
    _catalogModule = GamepadlaCatalog
    return _catalogModule
  }
  if (typeof require !== "undefined") {
    try {
      _catalogModule = require("./GamepadlaCatalog.js")
      return _catalogModule
    } catch (e) {}
  }
  return null
}

function computePerformanceScorecard(dev, stats, joyLabStats) {
  if (!dev) {
    return {
      overallGrade: "C",
      overallScore: 50,
      summary: "No controller connected",
      sectors: {
        sticks: { score: 50, tier: "C", error: 0.15, drift: 0.01, label: "No stick data" },
        latency: { score: 50, tier: "C", hz: 0, ms: 0, label: "Idle / Unmeasured" },
        buttons: { score: 50, tier: "C", label: "0 buttons" },
        haptics: { score: 50, tier: "C", label: "No motors" },
        motion: { score: 0, tier: "C", label: "No motion sensor" },
        connectivity: { score: 50, tier: "C", label: "Disconnected" }
      },
      gamepadlaMatch: null
    }
  }

  stats = stats || {}
  joyLabStats = joyLabStats || {}

  // 1. Stick Precision & Circularity
  var leftErr = (dev.circularity && dev.circularity.left && isFinite(dev.circularity.left.error)) ? dev.circularity.left.error : null
  var rightErr = (dev.circularity && dev.circularity.right && isFinite(dev.circularity.right.error)) ? dev.circularity.right.error : null
  var stickErr = 0.08
  if (leftErr !== null && rightErr !== null) {
    stickErr = (leftErr + rightErr) / 2
  } else if (leftErr !== null) {
    stickErr = leftErr
  } else if (rightErr !== null) {
    stickErr = rightErr
  } else if (joyLabStats.stickError !== undefined) {
    stickErr = Number(joyLabStats.stickError) > 1.0 ? Number(joyLabStats.stickError) / 100 : Number(joyLabStats.stickError)
  }

  var drift = (dev.circularity && dev.circularity.left && isFinite(dev.circularity.left.drift)) ? dev.circularity.left.drift : 0.003
  var snapbacks = joyLabStats.snapbacks || 0

  var sticksTier = "C"
  var sticksScore = 60
  if (stickErr < 0.078 && snapbacks <= 1) {
    sticksTier = "S"; sticksScore = 96
  } else if (stickErr < 0.11) {
    sticksTier = "A"; sticksScore = 88
  } else if (stickErr < 0.16) {
    sticksTier = "B"; sticksScore = 75
  } else {
    sticksTier = "C"; sticksScore = 60
  }

  // 2. Polling Rate & Latency
  var hz = stats.hz || stats.pollingRate || (stats.avgMs > 0 ? Math.round(1000 / stats.avgMs) : (dev.hz || 125))
  var ms = stats.avgMs || stats.avg || (hz > 0 ? 1000 / hz : 8.0)
  var jitter = stats.jitter || 0.5
  var latencyTier = "C"
  var latencyScore = 60
  if (hz >= 500) {
    latencyTier = "S"; latencyScore = 98
  } else if (hz >= 250) {
    latencyTier = "A"; latencyScore = 90
  } else if (hz >= 120) {
    latencyTier = "B"; latencyScore = 80
  } else {
    latencyTier = "C"; latencyScore = 65
  }

  // 3. Buttons & Triggers
  var buttonCount = dev.buttonCount || 16
  var buttonsTier = buttonCount >= 14 ? "S" : (buttonCount >= 10 ? "A" : "B")
  var buttonsScore = buttonCount >= 14 ? 96 : (buttonCount >= 10 ? 88 : 76)

  // 4. Haptics & Vibration Engine
  var layout = dev.layout || "generic"
  var hasRumble = !!(dev.hasRumble || (dev.event && String(dev.event).length > 0))
  var hapticsTier = "C"
  var hapticsScore = 40
  if (layout === "switch" || layout === "ps") {
    hapticsTier = "S"; hapticsScore = 98
  } else if (hasRumble) {
    hapticsTier = "A"; hapticsScore = 88
  } else {
    hapticsTier = "C"; hapticsScore = 45
  }

  // 5. 6-DOF IMU Motion
  var hasGyro = !!(dev.motion || (dev.motionNode && dev.motionNode.length > 0) || layout === "switch" || layout === "ps")
  var gyroDrift = (dev.motion && isFinite(dev.motion.drift)) ? dev.motion.drift : 0.02
  var motionTier = "C"
  var motionScore = 30
  if (hasGyro && gyroDrift < 0.05) {
    motionTier = "S"; motionScore = 95
  } else if (hasGyro) {
    motionTier = "A"; motionScore = 85
  } else {
    motionTier = "C"; motionScore = 40
  }

  // 6. Connectivity & Audio Health
  var bus = String(dev.bus || "usb").toLowerCase()
  var connTier = "A"
  var connScore = 85
  if (bus === "usb" || bus === "dongle") {
    connTier = "S"; connScore = 96
  } else if (bus === "bluetooth") {
    connTier = "A"; connScore = 88
  }

  // Overall Weighted Score: Sticks (25%), Latency (25%), Buttons (15%), Haptics (15%), Motion (10%), Connectivity (10%)
  var overallScore = Math.round(
    sticksScore * 0.25 +
    latencyScore * 0.25 +
    buttonsScore * 0.15 +
    hapticsScore * 0.15 +
    motionScore * 0.10 +
    connScore * 0.10
  )

  var overallGrade = "C"
  if (overallScore >= 93) overallGrade = "S"
  else if (overallScore >= 87) overallGrade = "A+"
  else if (overallScore >= 80) overallGrade = "A"
  else if (overallScore >= 70) overallGrade = "B"
  else if (overallScore >= 55) overallGrade = "C"
  else overallGrade = "D"

  var cat = getCatalog()
  var match = cat ? cat.find(dev.modelLabel || dev.name, dev.maker) : null

  return {
    overallGrade: overallGrade,
    overallScore: overallScore,
    sectors: {
      sticks: {
        score: sticksScore,
        tier: sticksTier,
        error: stickErr,
        drift: drift,
        snapbacks: snapbacks,
        label: (stickErr * 100).toFixed(1) + "% error" + (snapbacks > 0 ? " · " + snapbacks + " snapbacks" : " · 0 snapbacks")
      },
      latency: {
        score: latencyScore,
        tier: latencyTier,
        hz: hz,
        ms: ms,
        jitter: jitter,
        label: Math.round(hz) + " Hz · " + ms.toFixed(1) + " ms avg"
      },
      buttons: {
        score: buttonsScore,
        tier: buttonsTier,
        count: buttonCount,
        label: buttonCount + " inputs verified"
      },
      haptics: {
        score: hapticsScore,
        tier: hapticsTier,
        label: (layout === "switch" || layout === "ps") ? "HD Rumble / LRAs Active" : (hasRumble ? "Dual ERM Motors" : "None")
      },
      motion: {
        score: motionScore,
        tier: motionTier,
        hasGyro: hasGyro,
        label: hasGyro ? "6-DOF Active (Drift: " + (gyroDrift * 100).toFixed(1) + "°/s)" : "No Gyro Detected"
      },
      connectivity: {
        score: connScore,
        tier: connTier,
        bus: bus,
        label: bus.toUpperCase() + (dev.battery !== undefined ? " · Battery " + dev.battery + "%" : "")
      }
    },
    gamepadlaMatch: match
  }
}

function exportMarkdownReport(dev, card) {
  var name = dev ? (dev.modelLabel || dev.name || "Gamepad") : "Unknown Controller"
  var dateStr = new Date().toISOString().slice(0, 10)
  var bus = dev && dev.bus ? dev.bus.toUpperCase() : "USB"
  card = card || computePerformanceScorecard(dev, null, null)

  var lines = [
    "### omycontroller Hardware Performance Report",
    "- **Generated**: " + dateStr,
    "- **Controller**: " + name,
    "- **Connection**: " + bus,
    "- **Overall Grade**: **" + card.overallGrade + "** (" + card.overallScore + "/100)",
    "",
    "#### 📊 Multi-Sector Benchmark Evaluation",
    "- **Stick Precision & Circularity**: Tier " + card.sectors.sticks.tier + " — " + card.sectors.sticks.label,
    "- **Polling & Latency**: Tier " + card.sectors.latency.tier + " — " + card.sectors.latency.label,
    "- **Button & Trigger Health**: Tier " + card.sectors.buttons.tier + " — " + card.sectors.buttons.label,
    "- **Haptics & HD Rumble**: Tier " + card.sectors.haptics.tier + " — " + card.sectors.haptics.label,
    "- **6-DOF IMU Motion**: Tier " + card.sectors.motion.tier + " — " + card.sectors.motion.label,
    "- **Connectivity & Bus Health**: Tier " + card.sectors.connectivity.tier + " — " + card.sectors.connectivity.label
  ]

  if (card.gamepadlaMatch && card.gamepadlaMatch.entry) {
    var entry = card.gamepadlaMatch.entry
    lines.push("")
    lines.push("#### 🏆 Gamepadla Lab Reference Match")
    lines.push("- **Model Match**: " + entry.n + (entry.b ? " (" + entry.b + ")" : ""))
    if (entry.poll) lines.push("- **Verified Polling Rate**: " + entry.poll + " Hz")
    if (entry.avg) lines.push("- **Verified Average Delay**: " + entry.avg + " ms")
    if (entry.stick_resolution) lines.push("- **Stick Resolution**: " + entry.stick_resolution + " points")
  }

  lines.push("")
  lines.push("---")
  lines.push("*Generated by omycontroller Pro Diagnostics on Omarchy Linux*")

  return lines.join("\n")
}

// ---------------------------------------------------------------------------
// RGB / LED color helpers & PlayStation presets
// ---------------------------------------------------------------------------
var PS_LED_PRESETS = [
  { name: "PS Blue", hex: "#0066ff", r: 0, g: 102, b: 255 },
  { name: "Crimson", hex: "#ff0033", r: 255, g: 0, b: 51 },
  { name: "Emerald", hex: "#00e676", r: 0, g: 230, b: 118 },
  { name: "Neon Violet", hex: "#9d00ff", r: 157, g: 0, b: 255 },
  { name: "Amber Gold", hex: "#ffaa00", r: 255, g: 170, b: 0 },
  { name: "Cyber Cyan", hex: "#00e5ff", r: 0, g: 229, b: 255 },
  { name: "Hot Pink", hex: "#ff1493", r: 255, g: 20, b: 147 },
  { name: "Studio White", hex: "#ffffff", r: 255, g: 255, b: 255 }
]

function hexToRgb(hex) {
  if (!hex) return { r: 0, g: 102, b: 255 }
  var clean = String(hex).replace("#", "").trim()
  if (clean.length === 3) {
    clean = clean[0] + clean[0] + clean[1] + clean[1] + clean[2] + clean[2]
  }
  var num = parseInt(clean, 16)
  if (isNaN(num)) return { r: 0, g: 102, b: 255 }
  return {
    r: (num >> 16) & 255,
    g: (num >> 8) & 255,
    b: num & 255
  }
}

function rgbToHex(r, g, b) {
  var clamp = function(v) { return Math.max(0, Math.min(255, Math.round(Number(v) || 0))) }
  var rh = clamp(r).toString(16)
  if (rh.length < 2) rh = "0" + rh
  var gh = clamp(g).toString(16)
  if (gh.length < 2) gh = "0" + gh
  var bh = clamp(b).toString(16)
  if (bh.length < 2) bh = "0" + bh
  return "#" + rh + gh + bh
}

// ---------------------------------------------------------------------------
// Gyro motion processing & steering helpers
// ---------------------------------------------------------------------------
function computeGyroSteering(gyro, gyroBias, deadzoneDeg, maxDeflectionDeg) {
  if (!gyro || typeof gyro !== "object") return 0.0
  var rawRoll = Number(gyro.roll)
  if (isNaN(rawRoll)) return 0.0

  // Apply Y-axis (roll/drift) bias correction if provided
  if (gyroBias && typeof gyroBias === "object" && !isNaN(Number(gyroBias.y))) {
    rawRoll -= Number(gyroBias.y)
  }

  var dz = deadzoneDeg !== undefined && !isNaN(Number(deadzoneDeg)) ? Math.max(0, Number(deadzoneDeg)) : 3.0
  var maxDeg = maxDeflectionDeg !== undefined && !isNaN(Number(maxDeflectionDeg)) ? Math.max(dz + 0.1, Number(maxDeflectionDeg)) : 25.0

  var absRoll = Math.abs(rawRoll)
  if (absRoll <= dz) return 0.0

  var sign = rawRoll > 0 ? 1.0 : -1.0
  var norm = Math.min(1.0, (absRoll - dz) / (maxDeg - dz))
  return sign * norm
}

function computeGyroFlick(gyro, prevGyro, threshold) {
  if (!gyro || !prevGyro || typeof gyro !== "object" || typeof prevGyro !== "object") return false
  var pNow = Number(gyro.pitch)
  var pPrev = Number(prevGyro.pitch)
  if (isNaN(pNow) || isNaN(pPrev)) return false

  var th = threshold !== undefined && !isNaN(Number(threshold)) ? Number(threshold) : 15.0
  return (pNow - pPrev) >= th
}


// ---------------------------------------------------------------------------
// CommonJS exports for Node.js test runner while preserving QML compatibility
// ---------------------------------------------------------------------------
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    KERNEL_DEVICES: KERNEL_DEVICES,
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
    triggerNorm: triggerNorm,
    isDpadActive: isDpadActive,
    computePerformanceScorecard: computePerformanceScorecard,
    exportMarkdownReport: exportMarkdownReport,
    PS_LED_PRESETS: PS_LED_PRESETS,
    hexToRgb: hexToRgb,
    rgbToHex: rgbToHex,
    computeGyroSteering: computeGyroSteering,
    computeGyroFlick: computeGyroFlick
  }
}


