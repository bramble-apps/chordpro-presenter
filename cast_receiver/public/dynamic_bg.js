// Dynamic backgrounds on the TV: the app's moving wallpapers (lib/dynamic_bg.dart,
// DynamicRenderer) drawn here, line for line the same, so a Chromecast moves
// the wallpaper itself while the phone sends only its recipe ("spec", from
// DynamicRenderer.castSpec) and the slides as see-through pictures.
// Keep in step with lib/dynamic_bg.dart.
'use strict';

(function (root) {
  var FAM = { linear: 0, terrain: 1, flyover: 2, diffusion: 3, waves: 4, wavesSym: 5, spheres: 6 };

  function mul32(a, b) { return Math.imul(a, b) >>> 0; }
  function hashX(x) { return mul32(x >>> 0, 0x8da6b343); }
  function hashY(y) { return mul32(y >>> 0, 0xd8163841); }
  function hashEnd(h) {
    h = h >>> 0;
    h = (h ^ (h >>> 13)) >>> 0;
    h = mul32(h, 0x85ebca6b);
    h = (h ^ (h >>> 16)) >>> 0;
    return h & 0xffff;
  }
  function hash(x, y) { return hashEnd(hashX(x) ^ hashY(y)); }
  function clamp(x, lo, hi) { return x < lo ? lo : (x > hi ? hi : x); }
  function smoothstep(e0, e1, x) {
    var k = clamp((x - e0) / (e1 - e0), 0, 1);
    return k * k * (3 - 2 * k);
  }
  function fract(x) { return x - Math.trunc(x); }

  /** A renderer for [spec] at [w] × [h] pixels. */
  function DynamicRenderer(spec, w, h) {
    this.w = Math.max(w, 2);
    this.h = Math.max(h, 2);
    var s = spec;
    this.stops = new Float64Array(s.stops);
    this.fam = FAM[s.family] || 0;
    this.factor = s.factor;
    this.aspect = this.w / this.h;
    var n = s.n;
    this.speed = n.speed; this.scale = n.scale; this.angle = n.angle;
    this.contrast = n.contrast; this.brightness = n.brightness;
    this.saturation = n.saturation; this.gamma = n.gamma;
    this.grain = n.grain; this.grainSpeed = n.grainSpeed; this.paletteOffset = n.paletteOffset;
    this.amp = n.amp; this.octaves = n.octaves; this.noiseScale = n.noiseScale;
    this.noiseSpeed = n.noiseSpeed; this.movement = n.movement;
    this.fogDistance = n.fogDistance; this.fogPower = n.fogPower; this.zoom = n.zoom;
    this.density = n.density; this.waveAmp = n.waveAmp; this.envelope = n.envelope;
    this.yOffset = n.yOffset; this.blur = n.blur; this.opacity = n.opacity; this.offset = n.offset;
    this.multiply = !!s.multiply;
    this.bgR = s.bg[0]; this.bgG = s.bg[1]; this.bgB = s.bg[2];
    var gam = Math.sqrt(clamp(this.gamma, 0.3, 3));
    this.gammaTable = null;
    if (gam !== 1) {
      var table = new Float64Array(4098);
      for (var i = 0; i < table.length; i++) table[i] = Math.pow(i / 4096, gam);
      this.gammaTable = table;
    }
    this.t = 0; this.tReal = 0;
    this.layers = [];
    this.skyTopR = 0; this.skyTopG = 0; this.skyTopB = 0;
    this.skyBotR = 0; this.skyBotG = 0; this.skyBotB = 0;
    this.grainX = new Uint32Array(this.w);
    this.ballX = new Float64Array(12); this.ballY = new Float64Array(12); this.ballR2 = new Float64Array(12);
    this.r = 0; this.g = 0; this.b = 0;
    this.cellX = new Int32Array(8); this.cellY = new Int32Array(8);
    this.cell = new Float64Array(32); this.cellSet = new Uint8Array(8);
  }

  var P = DynamicRenderer.prototype;

  P.begin = function (t) {
    this.t = t * this.factor;
    this.tReal = t;
    this.cellSet.fill(0);
    this.columns();
  };

  P.pal = function (x) {
    var s = this.stops, n = s.length / 4;
    if (x <= s[0]) { this.r = s[1]; this.g = s[2]; this.b = s[3]; return; }
    for (var i = 1; i < n; i++) {
      var o = i * 4;
      if (x <= s[o]) {
        var p = o - 4;
        var k = clamp((x - s[p]) / Math.max(s[o] - s[p], 1e-5), 0, 1);
        k = k * k * (3 - 2 * k);
        this.r = s[p + 1] + (s[o + 1] - s[p + 1]) * k;
        this.g = s[p + 2] + (s[o + 2] - s[p + 2]) * k;
        this.b = s[p + 3] + (s[o + 3] - s[p + 3]) * k;
        return;
      }
    }
    var q = (n - 1) * 4;
    this.r = s[q + 1]; this.g = s[q + 2]; this.b = s[q + 3];
  };

  P.noise = function (x, y, slot) {
    var xf = Math.floor(x), yf = Math.floor(y);
    var fx = x - xf, fy = y - yf;
    var ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy);
    var xi = xf | 0, yi = yf | 0;
    var o = slot * 4, cell = this.cell;
    if (this.cellSet[slot] === 0 || this.cellX[slot] !== xi || this.cellY[slot] !== yi) {
      this.cellSet[slot] = 1;
      this.cellX[slot] = xi;
      this.cellY[slot] = yi;
      cell[o] = hash(xi, yi) / 65535.0;
      cell[o + 1] = hash(xi + 1, yi) / 65535.0;
      cell[o + 2] = hash(xi, yi + 1) / 65535.0;
      cell[o + 3] = hash(xi + 1, yi + 1) / 65535.0;
    }
    var a = cell[o], b = cell[o + 1], c = cell[o + 2], d = cell[o + 3];
    return a + (b - a) * ux + (c - a) * uy + (a - b - c + d) * ux * uy;
  };

  P.fbm = function (x, y, octaves, slot) {
    slot = slot || 0;
    var v = 0.0, a = 0.5, norm = 0.0;
    var n = Math.ceil(octaves);
    var whole = Math.floor(octaves);
    for (var i = 0; i < n; i++) {
      var w = i < whole ? 1.0 : Math.max(fract(octaves), 0.001);
      v += a * w * this.noise(x, y, (slot + i) & 7);
      norm += a * w;
      a *= 0.5;
      var nx = x * 1.6 + y * 1.2, ny = -x * 1.2 + y * 1.6;
      x = nx + 17.3;
      y = ny + 9.1;
    }
    return v / Math.max(norm, 1e-4);
  };

  P.columns = function () {
    var layers = [], t = this.t, w = this.w, x, u, i;
    this.pal(0);
    this.skyTopR = this.skyBotR = this.r;
    this.skyTopG = this.skyBotG = this.g;
    this.skyTopB = this.skyBotB = this.b;
    if (this.fam === FAM.terrain && this.noiseScale < 0.5) {
      var drift0 = t * 0.12 * (this.movement / 100);
      var morph0 = t * 0.05 * Math.sqrt(Math.max(this.noiseSpeed, 0.5));
      var amp0 = clamp(this.amp / 4, 0.15, 2);
      var ys0 = new Float64Array(w);
      for (x = 0; x < w; x++) {
        u = x / w - 0.5;
        var hgt0 = this.fbm(u * this.aspect * 0.55 + drift0 + 3.1, 0.7 + morph0, 2) - 0.5;
        ys0[x] = 0.56 - u * 0.08 - hgt0 * amp0 * 1.2;
      }
      this.pal(0);
      var r0 = this.r, g0 = this.g, b0 = this.b;
      this.pal(0.25);
      this.skyTopR = r0 + (this.r - r0) * 0.1;
      this.skyTopG = g0 + (this.g - g0) * 0.1;
      this.skyTopB = b0 + (this.b - b0) * 0.1;
      this.skyBotR = r0 + (this.r - r0) * 0.16;
      this.skyBotG = g0 + (this.g - g0) * 0.16;
      this.skyBotB = b0 + (this.b - b0) * 0.16;
      layers.push({ ys: ys0, r: this.r, g: this.g, b: this.b, alpha: 1, soft: 0.03 + this.blur * 0.02 });
    } else if (this.fam === FAM.terrain || this.fam === FAM.flyover) {
      var n = 28;
      var flyover = this.fam === FAM.flyover;
      var mv = this.movement;
      var fly = flyover
        ? t * 0.04 * (Math.max(Math.abs(mv), 20) / 100) * ((mv < 0 || Object.is(mv, -0)) ? 0.5 : 1.0)
        : 0.0;
      var drift = t * 0.12 * (mv / 100);
      var morph = t * 0.05 * Math.sqrt(Math.max(this.noiseSpeed, 0.5));
      this.pal(0);
      var rr0 = this.r, gg0 = this.g, bb0 = this.b;
      this.pal(0.2);
      this.skyBotR = rr0 + (this.r - rr0) * 0.5;
      this.skyBotG = gg0 + (this.g - gg0) * 0.5;
      this.skyBotB = bb0 + (this.b - bb0) * 0.5;
      var freq = clamp(this.noiseScale / 4, 1.1, 3) * clamp(this.zoom / 50, 0.5, 2);
      var amp = clamp(this.amp / 4, 0.15, 2);
      var oct = Math.max(this.octaves * 0.5, 1.0);
      for (i = 0; i < n; i++) {
        var d = 1 - (i + 0.5) / n;
        var pass = 0.0;
        if (flyover) {
          var z = d + fly;
          pass = Math.floor(z);
          d = z - pass;
        }
        var persp = 1 / (0.35 + d * 2.2);
        var horizon = flyover ? 0.30 : 0.42;
        var base = horizon + (1 - d) * (1 - horizon) * 0.95;
        var seed = i * 7.31 + pass * 3.7;
        var ys = new Float64Array(w);
        for (x = 0; x < w; x++) {
          u = x / w - 0.5;
          var nx = u * this.aspect * freq * (0.25 + d * 1.6) * 3 + seed + drift;
          var hgt = this.fbm(nx, seed * 0.37 + morph, oct);
          var ridge = Math.max(hgt - 0.3, 0) * amp * persp * 0.32;
          ys[x] = base - ridge;
        }
        var near = 1 - d;
        this.pal(flyover ? 0.28 + 0.42 * near : 0.15 + 0.85 * near);
        var fog = Math.pow(clamp(d / Math.max(this.fogDistance, 0.2), 0, 1), Math.max(this.fogPower, 1) / 4);
        var k = fog * 0.85;
        var cr = this.r + (this.skyBotR - this.r) * k;
        var cg = this.g + (this.skyBotG - this.g) * k;
        var cb = this.b + (this.skyBotB - this.b) * k;
        var fade = flyover ? clamp(Math.min((1 - d) * 6, d * 12), 0, 1) : 1.0;
        var light = new Float64Array(w);
        for (x = 0; x < w; x++) {
          var la = ys[x < 2 ? 0 : x - 2];
          var lb = ys[Math.min(x + 2, w - 1)];
          light[x] = clamp(1 + (la - lb) * w * 0.02, 0.6, 1.35);
        }
        layers.push({ ys: ys, r: cr, g: cg, b: cb, alpha: fade, soft: 0.004, light: light });
      }
    } else if (this.fam === FAM.waves || this.fam === FAM.wavesSym) {
      var wn = clamp(Math.round(this.density * 2), 3, 12) | 0;
      var soft = 0.004 + this.blur * 0.05;
      var alpha = Math.min(Math.max(this.opacity, 0.15), 0.6);
      for (i = 0; i < wn; i++) {
        var fi = i;
        this.pal((fi + 0.5) / wn);
        var k1 = 0.6 + fract(fi * 0.37) * this.scale * 0.2;
        var k2 = 1.3 + fract(fi * 0.61) * this.scale * 0.3;
        var ph = fi * 1.7 + this.offset + t * this.speed * 0.02 * (1 + fi * 0.13);
        var wys = new Float64Array(w);
        for (x = 0; x < w; x++) {
          u = x / w;
          var e = 2 * u - 1;
          var env = this.envelope > 0 ? Math.max(1 - this.envelope * 0.5 * e * e, 0.2) : 1.0;
          var a = (0.04 + 0.045 * Math.min(this.waveAmp, 10)) * env;
          var v = Math.sin(u * k1 * 3 + ph) * 0.6 + Math.sin(u * k2 * 3 - ph * 1.3) * 0.4;
          wys[x] = v * a;
        }
        layers.push({ ys: wys, r: this.r, g: this.g, b: this.b, alpha: alpha, soft: soft });
      }
    }
    this.layers = layers;
  };

  /** Draws rows [y0, y1) into [out] (RGBA bytes, w × h × 4). */
  P.rows = function (y0, y1, out) {
    var w = this.w, h = this.h, t = this.t;
    var sat = 1 + (clamp(this.saturation, 0, 2) - 1) * 0.7;
    var con = 1 + (clamp(this.contrast, 0.3, 2) - 1) * 0.6;
    var gam = Math.sqrt(clamp(this.gamma, 0.3, 3));
    var gammaTable = this.gammaTable;
    var brightness = this.brightness;
    var aspect = this.aspect;
    var fam = this.fam;
    var grainFrame = this.grain > 0 ? Math.floor(this.tReal * (6 + clamp(this.grainSpeed, 0, 100) * 0.18)) : 0;
    var grain = this.grain * 0.01;
    var grainX = this.grainX, x, y, i, k, l;
    if (this.grain > 0) {
      for (x = 0; x < w; x++) grainX[x] = hashX(x + grainFrame * 7919);
    }
    var rad = this.angle * Math.PI / 180;
    var dx = Math.cos(rad), dy = -Math.sin(rad);
    var linS = 1 / Math.max(this.scale, 0.2);
    var flow = Math.sin(t * this.speed * 0.006) * (0.15 + 0.1 * Math.min(this.scale, 3));
    var ts = t * 0.09 * (this.noiseSpeed + this.speed * 0.01);
    var sts = t * Math.max(this.speed * 0.004, 0.03) + this.offset;
    var ballX = this.ballX, ballY = this.ballY, ballR2 = this.ballR2;
    if (fam === FAM.spheres) {
      for (l = 0; l < 3; l++) {
        var fl = l;
        var lx = aspect * (0.5 + 0.4 * Math.sin(sts * 0.31 + fl * 2.4));
        var ly = 0.5 + 0.4 * Math.cos(sts * 0.23 + fl * 1.7);
        for (k = 0; k < 4; k++) {
          var fb = k + fl * 4;
          ballX[l * 4 + k] = lx + 0.35 * Math.sin(sts * (0.7 + 0.13 * fb) + fb * 2.1);
          ballY[l * 4 + k] = ly + 0.3 * Math.cos(sts * (0.5 + 0.11 * fb) + fb * 1.3);
          var brad = 0.13 + 0.1 * fract(fb * 0.77) * clamp(this.noiseScale / 5, 0.5, 1.5);
          ballR2[l * 4 + k] = brad * brad;
        }
      }
    }
    var ballEdge = 2.0 / h * 3;
    var ballAlpha = 0.75 + 0.25 * Math.min(this.opacity, 1);
    var sym = fam === FAM.wavesSym;
    var center = (sym ? 0.5 : 0.62) - this.yOffset * 0.25;
    var broad = fam === FAM.terrain && this.noiseScale < 0.5;
    var layers = this.layers;
    var sphereStops = [1.0, 0.75, 0.25];

    for (y = y0; y < y1; y++) {
      var v = (y + 0.5) / h;
      var o = y * w * 4;
      var grainY = hashY(y - grainFrame * 104729);
      for (x = 0; x < w; x++) {
        var u = (x + 0.5) / w;
        var r, g, b, ly2, rr, cover;
        if (fam === FAM.linear) {
          var px = (u - 0.5) * aspect, py = v - 0.5;
          var warp = this.fbm(px * 0.9 + t * 0.09 * this.speed / 40, py * 0.9 - t * 0.07 * this.speed / 40, 2) - 0.5;
          var along = (px * dx + py * dy) / Math.max(aspect, 1) * linS * 1.1 + 0.55 + warp * 0.3;
          var kk = clamp(along + flow + this.paletteOffset, -0.5, 1.5);
          if (kk < 0) kk = -kk; else if (kk > 1) kk = 2 - kk;
          this.pal(kk);
          r = this.r; g = this.g; b = this.b;
        } else if (fam === FAM.diffusion) {
          var dpx = (u - 0.5) * aspect * this.scale * 0.55;
          var dpy = (v - 0.5) * this.scale * 0.55;
          var q0 = this.fbm(dpx + ts, dpy - ts * 0.7, 2, 0);
          var q1 = this.fbm(dpx - ts * 0.6 + 5.2, dpy + ts + 1.3, 2, 2);
          var dn = this.fbm(dpx * 0.7 + q0 * this.amp * 0.45, dpy * 0.7 + q1 * this.amp * 0.45, 2, 4);
          this.pal(clamp((dn - 0.2) * 1.7, 0, 1));
          r = this.r; g = this.g; b = this.b;
        } else if (fam === FAM.terrain && broad) {
          var bl = layers[0];
          rr = bl.ys[x];
          var glow = Math.exp(-Math.max(rr - v, 0) / 0.09) * 0.35;
          this.pal(0.25);
          var sr = this.skyTopR + (this.skyBotR - this.skyTopR) * v;
          var sg = this.skyTopG + (this.skyBotG - this.skyTopG) * v;
          var sb = this.skyTopB + (this.skyBotB - this.skyTopB) * v;
          var skyR = sr + (this.r - sr) * glow;
          var skyG = sg + (this.g - sg) * glow;
          var skyB = sb + (this.b - sb) * glow;
          var dd = clamp((v - rr) / Math.max(1 - rr, 0.05), 0, 1);
          this.pal(0.25 + Math.pow(dd, 1.5) * 0.5);
          var bk = smoothstep(rr - bl.soft, rr + bl.soft, v);
          r = skyR + (this.r - skyR) * bk;
          g = skyG + (this.g - skyG) * bk;
          b = skyB + (this.b - skyB) * bk;
        } else if (fam === FAM.terrain || fam === FAM.flyover) {
          r = this.skyTopR + (this.skyBotR - this.skyTopR) * v;
          g = this.skyTopG + (this.skyBotG - this.skyTopG) * v;
          b = this.skyTopB + (this.skyBotB - this.skyTopB) * v;
          var first = layers.length - 1;
          while (first > 0) {
            var fl2 = layers[first];
            if (fl2.alpha === 1 && v >= fl2.ys[x] + fl2.soft) break;
            first--;
          }
          for (i = first; i < layers.length; i++) {
            var tl = layers[i];
            rr = tl.ys[x];
            if (v <= rr - tl.soft) continue;
            cover = smoothstep(rr - tl.soft, rr + tl.soft, v) * tl.alpha;
            if (cover > 0) {
              var below = Math.max(v - rr, 0) * 0.6;
              var shade = tl.light[x] * (1 - (below < 0.15 ? below : 0.15));
              r += (tl.r * shade - r) * cover;
              g += (tl.g * shade - g) * cover;
              b += (tl.b * shade - b) * cover;
            }
          }
        } else if (fam === FAM.waves || fam === FAM.wavesSym) {
          r = this.bgR; g = this.bgG; b = this.bgB;
          for (i = 0; i < layers.length; i++) {
            var wl = layers[i];
            rr = wl.ys[x];
            if (sym) {
              var half = Math.abs(rr) + 0.02;
              if (Math.abs(v - center) >= half + wl.soft) continue;
              cover = 1 - smoothstep(half - wl.soft, half + wl.soft, Math.abs(v - center));
            } else {
              if (v <= center + rr - wl.soft) continue;
              cover = smoothstep(center + rr - wl.soft, center + rr + wl.soft, v);
            }
            if (cover > 0) {
              var wk = cover * wl.alpha;
              if (this.multiply) {
                r += (r * wl.r - r) * wk;
                g += (g * wl.g - g) * wk;
                b += (b * wl.b - b) * wk;
              } else {
                r += (wl.r - r) * wk;
                g += (wl.g - g) * wk;
                b += (wl.b - b) * wk;
              }
            }
          }
        } else {
          // spheres
          var spx = u * aspect, spy = v;
          this.pal(0.5);
          r = this.r; g = this.g; b = this.b;
          for (l = 0; l < 3; l++) {
            var field = 0.0;
            for (k = l * 4; k < l * 4 + 4; k++) {
              var ex = spx - ballX[k], ey = spy - ballY[k];
              var d2 = ex * ex + ey * ey;
              field += ballR2[k] / (d2 > 1e-4 ? d2 : 1e-4);
            }
            cover = smoothstep(1 - ballEdge, 1 + ballEdge, field);
            if (cover > 0) {
              this.pal(sphereStops[l]);
              var sk = cover * ballAlpha;
              r += (this.r - r) * sk;
              g += (this.g - g) * sk;
              b += (this.b - b) * sk;
            }
          }
        }

        var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
        r = (lum + (r - lum) * sat - 0.5) * con + 0.5 + brightness;
        g = (lum + (g - lum) * sat - 0.5) * con + 0.5 + brightness;
        b = (lum + (b - lum) * sat - 0.5) * con + 0.5 + brightness;
        r = r > 0 ? r : 0;
        g = g > 0 ? g : 0;
        b = b > 0 ? b : 0;
        if (gammaTable !== null) {
          var f, gi;
          if (r < 1) { f = r * 4096; gi = f | 0; r = gammaTable[gi] + (gammaTable[gi + 1] - gammaTable[gi]) * (f - gi); }
          else r = Math.pow(r, gam);
          if (g < 1) { f = g * 4096; gi = f | 0; g = gammaTable[gi] + (gammaTable[gi + 1] - gammaTable[gi]) * (f - gi); }
          else g = Math.pow(g, gam);
          if (b < 1) { f = b * 4096; gi = f | 0; b = gammaTable[gi] + (gammaTable[gi + 1] - gammaTable[gi]) * (f - gi); }
          else b = Math.pow(b, gam);
        }
        if (this.grain > 0) {
          var gr = (hashEnd(grainX[x] ^ grainY) / 65535.0 - 0.5) * grain;
          r += gr; g += gr; b += gr;
        }
        out[o] = (clamp(r, 0, 1) * 255 + 0.5) | 0;
        out[o + 1] = (clamp(g, 0, 1) * 255 + 0.5) | 0;
        out[o + 2] = (clamp(b, 0, 1) * 255 + 0.5) | 0;
        out[o + 3] = 255;
        o += 4;
      }
    }
  };

  /** The whole frame at time [t] (seconds), as RGBA bytes. */
  DynamicRenderer.frame = function (spec, t, w, h) {
    var r = new DynamicRenderer(spec, w, h);
    r.begin(t);
    var out = new Uint8ClampedArray(r.w * r.h * 4);
    r.rows(0, r.h, out);
    return out;
  };

  root.DynamicRenderer = DynamicRenderer;
  if (typeof module !== 'undefined' && module.exports) module.exports = DynamicRenderer;
})(typeof window !== 'undefined' ? window : globalThis);
