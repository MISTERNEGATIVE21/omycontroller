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
  assert.strictEqual(Model.centerArt('ps', 'left'), 'assets/input/ps3/back.svg');

  // Switch/generic fall back to vector text labels
  assert.strictEqual(Model.faceArt('switch', 'top'), '');
  assert.strictEqual(Model.bumperArt('switch', 'l'), '');
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
  assert.strictEqual(Model.buttonArt('xbox', 'faceBottom', nProfile), 'assets/input/xbox360/e.svg');

  // buttonLabel resolver
  assert.strictEqual(Model.buttonLabel('xbox', 'faceBottom'), 'A');
  assert.strictEqual(Model.buttonLabel('xbox', 'faceBottom', nProfile), 'B');
  assert.strictEqual(Model.buttonLabel('ps', 'faceBottom'), '×');
  assert.strictEqual(Model.buttonLabel('ps', 'faceBottom', nProfile), '○');
});


