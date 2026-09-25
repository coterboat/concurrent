#!/usr/bin/env node
// CONCURRENT map geography generator. No dependencies.
//
//   node tools/mapgen/mapgen.mjs knife7 known24 world30
//
// Reads maps/<id>.json (the rules graph) and tools/mapgen/<id>.geo.json (seed
// points + shape knobs). Writes:
//   maps/art/<id>_data.png   RGBA data texture the map shader reads
//       R = territory index (nearest territory, also under the sea)
//       G = signed coast distance, 128 = coastline, >128 land, <128 sea (3 units / px)
//       B = distance to nearest territory border, 8 units / px
//       A = distance to nearest region border, 8 units / px
//   maps/art/<id>_art.json   label/token anchors, sea lanes, size
//   maps/art/<id>_preview.png  quick look for humans
//
// Geography never contradicts the rules graph: two territories that are not
// adjacent never share a land border (a channel is carved between them), and
// adjacent pairs that do not touch become dashed sea lanes.
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

// ---------- rng + noise ----------
function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function makeNoise(seed) {
  const rnd = mulberry32(seed);
  const perm = new Uint8Array(512);
  const p = Array.from({ length: 256 }, (_, i) => i);
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [p[i], p[j]] = [p[j], p[i]];
  }
  for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
  const grad = (h, x, y) => {
    switch (h & 7) {
      case 0: return x + y; case 1: return -x + y; case 2: return x - y; case 3: return -x - y;
      case 4: return x; case 5: return -x; case 6: return y; default: return -y;
    }
  };
  const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);
  function noise(x, y) {
    const X = Math.floor(x) & 255, Y = Math.floor(y) & 255;
    x -= Math.floor(x); y -= Math.floor(y);
    const u = fade(x), v = fade(y);
    const a = perm[X] + Y, b = perm[X + 1] + Y;
    const l1 = grad(perm[a], x, y) + u * (grad(perm[b], x - 1, y) - grad(perm[a], x, y));
    const l2 = grad(perm[a + 1], x, y - 1) + u * (grad(perm[b + 1], x - 1, y - 1) - grad(perm[a + 1], x, y - 1));
    return l1 + v * (l2 - l1);
  }
  return function fbm(x, y, oct = 4) {
    let s = 0, amp = 0.5, f = 1;
    for (let i = 0; i < oct; i++) { s += amp * noise(x * f, y * f); f *= 2; amp *= 0.5; }
    return s;
  };
}

// ---------- png ----------
const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 255] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type, "ascii"), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function writePng(file, w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    rgba.copy ? rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4)
      : raw.set(rgba.subarray(y * w * 4, (y + 1) * w * 4), y * (w * 4 + 1) + 1);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  const png = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]);
  fs.writeFileSync(file, png);
}

// ---------- distance transform (Felzenszwalb) ----------
function edt1d(f, n, d, v, z) {
  let k = 0; v[0] = 0; z[0] = -Infinity; z[1] = Infinity;
  for (let q = 1; q < n; q++) {
    let s;
    while (true) {
      s = ((f[q] + q * q) - (f[v[k]] + v[k] * v[k])) / (2 * q - 2 * v[k]);
      if (s <= z[k]) { k--; if (k < 0) { k = 0; break; } } else break;
    }
    k++; v[k] = q; z[k] = s; z[k + 1] = Infinity;
  }
  k = 0;
  for (let q = 0; q < n; q++) {
    while (z[k + 1] < q) k++;
    d[q] = (q - v[k]) * (q - v[k]) + f[v[k]];
  }
}
// seeds: Uint8Array mask (1 = distance 0). Returns Float32Array of euclidean distances.
function edt(seeds, w, h) {
  const INF = 1e20;
  const g = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) g[i] = seeds[i] ? 0 : INF;
  const n = Math.max(w, h);
  const f = new Float64Array(n), d = new Float64Array(n), v = new Int32Array(n), z = new Float64Array(n + 1);
  for (let x = 0; x < w; x++) {
    for (let y = 0; y < h; y++) f[y] = g[y * w + x];
    edt1d(f, h, d, v, z);
    for (let y = 0; y < h; y++) g[y * w + x] = d[y];
  }
  const out = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) f[x] = g[y * w + x];
    edt1d(f, w, d, v, z);
    for (let x = 0; x < w; x++) out[y * w + x] = Math.sqrt(d[x]);
  }
  return out;
}

// ---------- generator ----------
function generate(id) {
  const map = JSON.parse(fs.readFileSync(path.join(ROOT, "maps", id + ".json"), "utf8"));
  const geo = JSON.parse(fs.readFileSync(path.join(ROOT, "tools", "mapgen", id + ".geo.json"), "utf8"));
  const W = geo.width, H = geo.height;
  const ids = Object.keys(map.territories).sort();
  const index = Object.fromEntries(ids.map((t, i) => [t, i]));
  const T = ids.length;
  const derive = geo.adjacency === "derive";
  const adj = Array.from({ length: T }, () => new Uint8Array(T));
  if (!derive) {
    for (const t of ids) for (const n of map.territories[t].adjacent) {
      adj[index[t]][index[n]] = 1; adj[index[n]][index[t]] = 1;
    }
  } else {
    for (let i = 0; i < T; i++) for (let j = 0; j < T; j++) adj[i][j] = 1;
    const cut = (a, b) => { adj[index[a]][index[b]] = 0; adj[index[b]][index[a]] = 0; };
    for (const [a, b] of geo.separate || []) cut(a, b);
    // separateRegions: [[regionA, regionB, [[allowedA, allowedB], ...]], ...]
    const inRegion = (r) => ids.filter((t) => map.territories[t].region === r);
    for (const [ra, rb, allow = []] of geo.separateRegions || []) {
      const ok = new Set(allow.map(([a, b]) => (a < b ? a + "|" + b : b + "|" + a)));
      for (const a of inRegion(ra)) for (const b of inRegion(rb)) {
        if (!ok.has(a < b ? a + "|" + b : b + "|" + a)) cut(a, b);
      }
    }
    // islands: never share a land border with anything
    for (const t of geo.islands || []) for (const o of ids) if (o !== t) cut(t, o);
  }
  const fbm = makeNoise(geo.seed || 7);
  const warpAmp = geo.warp?.amp ?? 40, warpScale = geo.warp?.scale ?? 0.004;
  const coastAmp = geo.coast?.amp ?? 0.35, coastScale = geo.coast?.scale ?? 0.006;
  const gap = geo.gap ?? 9;
  const defR = geo.radius ?? 200;
  const pts = [], rad = new Float32Array(T), wt = new Float32Array(T);
  for (const t of ids) {
    const g = geo.territories[t];
    if (!g) throw new Error(`${id}: geo missing territory ${t}`);
    const arr = Array.isArray(g) ? g : g.pts;
    const i = index[t];
    pts[i] = Array.isArray(arr[0]) ? arr : [arr];
    rad[i] = (Array.isArray(g) ? null : g.r) ?? defR;
    wt[i] = (Array.isArray(g) ? null : g.w) ?? 1;
  }

  const owner = new Int16Array(W * H).fill(-1); // -1 sea
  const nearest = new Uint8Array(W * H);
  const dist = new Float64Array(T);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const qx = x + warpAmp * fbm(x * warpScale, y * warpScale, 4);
      const qy = y + warpAmp * fbm(x * warpScale + 91.7, y * warpScale + 33.1, 4);
      let b1 = 1e9, t1 = 0, raw1 = 0;
      for (let i = 0; i < T; i++) {
        let best = 1e9;
        for (const p of pts[i]) {
          const dx = qx - p[0], dy = qy - p[1];
          const d = dx * dx + dy * dy;
          if (d < best) best = d;
        }
        const raw = Math.sqrt(best);
        const d = raw / wt[i];
        dist[i] = d;
        if (d < b1) { b1 = d; t1 = i; raw1 = raw; }
      }
      const k = y * W + x;
      nearest[k] = t1;
      const r = rad[t1] * (1 + coastAmp * fbm(x * coastScale + 17.3, y * coastScale - 5.1, 5) * 2);
      if (raw1 > r) continue;
      let carve = false;
      for (let i = 0; i < T; i++) {
        if (i !== t1 && !adj[t1][i] && (dist[i] - b1) * Math.min(wt[t1], wt[i]) < gap) { carve = true; break; }
      }
      if (carve) continue;
      owner[k] = t1;
    }
  }

  // keep only each territory's largest component
  const comp = new Int32Array(W * H).fill(-1);
  const stack = new Int32Array(W * H);
  const best = new Map();
  let cid = 0;
  const sizes = [];
  const compOwner = [];
  for (let k = 0; k < W * H; k++) {
    if (owner[k] < 0 || comp[k] >= 0) continue;
    const o = owner[k];
    let sp = 0, size = 0;
    stack[sp++] = k; comp[k] = cid;
    while (sp) {
      const c = stack[--sp]; size++;
      const cx = c % W, cy = (c - cx) / W;
      if (cx > 0 && comp[c - 1] < 0 && owner[c - 1] === o) { comp[c - 1] = cid; stack[sp++] = c - 1; }
      if (cx < W - 1 && comp[c + 1] < 0 && owner[c + 1] === o) { comp[c + 1] = cid; stack[sp++] = c + 1; }
      if (cy > 0 && comp[c - W] < 0 && owner[c - W] === o) { comp[c - W] = cid; stack[sp++] = c - W; }
      if (cy < H - 1 && comp[c + W] < 0 && owner[c + W] === o) { comp[c + W] = cid; stack[sp++] = c + W; }
    }
    sizes.push(size); compOwner.push(o);
    if (!best.has(o) || sizes[best.get(o)] < size) best.set(o, cid);
    cid++;
  }
  for (let k = 0; k < W * H; k++) if (owner[k] >= 0 && best.get(owner[k]) !== comp[k]) owner[k] = -1;
  for (let i = 0; i < T; i++) if (!best.has(i)) throw new Error(`${id}: ${ids[i]} has no land`);

  // fill small enclosed lakes that touch exactly one territory
  const seen = new Uint8Array(W * H);
  const minLake = geo.minLake ?? 1500;
  for (let k = 0; k < W * H; k++) {
    if (owner[k] >= 0 || seen[k]) continue;
    let sp = 0; const cells = []; let edge = false; const touch = new Set();
    stack[sp++] = k; seen[k] = 1;
    while (sp) {
      const c = stack[--sp]; cells.push(c);
      const cx = c % W, cy = (c - cx) / W;
      if (cx === 0 || cy === 0 || cx === W - 1 || cy === H - 1) edge = true;
      for (const n of [cx > 0 ? c - 1 : -1, cx < W - 1 ? c + 1 : -1, cy > 0 ? c - W : -1, cy < H - 1 ? c + W : -1]) {
        if (n < 0) continue;
        if (owner[n] >= 0) { touch.add(owner[n]); continue; }
        if (!seen[n]) { seen[n] = 1; stack[sp++] = n; }
      }
    }
    if (!edge && cells.length < minLake && touch.size === 1) {
      const o = [...touch][0];
      for (const c of cells) owner[c] = o;
    }
  }

  // derived adjacency
  const touching = Array.from({ length: T }, () => new Set());
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const k = y * W + x, o = owner[k];
    if (o < 0) continue;
    if (x < W - 1 && owner[k + 1] >= 0 && owner[k + 1] !== o) { touching[o].add(owner[k + 1]); touching[owner[k + 1]].add(o); }
    if (y < H - 1 && owner[k + W] >= 0 && owner[k + W] !== o) { touching[o].add(owner[k + W]); touching[owner[k + W]].add(o); }
  }
  const problems = [];
  const landPairs = [];
  for (let i = 0; i < T; i++) for (const j of touching[i]) if (i < j) landPairs.push([ids[i], ids[j]]);
  let lanes = [];
  if (!derive) {
    for (const [a, b] of landPairs) if (!adj[index[a]][index[b]]) problems.push(`land border ${a}-${b} is not in the graph`);
    for (const t of ids) for (const n of map.territories[t].adjacent) {
      if (t < n && !touching[index[t]].has(index[n])) lanes.push([t, n]);
    }
  } else {
    lanes = (geo.lanes || []).map(([a, b]) => (a < b ? [a, b] : [b, a]));
    for (const [a, b] of lanes) if (touching[index[a]].has(index[b])) problems.push(`lane ${a}-${b} also touches by land`);
  }

  // distances
  const land = new Uint8Array(W * H), sea = new Uint8Array(W * H), border = new Uint8Array(W * H), rborder = new Uint8Array(W * H);
  const regionOf = ids.map((t) => map.territories[t].region || "");
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const k = y * W + x, o = owner[k];
    if (o < 0) { sea[k] = 1; continue; }
    land[k] = 1;
    for (const n of [x > 0 ? k - 1 : -1, x < W - 1 ? k + 1 : -1, y > 0 ? k - W : -1, y < H - 1 ? k + W : -1]) {
      if (n < 0 || owner[n] < 0 || owner[n] === o) continue;
      border[k] = 1;
      if (regionOf[owner[n]] !== regionOf[o]) rborder[k] = 1;
    }
  }
  const dSea = edt(sea, W, H);   // for land pixels: distance to sea
  const dLand = edt(land, W, H); // for sea pixels: distance to land
  const dBorder = edt(border, W, H);
  const dRegion = edt(rborder, W, H);

  const data = Buffer.alloc(W * H * 4);
  const clamp = (v) => (v < 0 ? 0 : v > 255 ? 255 : Math.round(v));
  for (let k = 0; k < W * H; k++) {
    const o = owner[k];
    const s = o >= 0 ? dSea[k] - 0.5 : -(dLand[k] - 0.5);
    data[k * 4] = o >= 0 ? o : nearest[k];
    data[k * 4 + 1] = clamp(128 + s * 3);
    data[k * 4 + 2] = o >= 0 ? clamp((dBorder[k] + 0.5) * 8) : 255;
    data[k * 4 + 3] = o >= 0 ? clamp((dRegion[k] + 0.5) * 8) : 255;
  }

  // anchors: pole of inaccessibility per territory
  const inside = new Float32Array(W * H);
  {
    const notMine = new Uint8Array(W * H);
    // distance to anything that is not the same territory (border or sea)
    for (let k = 0; k < W * H; k++) notMine[k] = owner[k] < 0 || border[k] ? 1 : 0;
    const d = edt(notMine, W, H);
    for (let k = 0; k < W * H; k++) inside[k] = d[k];
  }
  const anchors = {};
  const area = new Int32Array(T);
  const bbox = Array.from({ length: T }, () => [W, H, 0, 0]);
  const cx = new Float64Array(T), cy = new Float64Array(T);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const o = owner[y * W + x];
    if (o < 0) continue;
    area[o]++; cx[o] += x; cy[o] += y;
    const b = bbox[o];
    if (x < b[0]) b[0] = x; if (y < b[1]) b[1] = y; if (x > b[2]) b[2] = x; if (y > b[3]) b[3] = y;
  }
  for (let i = 0; i < T; i++) {
    const mx = cx[i] / area[i], my = cy[i] / area[i];
    // prefer deep points near the centroid so tokens sit where the eye expects
    let bestK = -1, bestScore = -1e9;
    for (let y = 0; y < H; y += 2) for (let x = 0; x < W; x += 2) {
      const k = y * W + x;
      if (owner[k] !== i) continue;
      const depth = Math.min(inside[k], 60);
      const score = depth * 2 - Math.hypot(x - mx, y - my) * 0.15;
      if (score > bestScore) { bestScore = score; bestK = k; }
    }
    const px = bestK % W, py = (bestK - px) / W;
    anchors[ids[i]] = { x: px, y: py, depth: +inside[bestK].toFixed(1), area: area[i], bbox: bbox[i] };
  }

  // sea lane endpoints: nearest coast pixels between the two territories
  const coastPts = Array.from({ length: T }, () => []);
  for (let y = 0; y < H; y += 2) for (let x = 0; x < W; x += 2) {
    const k = y * W + x, o = owner[k];
    if (o >= 0 && dSea[k] <= 2.5) coastPts[o].push([x, y]);
  }
  const laneGeo = lanes.map(([a, b]) => {
    let bd = 1e18, pa = null, pb = null;
    for (const p of coastPts[index[a]]) for (const q of coastPts[index[b]]) {
      const d = (p[0] - q[0]) ** 2 + (p[1] - q[1]) ** 2;
      if (d < bd) { bd = d; pa = p; pb = q; }
    }
    if (!pa) { pa = [anchors[a].x, anchors[a].y]; pb = [anchors[b].x, anchors[b].y]; }
    // lanes should cross water, not other land
    let crosses = "";
    const steps = Math.ceil(Math.sqrt(bd)) || 1;
    for (let s = 1; s < steps; s++) {
      const x = Math.round(pa[0] + (pb[0] - pa[0]) * s / steps), y = Math.round(pa[1] + (pb[1] - pa[1]) * s / steps);
      const o = owner[y * W + x];
      if (o >= 0 && o !== index[a] && o !== index[b]) { crosses = ids[o]; break; }
    }
    if (crosses) problems.push(`lane ${a}-${b} crosses ${crosses}`);
    return { a, b, ax: pa[0], ay: pa[1], bx: pb[0], by: pb[1], length: Math.round(Math.sqrt(bd)) };
  });

  // region label spots: inside the region, clear of every token and name plate,
  // away from the region's edge, with horizontal room for the name
  const regions = {};
  const regionIds = [...new Set(regionOf.filter((r) => r))].sort();
  const anchorList = ids.map((t) => [anchors[t].x, anchors[t].y + 18]);
  for (const r of regionIds) {
    const inR = new Uint8Array(W * H);
    for (let k = 0; k < W * H; k++) if (owner[k] >= 0 && regionOf[owner[k]] === r) inR[k] = 1;
    const outside = new Uint8Array(W * H);
    for (let k = 0; k < W * H; k++) outside[k] = inR[k] ? 0 : 1;
    const dEdge = edt(outside, W, H);
    const name = (map.regionNames && map.regionNames[r]) || r;
    const want = name.length * 14 + 60; // half-width in map px the label wants
    let best = null, bestScore = -1;
    for (let y = 8; y < H - 8; y += 6) {
      for (let x = 8; x < W - 8; x += 6) {
        const k = y * W + x;
        if (!inR[k]) continue;
        let dA = 1e9;
        for (const [ax, ay] of anchorList) {
          // tokens and their name plates are wider than tall
          const dx = (x - ax) * 0.8, dy = (y - ay) * 1.4;
          const d = Math.sqrt(dx * dx + dy * dy);
          if (d < dA) dA = d;
        }
        let run = 0;
        for (let s = 4; s <= want; s += 4) {
          if (x - s < 0 || x + s >= W || !inR[k - s] || !inR[k + s]) break;
          run = s;
        }
        const score = Math.min(dA, dEdge[k] * 2.2, run * 0.9);
        if (score > bestScore) { bestScore = score; best = [x, y]; }
      }
    }
    if (best) regions[r] = { x: best[0], y: best[1], room: Math.round(bestScore) };
  }
  Object.assign(regions, geo.regionLabels || {});

  const outDir = path.join(ROOT, "maps", "art");
  fs.mkdirSync(outDir, { recursive: true });
  writePng(path.join(outDir, `${id}_data.png`), W, H, data);
  const art = {
    id, width: W, height: H, order: ids,
    anchors, lanes: laneGeo, regions,
    landAdjacency: landPairs,
  };
  fs.writeFileSync(path.join(outDir, `${id}_art.json`), JSON.stringify(art, null, 1));

  if (derive) {
    // write the derived graph back into the rules file
    const nb = Object.fromEntries(ids.map((t) => [t, new Set()]));
    for (const [a, b] of landPairs) { nb[a].add(b); nb[b].add(a); }
    for (const [a, b] of lanes) { nb[a].add(b); nb[b].add(a); }
    for (const t of ids) map.territories[t].adjacent = [...nb[t]].sort();
    fs.writeFileSync(path.join(ROOT, "maps", id + ".json"), JSON.stringify(map, null, 2) + "\n");
  }

  // preview: region hue, owner-agnostic, borders + coasts + lanes
  const prev = Buffer.alloc(W * H * 4);
  const regionNames = [...new Set(regionOf)].sort();
  const hue = (i) => {
    const h = (i * 0.61803) % 1, s = 0.45, l = 0.55;
    const f = (n) => { const k = (n + h * 12) % 12; return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1)); };
    return [f(0) * 255, f(8) * 255, f(4) * 255];
  };
  for (let k = 0; k < W * H; k++) {
    const o = owner[k];
    let c;
    if (o < 0) {
      const d = dLand[k];
      c = d < 3 ? [30, 40, 60] : [18 + Math.max(0, 30 - d) * 1.2, 32 + Math.max(0, 30 - d) * 1.5, 58 + Math.max(0, 30 - d) * 1.5];
    } else {
      c = hue(regionNames.indexOf(regionOf[o]) + 1);
      if (dBorder[k] < 1.5) c = [40, 30, 25];
      if (dRegion[k] < 2.5) c = [20, 15, 10];
      if (dSea[k] < 2) c = [25, 20, 18];
    }
    prev[k * 4] = c[0]; prev[k * 4 + 1] = c[1]; prev[k * 4 + 2] = c[2]; prev[k * 4 + 3] = 255;
  }
  const dot = (x, y, r, col) => {
    for (let dy = -r; dy <= r; dy++) for (let dx = -r; dx <= r; dx++) {
      if (dx * dx + dy * dy > r * r) continue;
      const X = x + dx, Y = y + dy;
      if (X < 0 || Y < 0 || X >= W || Y >= H) continue;
      const k = Y * W + X;
      prev[k * 4] = col[0]; prev[k * 4 + 1] = col[1]; prev[k * 4 + 2] = col[2];
    }
  };
  for (const l of laneGeo) {
    const n = Math.max(1, Math.round(l.length / 6));
    for (let s = 0; s <= n; s += 2) dot(Math.round(l.ax + (l.bx - l.ax) * s / n), Math.round(l.ay + (l.by - l.ay) * s / n), 3, [240, 230, 200]);
  }
  for (const t of ids) dot(anchors[t].x, anchors[t].y, 10, [240, 230, 200]);
  writePng(path.join(outDir, `${id}_preview.png`), W, H, prev);

  console.log(`${id}: ${W}x${H}, ${T} territories, ${landPairs.length} land borders, ${lanes.length} sea lanes`);
  for (const t of ids) {
    const a = anchors[t];
    if (a.depth < 28) problems.push(`${t} is thin (depth ${a.depth}) — token may overlap its border`);
  }
  for (const p of problems) console.log("  !", p);
  return problems.length;
}

const want = process.argv.slice(2);
let bad = 0;
for (const id of want) bad += generate(id);
process.exit(bad ? 2 : 0);
