// Smooth scrolling for the Linux app (Electron / Chromium).
//
// Chromium on Linux sends touchpad and wheel scrolling as a few large jumps
// (often several hundred pixels at once, 20–40 times a second; its own
// glide after a flick included). Ordinary web pages animate those jumps;
// Flutter applies each one instantly, so lists leap. This takes each
// scroll event before Flutter sees it and hands the distance on in small
// steps, one per screen refresh, easing out — no extra glide is added.
(() => {
  'use strict';
  if (window.__chordproSmoothScroll) return;
  window.__chordproSmoothScroll = true;

  const EASE_MS = 55; // how quickly each jump's distance is used up
  let replaying = false;
  let pendingX = 0;
  let pendingY = 0;
  let where = null; // the latest event: target and pointer position
  let frame = 0;
  let last = 0;

  function send(dx, dy) {
    if (!where || (dx === 0 && dy === 0)) return;
    replaying = true;
    try {
      const ev = new WheelEvent('wheel', {
        deltaX: dx,
        deltaY: dy,
        deltaMode: 0,
        clientX: where.x,
        clientY: where.y,
        screenX: where.sx,
        screenY: where.sy,
        shiftKey: where.shift,
        bubbles: true,
        cancelable: true,
        composed: true,
      });
      // Flutter places the event by offsetX / offsetY, which Chromium gets
      // wrong for a made-up event on a 2× (HiDPI) screen: it would land to
      // the left (e.g. on the chord sheet instead of the Format pane). Use
      // the real event's.
      Object.defineProperty(ev, 'offsetX', { value: where.ox });
      Object.defineProperty(ev, 'offsetY', { value: where.oy });
      where.target.dispatchEvent(ev);
    } finally {
      replaying = false;
    }
  }

  function tick(now) {
    const dt = Math.min(now - last, 50);
    last = now;
    const k = 1 - Math.exp(-dt / EASE_MS);
    let dx = pendingX * k;
    let dy = pendingY * k;
    pendingX -= dx;
    pendingY -= dy;
    if (Math.abs(pendingX) < 0.5 && Math.abs(pendingY) < 0.5) {
      dx += pendingX;
      dy += pendingY;
      pendingX = pendingY = 0;
    }
    send(dx, dy);
    frame = pendingX || pendingY ? requestAnimationFrame(tick) : 0;
  }

  window.addEventListener(
    'wheel',
    (e) => {
      if (replaying || e.ctrlKey) return; // ours, or pinch-zoom
      // Sideways (tag bars, swiping between songs): left as it is. Flutter
      // ignores sideways scrolling sent from a script, and these lists are
      // short enough not to need easing.
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) {
        pendingX = pendingY = 0;
        return;
      }
      const unit = e.deltaMode === 1 ? 19 : e.deltaMode === 2 ? innerHeight : 1;
      e.preventDefault();
      e.stopImmediatePropagation();
      // Scrolling somewhere else: drop what was still going here.
      if (where && (Math.abs(where.x - e.clientX) > 4 || Math.abs(where.y - e.clientY) > 4)) {
        pendingX = pendingY = 0;
      }
      where = {
        target: e.target,
        x: e.clientX,
        y: e.clientY,
        ox: e.offsetX,
        oy: e.offsetY,
        sx: e.screenX,
        sy: e.screenY,
        shift: e.shiftKey,
      };
      pendingX += e.deltaX * unit;
      pendingY += e.deltaY * unit;
      if (!frame) {
        last = performance.now();
        frame = requestAnimationFrame(tick);
      }
    },
    { capture: true, passive: false },
  );

  // Clicking or typing stops what's still moving, as on any page.
  for (const type of ['pointerdown', 'keydown']) {
    window.addEventListener(type, () => (pendingX = pendingY = 0), true);
  }
})();
