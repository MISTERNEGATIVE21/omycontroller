const test = require('node:test');
const assert = require('node:assert/strict');
const Model = require('../GamepadModel.js');
const Catalog = require('../GamepadlaCatalog.js');

test('Classification - Xbox Series, DualSense, Switch Pro, and others', (t) => {
  // Xbox Series
  const xboxSeries = Model.classify('Xbox Series X Controller', 'xpadneo', '045e', '0b12', 6, 16);
  assert.strictEqual(xboxSeries.layout, 'xbox');
  assert.strictEqual(xboxSeries.modelLabel, 'Xbox Series pad');
  assert.strictEqual(xboxSeries.protocol, 'XInput');
  assert.strictEqual(xboxSeries.maker, 'Microsoft');

  // DualSense
  const dualSense = Model.classify('Wireless Controller', 'hid-playstation', '054c', '0ce6', 6, 16);
  assert.strictEqual(dualSense.layout, 'ps');
  assert.strictEqual(dualSense.modelLabel, 'DualSense');
  assert.strictEqual(dualSense.protocol, 'DualSense');
  assert.strictEqual(dualSense.maker, 'Sony');

  // DualSense Edge
  const dualSenseEdge = Model.classify('DualSense Edge Wireless Controller', 'hid-playstation', '054c', '0df2', 6, 16);
  assert.strictEqual(dualSenseEdge.layout, 'ps');
  assert.strictEqual(dualSenseEdge.modelLabel, 'DualSense Edge');
  assert.strictEqual(dualSenseEdge.protocol, 'DualSense');

  // Switch Pro
  const switchPro = Model.classify('Nintendo Switch Pro Controller', 'hid-nintendo', '057e', '2009', 6, 16);
  assert.strictEqual(switchPro.layout, 'switch');
  assert.strictEqual(switchPro.modelLabel, 'Switch Pro pad');
  assert.strictEqual(switchPro.protocol, 'Nintendo Switch');
  assert.strictEqual(switchPro.maker, 'Nintendo');

  // Flight / Arcade Stick
  const stick = Model.classify('T.Flight Hotas X', 'usbhid', '044f', 'b108', 4, 8);
  assert.strictEqual(stick.layout, 'joystick');
  assert.strictEqual(stick.protocol, 'HID joystick');

  // 8BitDo
  const bitdo = Model.classify('8BitDo Ultimate Controller', 'hid-generic', '2dc8', '3106', 6, 16);
  assert.strictEqual(bitdo.maker, '8BitDo');
});

test('Circularity Metrics - magnitude, center drift, and circularity error', (t) => {
  assert.strictEqual(typeof Model.circularityMetrics, 'function', 'circularityMetrics must be a function');

  // Dead center
  const center = Model.circularityMetrics(0, 0, []);
  assert.strictEqual(center.r, 0);
  assert.strictEqual(center.centerDrift, 0);
  assert.strictEqual(center.circularityError, 0);

  // Slight resting drift (e.g. x=0.03, y=0.04 -> r = 0.05 -> 5% drift)
  const drift = Model.circularityMetrics(0.03, 0.04, []);
  assert.ok(Math.abs(drift.r - 0.05) < 1e-6);
  assert.ok(Math.abs(drift.centerDrift - 5.0) < 0.1);

  // Perfect circle points (r = 1.0)
  const circlePoints = [
    { x: 1, y: 0 },
    { x: 0, y: 1 },
    { x: -1, y: 0 },
    { x: 0, y: -1 },
    { x: Math.SQRT1_2, y: Math.SQRT1_2 },
    { x: -Math.SQRT1_2, y: Math.SQRT1_2 }
  ];
  let metrics = null;
  let history = [];
  for (const pt of circlePoints) {
    metrics = Model.circularityMetrics(pt.x, pt.y, history);
    history = metrics.history;
  }
  assert.ok(metrics !== null);
  assert.strictEqual(metrics.circularityError, 0);

  // Distorted / overshooting circle (e.g. square gate reaching corners at r ~ 1.25)
  const distortedPoints = [
    { x: 1.25, y: 0 },
    { x: 0, y: 1.25 },
    { x: -1.25, y: 0 },
    { x: 0, y: -1.25 }
  ];
  let distMetrics = null;
  let distHistory = [];
  for (const pt of distortedPoints) {
    distMetrics = Model.circularityMetrics(pt.x, pt.y, distHistory);
    distHistory = distMetrics.history;
  }
  // 1.25 has a 25% deviation from 1.0
  assert.ok(distMetrics.circularityError >= 24 && distMetrics.circularityError <= 26, `Expected ~25% circularity error, got ${distMetrics.circularityError}%`);
});

test('Deadzone Response Curves - linear, dynamic, smooth, and aggressive', (t) => {
  assert.strictEqual(typeof Model.applyCurve, 'function', 'applyCurve must be a function');

  const dz = 0.10;
  const outer = 0.90;

  // Inside inner deadzone -> 0
  assert.strictEqual(Model.applyCurve(0.05, 'linear', dz, outer), 0);
  assert.strictEqual(Model.applyCurve(-0.08, 'linear', dz, outer), 0);
  assert.strictEqual(Model.applyCurve(0.00, 'dynamic', dz, outer), 0);
  assert.strictEqual(Model.applyCurve(0.09, 'smooth', dz, outer), 0);

  // Beyond outer deadzone -> clamped to 1.0 (or -1.0)
  assert.strictEqual(Model.applyCurve(0.95, 'linear', dz, outer), 1.0);
  assert.strictEqual(Model.applyCurve(1.00, 'dynamic', dz, outer), 1.0);
  assert.strictEqual(Model.applyCurve(-0.99, 'smooth', dz, outer), -1.0);

  // Midpoint: (0.50 - 0.10) / (0.90 - 0.10) = 0.40 / 0.80 = 0.50 normalized
  const linMid = Model.applyCurve(0.50, 'linear', dz, outer);
  assert.ok(Math.abs(linMid - 0.50) < 1e-4, `Linear midpoint expected 0.5, got ${linMid}`);

  // Dynamic curve has precision center (slope < 1 at low input, so f(0.5) < 0.5)
  const dynMid = Model.applyCurve(0.50, 'dynamic', dz, outer);
  assert.ok(dynMid > 0 && dynMid < 0.50, `Dynamic midpoint expected < 0.5, got ${dynMid}`);
  assert.strictEqual(Model.applyCurve(0.90, 'dynamic', dz, outer), 1.0);

  // Smooth sinusoidal S-curve: f(0.5) should be 0.5 by symmetry
  const smoothMid = Model.applyCurve(0.50, 'smooth', dz, outer);
  assert.ok(Math.abs(smoothMid - 0.50) < 1e-4, `Smooth midpoint expected 0.5, got ${smoothMid}`);

  // Quarter-point: smooth curve S-shape has f(0.25) < 0.25 (slower start)
  const linQuarter = Model.applyCurve(0.30, 'linear', dz, outer); // u = 0.20/0.80 = 0.25
  const smoothQuarter = Model.applyCurve(0.30, 'smooth', dz, outer);
  assert.ok(smoothQuarter < linQuarter, `Smooth at quarter expected < linear, got ${smoothQuarter} vs ${linQuarter}`);

  // Aggressive curve: fast ramp near center, f(0.25) > 0.25
  const aggQuarter = Model.applyCurve(0.30, 'aggressive', dz, outer);
  assert.ok(aggQuarter > linQuarter, `Aggressive at quarter expected > linear, got ${aggQuarter} vs ${linQuarter}`);

  // Negative values preserve sign
  const negLinear = Model.applyCurve(-0.50, 'linear', dz, outer);
  assert.strictEqual(negLinear, -linMid);

  // Vector object {x, y} support
  const vecResult = Model.applyCurve({ x: 0.50, y: 0 }, 'linear', dz, outer);
  assert.ok(Math.abs(vecResult.x - 0.50) < 1e-4);
  assert.strictEqual(vecResult.y, 0);
});

test('Connection Iconography - asset paths matching hardware/bus/phys', (t) => {
  assert.strictEqual(typeof Model.connectionIcon, 'function', 'connectionIcon must be a function');

  // Bluetooth
  assert.strictEqual(Model.connectionIcon('0005', ''), 'assets/icon_bt.svg');
  assert.strictEqual(Model.connectionIcon('Bluetooth', ''), 'assets/icon_bt.svg');
  assert.strictEqual(Model.connectionIcon('0003', 'e4:17:d8:12:34:56'), 'assets/icon_bt.svg');

  // USB Dongle / Wireless adapter
  assert.strictEqual(Model.connectionIcon('0003', 'usb-0000:00:14.0-1/input0 Wireless Adapter'), 'assets/icon_dongle.svg');
  assert.strictEqual(Model.connectionIcon('USB Dongle', ''), 'assets/icon_dongle.svg');
  assert.strictEqual(Model.connectionIcon('0003', 'Xbox Wireless Receiver'), 'assets/icon_dongle.svg');

  // Wired USB cable
  assert.strictEqual(Model.connectionIcon('0003', 'usb-0000:00:14.0-1/input0'), 'assets/icon_cable.svg');
  assert.strictEqual(Model.connectionIcon('Wired USB', ''), 'assets/icon_cable.svg');
  assert.strictEqual(Model.connectionIcon(null, null), 'assets/icon_cable.svg');
});

test('Latency Metrics & Polling Rate - calculations and formatting', (t) => {
  assert.strictEqual(typeof Model.latencyMetrics, 'function', 'latencyMetrics must be a function');
  assert.strictEqual(typeof Model.formatHz, 'function', 'formatHz must be a function');

  // Empty / null intervals
  const empty = Model.latencyMetrics([]);
  assert.strictEqual(empty.hz, 0);
  assert.strictEqual(empty.avg, 0);
  assert.strictEqual(empty.jitter, 0);

  // Steady 250 Hz (4 ms intervals)
  const steady250 = Model.latencyMetrics([4, 4, 4, 4, 4]);
  assert.strictEqual(steady250.avg, 4);
  assert.strictEqual(steady250.min, 4);
  assert.strictEqual(steady250.max, 4);
  assert.strictEqual(steady250.jitter, 0);
  assert.strictEqual(steady250.hz, 250);

  // Steady 1000 Hz (1 ms intervals)
  const steady1000 = Model.latencyMetrics([1, 1, 1, 1]);
  assert.strictEqual(steady1000.avg, 1);
  assert.strictEqual(steady1000.hz, 1000);

  // Jitter calculation
  const jittery = Model.latencyMetrics([2, 4, 6]);
  assert.strictEqual(jittery.avg, 4);
  assert.strictEqual(jittery.min, 2);
  assert.strictEqual(jittery.max, 6);
  // variance = ((2-4)^2 + (4-4)^2 + (6-4)^2)/3 = (4 + 0 + 4)/3 = 8/3 ~ 2.6667; stddev = sqrt(8/3) ~ 1.633
  assert.ok(Math.abs(jittery.jitter - Math.sqrt(8 / 3)) < 1e-4);

  // formatHz helper
  assert.strictEqual(Model.formatHz(4), '250 Hz');
  assert.strictEqual(Model.formatHz(2), '500 Hz');
  assert.strictEqual(Model.formatHz(1), '1000 Hz');
  assert.strictEqual(Model.formatHz(0), '0 Hz');
});

test('Compatibility - existing exports and helper functions preserved', (t) => {
  assert.strictEqual(typeof Model.connection, 'function');
  assert.strictEqual(typeof Model.connectionShort, 'function');
  assert.strictEqual(typeof Model.batteryBucket, 'function');
  assert.strictEqual(typeof Model.batteryLabel, 'function');
  assert.strictEqual(typeof Model.latencyLabel, 'function');
  assert.strictEqual(typeof Model.profileKey, 'function');
  assert.strictEqual(typeof Model.normalizeProfile, 'function');
  assert.strictEqual(typeof Model.applyStickDeadzone, 'function');
  assert.strictEqual(typeof Model.buttonTables, 'function');
  assert.strictEqual(typeof Model.axesMap, 'function');
  assert.strictEqual(typeof Model.shapeLabel, 'function');
  assert.strictEqual(typeof Model.triggerNorm, 'function');

  // Verify behavior of existing helpers
  assert.strictEqual(Model.connection('0005', '', ''), 'Bluetooth');
  assert.strictEqual(Model.connectionShort('Bluetooth'), 'BT');
  assert.strictEqual(Model.batteryBucket(15, 20), 'low');
  assert.strictEqual(Model.batteryBucket(30, 20), 'warn');
  assert.strictEqual(Model.batteryBucket(80, 20), 'ok');
  assert.strictEqual(Model.batteryLabel(85, false), '85%');
  assert.strictEqual(Model.batteryLabel(85, true), '85% ⚡');
  assert.strictEqual(Model.profileKey('045e', '0b12', 'Xbox Pad'), '045e:0b12:Xbox_Pad');
});

test('Edge cases and boundary handling across all modules', (t) => {
  // DualShock 4 detection
  const ds4 = Model.classify('Wireless Controller', 'hid-playstation', '054c', '05c4', 6, 16);
  assert.strictEqual(ds4.modelLabel, 'DualShock 4');
  assert.strictEqual(ds4.layout, 'ps');

  // Joy-Cons detection
  const joycons = Model.classify('Joy-Con (L/R)', 'hid-nintendo', '057e', '2008', 4, 10);
  assert.strictEqual(joycons.modelLabel, 'Joy-Cons');
  assert.strictEqual(joycons.layout, 'switch');

  // circularityMetrics rolling window trimming at 500
  let hist = [];
  for (let i = 0; i < 550; i++) {
    const res = Model.circularityMetrics(1, 0, hist);
    hist = res.history;
  }
  assert.strictEqual(hist.length, 500, 'History should cap at 500 points');

  // circularityMetrics with null/undefined
  const nullCirc = Model.circularityMetrics(undefined, null, null);
  assert.strictEqual(nullCirc.r, 0);
  assert.strictEqual(nullCirc.circularityError, 0);

  // applyCurve with outer <= inner deadzone fallback
  const curveFallback = Model.applyCurve(0.5, 'linear', 0.8, 0.5);
  assert.strictEqual(typeof curveFallback, 'number');

  // latencyMetrics with non-positive or invalid numbers
  const dirtyLatency = Model.latencyMetrics([-5, 0, 'invalid', NaN, 4, 4]);
  assert.strictEqual(dirtyLatency.avg, 4);
  assert.strictEqual(dirtyLatency.hz, 250);

  // formatHz invalid inputs
  assert.strictEqual(Model.formatHz(-10), '0 Hz');
  assert.strictEqual(Model.formatHz('invalid'), '0 Hz');
  assert.strictEqual(Model.formatHz(NaN), '0 Hz');
});

test('ControllerImage button art resolution paths', (t) => {
  // Art set per layout
  assert.strictEqual(Model.artSet('xbox'), 'xbox360');
  assert.strictEqual(Model.artSet('ps'), 'ps3');
  assert.strictEqual(Model.artSet('switch'), 'switchpro');
  assert.strictEqual(Model.artSet('generic'), '');
  assert.strictEqual(Model.artSet('joystick'), '');

  // Face caps: SDL3 positional naming n/s/w/e (relative, resolvable via Qt.resolvedUrl)
  assert.strictEqual(Model.faceArt('xbox', 'top'), 'assets/input/xbox360/n.svg');
  assert.strictEqual(Model.faceArt('xbox', 'bottom'), 'assets/input/xbox360/s.svg');
  assert.strictEqual(Model.faceArt('xbox', 'left'), 'assets/input/xbox360/w.svg');
  assert.strictEqual(Model.faceArt('xbox', 'right'), 'assets/input/xbox360/e.svg');
  assert.strictEqual(Model.faceArt('ps', 'top'), 'assets/input/ps3/n.svg');

  // Bumpers / triggers / center keys only exist for sets with that art
  assert.strictEqual(Model.bumperArt('xbox', 'l'), 'assets/input/xbox360/leftshoulder.svg');
  assert.strictEqual(Model.bumperArt('ps', 'r'), 'assets/input/ps3/rightshoulder.svg');
  assert.strictEqual(Model.triggerArt('xbox', 'r'), 'assets/input/xbox360/righttrigger.svg');
  assert.strictEqual(Model.centerArt('xbox', 'left'), 'assets/input/xbox360/back.svg');
  assert.strictEqual(Model.centerArt('xbox', 'right'), 'assets/input/xbox360/start.svg');
  assert.strictEqual(Model.centerArt('xbox', 'extra'), 'assets/input/xbox360/share.svg');
  assert.strictEqual(Model.centerArt('xbox', 'guide'), 'assets/input/xbox360/guide.svg');
  assert.strictEqual(Model.centerArt('ps', 'left'), 'assets/input/ps3/back.svg');

  // Switch resolves to switchpro SVG art set
  assert.strictEqual(Model.faceArt('switch', 'top'), 'assets/input/switchpro/n.svg');
  assert.strictEqual(Model.bumperArt('switch', 'l'), 'assets/input/switchpro/leftshoulder.svg');
  assert.strictEqual(Model.triggerArt('switch', 'r'), 'assets/input/switchpro/righttrigger.svg');
  assert.strictEqual(Model.centerArt('switch', 'guide'), 'assets/input/switchpro/guide.svg');
  assert.strictEqual(Model.centerArt('switch', 'extra'), 'assets/input/switchpro/share.svg');

  // Generic/joystick fall back to vector text labels
  assert.strictEqual(Model.faceArt('generic', 'top'), '');
  assert.strictEqual(Model.bumperArt('generic', 'l'), '');
  assert.strictEqual(Model.centerArt('generic', 'right'), '');
  assert.strictEqual(Model.triggerArt('generic', 'l'), '');
});

test('Gamepadla catalog matching, photo paths, and benchmark summaries', (t) => {
  assert.ok(Array.isArray(Catalog.CATALOG));
  assert.ok(Catalog.CATALOG.length >= 200, 'catalog should hold the scraped controllers');

  // Known pads resolve against the scraped database
  const dualSense = Catalog.find('DualSense', 'Sony');
  assert.ok(dualSense, 'DualSense should match');
  assert.match(dualSense.entry.n, /DualSense/i);
  assert.strictEqual(dualSense.entry.b, 'Sony');

  const xbox = Catalog.find('Xbox Series pad', 'Microsoft');
  assert.ok(xbox, 'Xbox Series should match');
  assert.match(xbox.entry.n, /Xbox/i);

  const switchPro = Catalog.find('Switch Pro pad', 'Nintendo');
  assert.ok(switchPro, 'Switch Pro should match');
  assert.match(switchPro.entry.n, /Switch/i);

  const bitdo = Catalog.find('8BitDo Ultimate 3E For Xbox', '8BitDo');
  assert.ok(bitdo, '8BitDo Ultimate should match');
  assert.strictEqual(bitdo.entry.b, '8BitDo');

  // Unrelated pads fall through to generic
  assert.strictEqual(Catalog.find('Generic USB pad', ''), null);
  assert.strictEqual(Catalog.find('', ''), null);

  // Photo path maps into the gamepadla assets dir
  const img = Catalog.imagePath(dualSense.entry);
  assert.match(img, /^assets\/gamepadla_data\/gamepadla_data\/images\/.+\.webp$/);

  // Benchmark helpers produce non-empty summaries for matched entries
  assert.ok(Catalog.benchmarkLabel(dualSense.entry).length > 0);
  const best = Catalog.bestLatency(dualSense.entry);
  assert.ok(best === null || (best.mode && best.ms > 0));

  // Every catalog entry has a name and (usually) an image
  for (const e of Catalog.CATALOG) {
    assert.ok(e.n, 'entry must have a name');
    assert.match(e.img, /\.webp$/, 'entry should point at a webp image');
  }
});

test('Button remapping via profile presets and custom buttonMap', (t) => {
  const std = Model.buttonTables('xbox');
  assert.strictEqual(std.faceBottom, 0); // A
  assert.strictEqual(std.faceRight, 1);  // B
  assert.strictEqual(std.faceLeft, 2);   // X
  assert.strictEqual(std.faceTop, 3);    // Y

  // Nintendo layout swap (A <-> B, X <-> Y)
  const swapped = Model.buttonTables('xbox', { remapPreset: 'nintendo_swap' });
  assert.strictEqual(swapped.faceBottom, 1); // B is at bottom position
  assert.strictEqual(swapped.faceRight, 0);  // A is at right position
  assert.strictEqual(swapped.faceLeft, 3);   // Y is at left position
  assert.strictEqual(swapped.faceTop, 2);    // X is at top position

  // Custom buttonMap override
  const custom = Model.buttonTables('xbox', { buttonMap: { bumperL: 10, bumperR: 11 } });
  assert.strictEqual(custom.bumperL, 10);
  assert.strictEqual(custom.bumperR, 11);
  assert.strictEqual(custom.faceBottom, 0);
});

test('Dynamic SVG buttonArt and faceArt with button remapping', (t) => {
  // Standard Xbox face art
  assert.strictEqual(Model.faceArt('xbox', 'bottom'), 'assets/input/xbox360/s.svg');
  assert.strictEqual(Model.faceArt('xbox', 'right'), 'assets/input/xbox360/e.svg');
  assert.strictEqual(Model.faceArt('xbox', 'left'), 'assets/input/xbox360/w.svg');
  assert.strictEqual(Model.faceArt('xbox', 'top'), 'assets/input/xbox360/n.svg');

  // Remapped with nintendo_swap: bottom becomes B (e.svg), right becomes A (s.svg)
  const nProfile = { remapPreset: 'nintendo_swap' };
  assert.strictEqual(Model.faceArt('xbox', 'bottom', nProfile), 'assets/input/xbox360/e.svg');
  assert.strictEqual(Model.faceArt('xbox', 'right', nProfile), 'assets/input/xbox360/s.svg');
  assert.strictEqual(Model.faceArt('xbox', 'left', nProfile), 'assets/input/xbox360/n.svg');
  assert.strictEqual(Model.faceArt('xbox', 'top', nProfile), 'assets/input/xbox360/w.svg');

  // Generic buttonArt resolver
  assert.strictEqual(Model.buttonArt('xbox', 'faceBottom'), 'assets/input/xbox360/s.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'bumperL'), 'assets/input/xbox360/leftshoulder.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'triggerR'), 'assets/input/xbox360/righttrigger.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'stickL'), 'assets/input/xbox360/leftstick.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'stickR'), 'assets/input/xbox360/rightstick.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'centerExtra'), 'assets/input/xbox360/share.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'centerTop'), 'assets/input/xbox360/guide.svg');
  assert.strictEqual(Model.buttonArt('xbox', 'faceBottom', nProfile), 'assets/input/xbox360/e.svg');

  // buttonLabel resolver
  assert.strictEqual(Model.buttonLabel('xbox', 'faceBottom'), 'A');
  assert.strictEqual(Model.buttonLabel('xbox', 'faceBottom', nProfile), 'B');
  assert.strictEqual(Model.buttonLabel('xbox', 'centerExtra'), 'Share');
  assert.strictEqual(Model.buttonLabel('xbox', 'centerTop'), 'Xbox');
  assert.strictEqual(Model.buttonLabel('ps', 'faceBottom'), '×');
  assert.strictEqual(Model.buttonLabel('ps', 'faceBottom', nProfile), '○');
});

test('ZhiXu Gamepad Classification and Button Mapping', (t) => {
  // Classification
  const zx = Model.classify('ZhiXu Gamepad', 'hid-generic', '0079', '181c', 8, 15);
  assert.strictEqual(zx.layout, 'xbox');
  assert.strictEqual(zx.maker, 'ZhiXu');
  assert.strictEqual(zx.modelLabel, 'ZhiXu Gamepad');
  assert.strictEqual(zx.buttonPreset, 'zhixu');

  // Axes map with hat coordinates
  const axes = Model.axesMap('xbox', 8, ['X', 'Y', 'Z', 'Rz', 'Gas', 'Brake', 'Hat0X', 'Hat0Y']);
  assert.strictEqual(axes.lx, 0);
  assert.strictEqual(axes.ly, 1);
  assert.strictEqual(axes.rx, 2);
  assert.strictEqual(axes.ry, 3);
  assert.strictEqual(axes.lt, 4);
  assert.strictEqual(axes.rt, 5);
  assert.strictEqual(axes.hatX, 6);
  assert.strictEqual(axes.hatY, 7);

  // Button table for zhixu
  const zxTable = Model.buttonTables('xbox', { buttonPreset: 'zhixu' });
  assert.strictEqual(zxTable.faceBottom, 0); // A (BTN_SOUTH)
  assert.strictEqual(zxTable.faceRight, 1);  // B (BTN_EAST)
  assert.strictEqual(zxTable.faceTop, 3);    // Y (BTN_NORTH)
  assert.strictEqual(zxTable.faceLeft, 4);   // X (BTN_WEST)
  assert.strictEqual(zxTable.bumperL, 6);    // LB
  assert.strictEqual(zxTable.bumperR, 7);    // RB
  assert.strictEqual(zxTable.triggerL, 8);   // LT button
  assert.strictEqual(zxTable.triggerR, 9);   // RT button
  assert.strictEqual(zxTable.centerLeft, 10); // Back/View
  assert.strictEqual(zxTable.centerRight, 11); // Start/Menu
  assert.strictEqual(zxTable.centerTop, 12);  // Mode/Guide
  assert.strictEqual(zxTable.stickL, 13);    // LS
  assert.strictEqual(zxTable.stickR, 14);    // RS
});

test('Kernel Device Database & Multi-Vendor Classification', (t) => {
  // Vendor coverage
  assert.ok(typeof Model.VENDORS === 'object');
  assert.ok(Object.keys(Model.VENDORS).length >= 75, `Expected >= 75 vendors, got ${Object.keys(Model.VENDORS).length}`);

  // Device catalog coverage
  assert.ok(typeof Model.KERNEL_DEVICES === 'object');
  assert.ok(Object.keys(Model.KERNEL_DEVICES).length >= 350, `Expected >= 350 kernel devices, got ${Object.keys(Model.KERNEL_DEVICES).length}`);

  // Logitech F310 DirectInput
  const f310 = Model.classify('Logitech Gamepad F310', 'hid-generic', '046d', 'c21d', 6, 12);
  assert.strictEqual(f310.maker, 'Logitech');
  assert.strictEqual(f310.modelLabel, 'Logitech Gamepad F310');
  assert.strictEqual(f310.protocol, 'DirectInput');

  // Logitech G29 Racing Wheel
  const g29 = Model.classify('Logitech G29 Driving Force Racing Wheel', 'hid-generic', '046d', 'c29b', 4, 16);
  assert.strictEqual(g29.layout, 'joystick');
  assert.strictEqual(g29.maker, 'Logitech');
  assert.strictEqual(g29.protocol, 'HID wheel');

  // Valve Steam Deck Controller
  const steamDeck = Model.classify('Steam Deck Controller', 'hid-generic', '28de', '1205', 6, 16);
  assert.strictEqual(steamDeck.maker, 'Valve');
  assert.strictEqual(steamDeck.modelLabel, 'Steam Deck Controller');
  assert.strictEqual(steamDeck.protocol, 'Steam Input');

  // Flydigi Apex 4
  const apex4 = Model.classify('Flydigi Apex 4', 'xpadneo', '31e3', '1100', 6, 16);
  assert.strictEqual(apex4.maker, 'Flydigi');
  assert.strictEqual(apex4.modelLabel, 'Flydigi Apex 4');
  assert.strictEqual(apex4.layout, 'xbox');

  // GameSir G7 SE
  const g7se = Model.classify('GameSir G7 SE', 'xpad', '3537', '1001', 6, 16);
  assert.strictEqual(g7se.maker, 'GameSir');
  assert.strictEqual(g7se.modelLabel, 'GameSir G7 SE');
  assert.strictEqual(g7se.protocol, 'XInput');

  // BIGBIG WON Rainbow 2 Pro
  const bbw = Model.classify('BIGBIG WON Rainbow 2 Pro', 'xpad', '3507', '1001', 6, 16);
  assert.strictEqual(bbw.maker, 'BIGBIG WON');
  assert.strictEqual(bbw.modelLabel, 'BIGBIG WON Rainbow 2 Pro');

  // Sony DualSense Edge
  const edge = Model.classify('Wireless Controller', 'hid-playstation', '054c', '0df2', 6, 16);
  assert.strictEqual(edge.maker, 'Sony');
  assert.strictEqual(edge.modelLabel, 'DualSense Edge');
  assert.strictEqual(edge.layout, 'ps');
  assert.strictEqual(edge.protocol, 'DualSense');

  // Nintendo Joy-Con
  const joyconL = Model.classify('Joy-Con (L)', 'hid-nintendo', '057e', '2006', 4, 8);
  assert.strictEqual(joyconL.maker, 'Nintendo');
  assert.strictEqual(joyconL.modelLabel, 'Joy-Cons');
  assert.strictEqual(joyconL.layout, 'switch');
});

test('Nintendo Switch Pro Controller button tables and axes map', (t) => {
  const swTable = Model.buttonTables('switch');
  // hid-nintendo evdev keycodes:
  // BTN_SOUTH (304) = B (0)
  // BTN_EAST (305) = A (1)
  // BTN_NORTH (307) = X (2)
  // BTN_WEST (308) = Y (3)
  // BTN_Z (309) = Capture (4)
  // BTN_TL (310) = L (5)
  // BTN_TR (311) = R (6)
  // BTN_TL2 (312) = ZL (7)
  // BTN_TR2 (313) = ZR (8)
  // BTN_SELECT (314) = Minus (9)
  // BTN_START (315) = Plus (10)
  // BTN_MODE (316) = Home (11)
  // BTN_THUMBL (317) = StickL (12)
  // BTN_THUMBR (318) = StickR (13)
  assert.strictEqual(swTable.faceBottom, 0); // B
  assert.strictEqual(swTable.faceRight, 1);  // A
  assert.strictEqual(swTable.faceTop, 2);    // X
  assert.strictEqual(swTable.faceLeft, 3);   // Y
  assert.strictEqual(swTable.centerExtra, 4); // Capture
  assert.strictEqual(swTable.bumperL, 5);    // L
  assert.strictEqual(swTable.bumperR, 6);    // R
  assert.strictEqual(swTable.triggerL, 7);   // ZL
  assert.strictEqual(swTable.triggerR, 8);   // ZR
  assert.strictEqual(swTable.centerLeft, 9); // Minus (-)
  assert.strictEqual(swTable.centerRight, 10); // Plus (+)
  assert.strictEqual(swTable.centerTop, 11);  // Home
  assert.strictEqual(swTable.stickL, 12);    // Left stick click
  assert.strictEqual(swTable.stickR, 13);    // Right stick click

  // Switch axes map with Hat0X/Hat0Y
  const swAxes = Model.axesMap('switch', 6);
  assert.strictEqual(swAxes.lx, 0);
  assert.strictEqual(swAxes.ly, 1);
  assert.strictEqual(swAxes.rx, 2);
  assert.strictEqual(swAxes.ry, 3);
  assert.strictEqual(swAxes.hatX, 4);
  assert.strictEqual(swAxes.hatY, 5);
});

test('isDpadActive - unified D-pad detection across buttons and hat axes', (t) => {
  assert.strictEqual(typeof Model.isDpadActive, 'function', 'isDpadActive must be exported');

  // 1. Digital button active via custom remap or digital D-pad
  const digitalTables = { dpadUp: 0, dpadDown: 1, dpadLeft: 2, dpadRight: 3 };
  const buttonsUp = { 0: true };
  assert.strictEqual(Model.isDpadActive('up', buttonsUp, [], digitalTables, null), true);
  assert.strictEqual(Model.isDpadActive('down', buttonsUp, [], digitalTables, null), false);
  assert.strictEqual(Model.isDpadActive('left', buttonsUp, [], digitalTables, null), false);
  assert.strictEqual(Model.isDpadActive('right', buttonsUp, [], digitalTables, null), false);

  // 2. Hat axes on Switch (hatX: 4, hatY: 5)
  const swTables = Model.buttonTables('switch');
  const swAxisMap = Model.axesMap('switch', 6);

  // Hat centered (0, 0)
  assert.strictEqual(Model.isDpadActive('up', {}, [0, 0, 0, 0, 0, 0], swTables, swAxisMap), false);
  assert.strictEqual(Model.isDpadActive('down', {}, [0, 0, 0, 0, 0, 0], swTables, swAxisMap), false);
  assert.strictEqual(Model.isDpadActive('left', {}, [0, 0, 0, 0, 0, 0], swTables, swAxisMap), false);
  assert.strictEqual(Model.isDpadActive('right', {}, [0, 0, 0, 0, 0, 0], swTables, swAxisMap), false);

  // Hat Up: hatY (index 5) = -1.0
  const axesUp = [0, 0, 0, 0, 0, -1.0];
  assert.strictEqual(Model.isDpadActive('up', {}, axesUp, swTables, swAxisMap), true);
  assert.strictEqual(Model.isDpadActive('down', {}, axesUp, swTables, swAxisMap), false);

  // Hat Down: hatY (index 5) = +1.0
  const axesDown = [0, 0, 0, 0, 0, 1.0];
  assert.strictEqual(Model.isDpadActive('down', {}, axesDown, swTables, swAxisMap), true);
  assert.strictEqual(Model.isDpadActive('up', {}, axesDown, swTables, swAxisMap), false);

  // Hat Left: hatX (index 4) = -1.0
  const axesLeft = [0, 0, 0, 0, -1.0, 0];
  assert.strictEqual(Model.isDpadActive('left', {}, axesLeft, swTables, swAxisMap), true);
  assert.strictEqual(Model.isDpadActive('right', {}, axesLeft, swTables, swAxisMap), false);

  // Hat Right: hatX (index 4) = +1.0
  const axesRight = [0, 0, 0, 0, 1.0, 0];
  assert.strictEqual(Model.isDpadActive('right', {}, axesRight, swTables, swAxisMap), true);
  assert.strictEqual(Model.isDpadActive('left', {}, axesRight, swTables, swAxisMap), false);

  // 3. Null / edge cases
  assert.strictEqual(Model.isDpadActive(null, null, null, null, null), false);
  assert.strictEqual(Model.isDpadActive('up', null, null, null, null), false);
});

test('Performance Scorecard - 6 sectors, grading, and Gamepadla comparison', (t) => {
  const dev = {
    id: 'js0',
    name: 'Nintendo Co., Ltd. Pro Controller',
    modelLabel: 'Nintendo Switch Pro Controller',
    maker: 'Nintendo',
    layout: 'switch',
    hasRumble: true,
    event: 'event30',
    bus: 'usb',
    circularity: {
      left: { error: 0.072, drift: 0.003 },
      right: { error: 0.075, drift: 0.004 }
    },
    motion: { gyroHz: 200, drift: 0.015 }
  };
  const stats = { hz: 125, avgMs: 8.0, jitter: 0.5 };
  const joyLabStats = { stickError: 7.2, snapbacks: 0, jumps: 12, coins: 5 };

  const card = Model.computePerformanceScorecard(dev, stats, joyLabStats);
  assert.ok(card, 'scorecard must be produced');
  assert.ok(card.overallGrade === 'S' || card.overallGrade === 'A+' || card.overallGrade === 'A', 'overall grade should be high tier');
  assert.ok(card.overallScore >= 85, 'overall score must be at least 85');
  assert.strictEqual(card.sectors.sticks.tier, 'S');
  assert.ok(card.sectors.sticks.score >= 90);
  assert.ok(card.sectors.latency.score > 0);
  assert.strictEqual(card.sectors.haptics.tier, 'S');
  assert.strictEqual(card.sectors.motion.tier, 'S');
  assert.ok(card.gamepadlaMatch, 'should find Gamepadla catalog match');

  // Edge case: null or empty device
  const emptyCard = Model.computePerformanceScorecard(null, null, null);
  assert.ok(emptyCard);
  assert.strictEqual(emptyCard.overallGrade, 'C');
});

test('Markdown Diagnostic Report Export', (t) => {
  const dev = {
    id: 'js0',
    name: 'Nintendo Co., Ltd. Pro Controller',
    modelLabel: 'Nintendo Switch Pro Controller',
    maker: 'Nintendo',
    layout: 'switch',
    hasRumble: true,
    event: 'event30',
    bus: 'usb',
    circularity: {
      left: { error: 0.072, drift: 0.003 },
      right: { error: 0.075, drift: 0.004 }
    }
  };
  const card = Model.computePerformanceScorecard(dev, { hz: 125, avgMs: 8.0 }, { stickError: 7.2, snapbacks: 0 });
  const md = Model.exportMarkdownReport(dev, card);
  assert.match(md, /### omycontroller Hardware Performance Report/);
  assert.match(md, /Nintendo Switch Pro Controller/);
  assert.match(md, /Overall Grade/);
  assert.match(md, /Stick Precision/);
  assert.match(md, /Polling & Latency/);
});




