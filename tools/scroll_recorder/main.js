// Scroll recorder: opens ChordPro Presenter (a copy of your library, using
// the running app's server) with the Linux app's smooth scrolling, and logs
// every wheel event to scroll_log.txt. Scroll over the Format pane, then
// close the window.
const { app, BrowserWindow } = require('electron');
const fs = require('fs');
const path = require('path');
const os = require('os');
const P = path.join(__dirname, '..', '..');
const OUT = path.join(__dirname, 'scroll_log.txt');
const ud = path.join(os.tmpdir(), 'chordpro-scroll-recorder');
fs.rmSync(ud, { recursive: true, force: true });
fs.mkdirSync(ud, { recursive: true });
fs.cpSync(path.join(os.homedir(), '.config', 'ChordPro Presenter', 'IndexedDB'), path.join(ud, 'IndexedDB'), { recursive: true });
for (const f of fs.readdirSync(path.join(ud, 'IndexedDB'))) fs.rmSync(path.join(ud, 'IndexedDB', f, 'LOCK'), { force: true });
app.setPath('userData', ud);
app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
app.commandLine.appendSwitch('enable-features', 'WaylandWindowDecorations');
const log = fs.createWriteStream(OUT);
const logger = `(() => {
  const t0 = performance.now();
  window.addEventListener('wheel', (e) => {
    const el = e.composedPath()[0];
    console.log('WHEEL ' + JSON.stringify({ t: Math.round(performance.now() - t0), trusted: e.isTrusted,
      x: e.clientX, y: e.clientY, dx: +e.deltaX.toFixed(2), dy: +e.deltaY.toFixed(2), mode: e.deltaMode,
      wdx: e.wheelDeltaX, wdy: e.wheelDeltaY, shift: e.shiftKey, ctrl: e.ctrlKey,
      target: el && (el.tagName + (el.id ? '#' + el.id : '') + (el.className && typeof el.className === 'string' ? '.' + el.className.split(' ').join('.') : '')),
      w: innerWidth, h: innerHeight, dpr: devicePixelRatio }));
    setTimeout(() => console.log('PREVENTED ' + e.defaultPrevented), 0);
  }, { capture: true });
})();`;
app.whenReady().then(async () => {
  const win = new BrowserWindow({ width: 1000, height: 640, title: 'Scroll recorder — scroll over the Format pane, then close' });
  const smooth = fs.readFileSync(path.join(P, 'desktop', 'electron', 'smooth_scroll.js'), 'utf8');
  win.webContents.on('console-message', (_e, _level, message) => {
    if (message.startsWith('WHEEL') || message.startsWith('PREVENTED')) log.write(message + '\n');
  });
  win.webContents.on('dom-ready', async () => {
    await win.webContents.executeJavaScript(logger);
    await win.webContents.executeJavaScript(smooth);
  });
  await win.loadURL('http://localhost:47615/');
  win.on('closed', () => { log.end(); app.quit(); });
});
