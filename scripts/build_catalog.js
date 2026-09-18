// omycontroller — scripts/build_catalog.js
//
// Builds GamepadlaCatalog.js from the scraped gamepadla.com catalog.
// The generated module is the single source the panel/service query for a
// matched controller entry (art, benchmark grades, pricing, latency data).
//
// Usage:
//   node scripts/build_catalog.js
//
// Reads:  assets/gamepadla_data/gamepadla_data/controllers.json
// Writes: GamepadlaCatalog.js              (data + pure matching helpers)

const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const SRC = path.join(ROOT, "assets/gamepadla_data/gamepadla_data/controllers.json");
const OUT = path.join(ROOT, "GamepadlaCatalog.js");
const IMG_DIR = path.join(ROOT, "assets/gamepadla_data/gamepadla_data/images");

function prune(entries) {
  const out = [];
  for (const e of entries) {
    if (!e || !e.name) continue;
    if (!e.image_downloaded && e.image_filename) continue;
    if (e.image_filename && !fs.existsSync(path.join(IMG_DIR, e.image_filename))) continue;
    const rec = {
      n: String(e.name).slice(0, 64),
      img: e.image_filename || ""
    };
    if (e.brand) rec.b = String(e.brand).slice(0, 40);
    if (Array.isArray(e.tags) && e.tags.length) rec.tags = e.tags;
    if (e.button_latency && typeof e.button_latency === "object") rec.bt = e.button_latency;
    if (e.stick_latency && typeof e.stick_latency === "object") rec.st = e.stick_latency;
    if (e.latscore_wired) rec.ws = e.latscore_wired;
    if (e.latscore_wireless) rec.wl = e.latscore_wireless;
    if (Number.isFinite(Number(e.min_latency_ms))) rec.min = Number(e.min_latency_ms);
    if (Number.isFinite(Number(e.avg_latency_ms))) rec.avg = Number(e.avg_latency_ms);
    if (Number.isFinite(Number(e.max_latency_ms))) rec.max = Number(e.max_latency_ms);
    if (Number.isFinite(Number(e.jitter_ms))) rec.jit = Number(e.jitter_ms);
    if (Number.isFinite(Number(e.polling_rate_hz))) rec.poll = Number(e.polling_rate_hz);
    if (e.price) rec.pr = String(e.price).slice(0, 24);
    if (Array.isArray(e.compatible_platforms) && e.compatible_platforms.length) rec.plats = e.compatible_platforms;
    if (Array.isArray(e.interfaces) && e.interfaces.length) rec.ifc = e.interfaces;
    out.push(rec);
  }
  return out;
}

function helpers() {
  return `// ===========================================================================
// Matching + presentation helpers (pure, side-effect free)
// ===========================================================================

// Lowercase, ASCII-safe, whitespace-collapsed string for token matching.
function normLower(s) {
  return String(s || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .replace(/^ +| +$/g, "");
}

// Split a normalized string into a de-duplicated token array.
function tokenize(s) {
  const seen = new Set();
  return String(s || "")
    .split(" ")
    .filter((t) => t.length > 0 && !seen.has(t) && seen.add(t) !== false);
}

// Best catalog entry for a controller "name/brand" descriptor (usually the
// classified modelLabel + maker). Token-overlap scored with a minimum
// threshold so unrelated pads fall through to null (generic fallback).
function find(name, brand, minScore) {
  const thresh = minScore === undefined || minScore === null ? 0.55 : Number(minScore);
  const target = tokenize(normLower((name || "") + " " + (brand || "")));
  if (target.length === 0) return null;

  let best = null;
  for (let i = 0; i < CATALOG.length; i++) {
    const e = CATALOG[i];
    const et = tokenize(normLower(e.n + " " + (e.b || "")));
    if (et.length === 0) continue;

    let hits = 0;
    for (let j = 0; j < target.length; j++) {
      if (et.indexOf(target[j]) !== -1) hits++;
    }
    let score = hits / et.length + hits / target.length; // 0..2 dice-ish
    score /= 2;

    // Exact brand agreement is a strong signal.
    if (brand && normLower(e.b) === normLower(brand)) score += 0.2;
    // Single-token targets: substring containment rescues short descriptors.
    if (target.length === 1) {
      const tn = normLower(name);
      if (normLower(e.n).indexOf(tn) !== -1 || tn.indexOf(normLower(e.n)) !== -1) score = Math.max(score, 0.95);
    }
    if (score > 1) score = 1;

    if (score >= thresh && (!best || score > best.score)) {
      best = { index: i, entry: e, score };
    }
  }
  return best;
}

// Relative path to the controller's gamepadla photo asset.
function imagePath(entry) {
  if (!entry || !entry.img) return "";
  return "assets/gamepadla_data/gamepadla_data/images/" + entry.img;
}

// Human benchmark summary: latency grades + best avg + jitter.
function benchmarkLabel(entry) {
  if (!entry) return "";
  const bits = [];
  if (entry.ws || entry.wl) bits.push((entry.ws || "–") + " wire / " + (entry.wl || "–") + " wireless");
  if (Number.isFinite(entry.avg)) bits.push("≤" + entry.avg.toFixed(2) + " ms avg");
  if (Number.isFinite(entry.jit)) bits.push("±" + entry.jit.toFixed(2) + " ms jitter");
  if (Number.isFinite(entry.poll)) bits.push(entry.poll + " Hz poll");
  return bits.join(" · ") || "—";
}

// Best observed connection latency (cable/dongle/bluetooth) across both
// button and stick figures, e.g. { mode: "Cable", ms: 2.44 }.
function bestLatency(entry) {
  if (!entry) return null;
  const modes = [{ k: "cable", m: "Cable" }, { k: "dongle", m: "Dongle" }, { k: "bluetooth", m: "Bluetooth" }];
  let best = null;
  for (const src of [entry.bt, entry.st]) {
    if (!src || typeof src !== "object") continue;
    for (const mod of modes) {
      const v = Number(src[mod.k]);
      if (Number.isFinite(v) && (!best || v < best.ms)) best = { mode: mod.m, ms: v };
    }
  }
  return best;
}

`;
}

const raw = JSON.parse(fs.readFileSync(SRC, "utf8"));
const cat = prune(Array.isArray(raw) ? raw : []);
let body = `// omycontroller — GamepadlaCatalog.js
//
// GENERATED by scripts/build_catalog.js — do not edit by hand.
// Compact catalog of 256 gamepadla.com-contributed gamepads (names, brands,
// art image files, latency grades, benchmark figures, platforms, prices).
// Both a QML import target and a CommonJS module (QML skips the exports).

var CATALOG = ${JSON.stringify(cat)};\n\n`;
body += helpers();
body += `if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    CATALOG: CATALOG,
    find: find,
    imagePath: imagePath,
    benchmarkLabel: benchmarkLabel,
    bestLatency: bestLatency,
    normLower: normLower,
    tokenize: tokenize
  };
}\n`;

fs.writeFileSync(OUT, body);
console.log("Wrote " + OUT);
console.log("Entries: " + cat.length + " (source " + raw.length + ")");
console.log("Size: " + (fs.statSync(OUT).size / 1024).toFixed(1) + " KB");