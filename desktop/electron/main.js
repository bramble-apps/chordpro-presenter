// ChordPro Presenter for the desktop (Linux, Windows, macOS): the web app in its own window (Chromium,
// so animation follows the screen's refresh rate), with the app's local
// server (tools/serve.py) started alongside it for everything a browser
// can't do on its own: casting, other screens on the Wi-Fi (QR link),
// song search, fetching song pages, uploaded backgrounds.

const { app, BrowserWindow, Menu, dialog, session, shell } = require('electron');
const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const os = require('os');
const path = require('path');

// Fixed, so the library (kept in this address's browser storage) is found
// again on every start.
const PORT = 47615;
const ORIGIN = `http://localhost:${PORT}`;

// Native Wayland on Linux (sharp text, the screen's real refresh rate) with
// the usual window title bar.
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
  app.commandLine.appendSwitch('enable-features', 'WaylandWindowDecorations');
}

// One copy at a time: starting it again just brings the open window
// forward (see 'second-instance').
const firstCopy = app.requestSingleInstanceLock();
if (!firstCopy) app.quit();

const packaged = app.isPackaged;
const project = path.join(__dirname, '..', '..');
const paths = {
  web: packaged ? path.join(process.resourcesPath, 'web') : path.join(project, 'build', 'web'),
  server: packaged
    ? path.join(process.resourcesPath, 'server', 'serve.py')
    : path.join(project, 'tools', 'serve.py'),
  pylib: packaged
    ? path.join(process.resourcesPath, 'server', 'pylib')
    : path.join(__dirname, 'pylib'),
  data: path.join(app.getPath('userData'), 'server'),
};

let server = null;
let main = null;

/// The Python that runs the local server: the one bundled with the app (Windows and macOS builds
/// carry their own, see .github/workflows/release.yml), else the computer's own.
function pythonCommand() {
  if (packaged) {
    const dir = path.join(process.resourcesPath, 'python');
    const exe = process.platform === 'win32'
      ? path.join(dir, 'python.exe')
      : path.join(dir, 'bin', 'python3');
    if (fs.existsSync(exe)) return exe;
  }
  return process.platform === 'win32' ? 'python' : 'python3';
}

function startServer() {
  server = spawn(
    pythonCommand(),
    [
      paths.server,
      '--port', String(PORT),
      '--root', paths.web,
      '--data', paths.data,
      '--exit-with-parent',
    ],
    {
      env: {
        ...process.env,
        PYTHONPATH: paths.pylib,
        PYTHONNOUSERSITE: '1',
        PYTHONUNBUFFERED: '1',
      },
      stdio: ['ignore', 'inherit', 'inherit'],
    },
  );
  server.on('error', (e) => {
    dialog.showErrorBox(
      'ChordPro Presenter',
      `Couldn't start the app's local server (Python 3 is needed):\n${e.message}`,
    );
    app.quit();
  });
}

function ping() {
  return new Promise((resolve) => {
    const req = http.get(`${ORIGIN}/relay/ping`, (res) => {
      res.resume();
      resolve(res.statusCode === 200);
    });
    req.on('error', () => resolve(false));
    req.setTimeout(500, () => {
      req.destroy();
      resolve(false);
    });
  });
}

async function waitForServer() {
  for (let i = 0; i < 100; i++) {
    if (await ping()) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

// ---- One-time import from the earlier native Linux app ----
// It kept each stored value as a file (store/<key, base64url>.txt / .bin);
// the web app keeps the same keys in IndexedDB.
function nativeStoreEntries() {
  const dir = path.join(
    os.homedir(),
    '.local/share/com.bilingualprojector.bilingual_projector/bilingual_projector/store',
  );
  if (!fs.existsSync(dir)) return [];
  const entries = [];
  for (const name of fs.readdirSync(dir)) {
    const m = /^(.*)\.(txt|bin)$/.exec(name);
    if (!m) continue;
    const key = Buffer.from(m[1], 'base64url').toString('utf8');
    const file = path.join(dir, name);
    entries.push(
      m[2] === 'txt'
        ? { key, text: fs.readFileSync(file, 'utf8') }
        : { key, bytes: fs.readFileSync(file).toString('base64') },
    );
  }
  return entries;
}

async function importNativeLibrary(win) {
  const flag = path.join(app.getPath('userData'), 'imported-native-library');
  if (fs.existsSync(flag)) return;
  const entries = nativeStoreEntries();
  if (entries.length > 0) {
    // A page of the app's own address (not the app itself, so nothing
    // reads or writes the library meanwhile).
    await win.loadURL(`${ORIGIN}/manifest.json`);
    await win.webContents.executeJavaScript(`
      new Promise((resolve, reject) => {
        const entries = ${JSON.stringify(entries)};
        const open = indexedDB.open('bilingual_projector', 1);
        open.onupgradeneeded = () => open.result.createObjectStore('kv');
        open.onerror = () => reject(open.error);
        open.onsuccess = () => {
          const db = open.result;
          const tx = db.transaction('kv', 'readwrite');
          const kv = tx.objectStore('kv');
          // Never replace a library that's already here.
          const check = kv.get('bilingual_projector_state');
          check.onsuccess = () => {
            if (check.result != null) { resolve('kept'); return; }
            for (const e of entries) {
              if (e.text != null) {
                kv.put(e.text, e.key);
              } else {
                const bin = atob(e.bytes);
                const bytes = new Uint8Array(bin.length);
                for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
                kv.put(bytes, e.key);
              }
            }
          };
          tx.oncomplete = () => resolve('imported');
          tx.onerror = () => reject(tx.error);
        };
      })`);
  }
  fs.mkdirSync(path.dirname(flag), { recursive: true });
  fs.writeFileSync(flag, new Date().toISOString());
}

const smoothScroll = fs.readFileSync(path.join(__dirname, 'smooth_scroll.js'), 'utf8');

/// Smooth scrolling in every window of the app (see smooth_scroll.js).
function addSmoothScroll(contents) {
  contents.on('dom-ready', () => {
    if (contents.getURL().startsWith(ORIGIN)) {
      contents.executeJavaScript(smoothScroll).catch(() => {});
    }
  });
}

function windowOptions(extra = {}) {
  return {
    width: 1280,
    height: 800,
    backgroundColor: '#121212',
    autoHideMenuBar: true,
    icon: path.join(paths.web, 'icons', 'Icon-512.png'),
    webPreferences: { contextIsolation: true, sandbox: true },
    ...extra,
  };
}

// ---- Importing from a song site the person has open ----
// Some sites (Cifra Club) turn away apps that fetch their pages. So the page
// opens in a real browser window here, and an Import button on it reads the
// song off the page the person is looking at; it reaches the app through
// the local server's relay (the app is listening under the id).

// The same as cifraPageScript in lib/song_sources.dart.
const CIFRA_PAGE_SCRIPT = `(() => {
  const pre = document.querySelector('pre');
  // "Song (chords) - Artist - Cifra Club"
  const parts = document.title.split(' - ');
  const h1 = document.querySelector('h1');
  const title = parts.length >= 3
      ? parts.slice(0, -2).join(' - ').replace(/\\s*\\([^)]*\\)\\s*$/, '')
      : (h1 ? h1.textContent.trim() : '');
  const artist = parts.length >= 3 ? parts[parts.length - 2] : '';
  const keyLabel = [...document.querySelectorAll('span, b, a, div, p')]
      .map((e) => e.textContent.trim())
      .find((t) => t.length < 24 &&
          /^(key|tom|tono|tonalidad)\\s*:\\s*[A-G]/i.test(t));
  return JSON.stringify({
    pre: pre ? (pre.innerText || pre.textContent) : '',
    title: title.trim(),
    artist: artist.trim(),
    key: keyLabel || '',
    url: location.href,
  });
})()`;

const IMPORT_BUTTON = `(() => {
  if (document.getElementById('cpp-import')) return;
  const b = document.createElement('button');
  b.id = 'cpp-import';
  b.textContent = 'Import into ChordPro';
  Object.assign(b.style, {
    position: 'fixed', right: '20px', bottom: '20px', zIndex: '2147483647',
    padding: '12px 20px', font: '600 16px system-ui, sans-serif',
    background: '#1f1f1f', color: '#fff', border: '0', borderRadius: '24px',
    boxShadow: '0 2px 10px rgba(0,0,0,.35)', cursor: 'pointer',
  });
  b.onclick = () => { location.hash = 'cpp-import-now'; };
  document.body.appendChild(b);
})()`;

function relaySend(message) {
  const body = JSON.stringify(message);
  const req = http.request(`${ORIGIN}/relay/send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Client': 'import' },
  });
  req.on('error', () => {});
  req.end(body);
}

function openImportWindow(url, id) {
  const w = new BrowserWindow({
    width: 1100,
    height: 860,
    title: 'Import into ChordPro',
    autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, sandbox: true },
  });
  // A real Chromium window the person browses in: it says so, without the
  // app's own "Electron/…" token (sites turn that away as an app).
  w.webContents.setUserAgent(
    w.webContents
      .getUserAgent()
      .replace(/ Electron\/\S+/, '')
      .replace(/ [\w-]+\/[\d.]+ Chrome/, ' Chrome'),
  );
  let imported = false;
  const addButton = () =>
    w.webContents.executeJavaScript(IMPORT_BUTTON).catch(() => {});
  w.webContents.on('did-finish-load', addButton);
  w.webContents.on('did-navigate-in-page', async (_e, at) => {
    if (!at.endsWith('#cpp-import-now')) return;
    try {
      const page = JSON.parse(
        await w.webContents.executeJavaScript(CIFRA_PAGE_SCRIPT),
      );
      imported = true;
      relaySend({ type: 'browserImport', id, page });
      w.close();
    } catch {
      // Not readable (yet): the button stays for another try.
    }
  });
  w.on('closed', () => {
    if (!imported) relaySend({ type: 'browserImportClosed', id });
  });
  // Links on the page stay in this window; new windows open in the
  // person's browser.
  w.webContents.setWindowOpenHandler(({ url: next }) => {
    shell.openExternal(next);
    return { action: 'deny' };
  });
  w.loadURL(url).catch(() => {});
}

async function createWindow() {
  main = new BrowserWindow(windowOptions({ title: 'ChordPro Presenter', show: false }));
  main.once('ready-to-show', () => main.show());
  addSmoothScroll(main.webContents);
  main.webContents.on('did-create-window', (w) => addSmoothScroll(w.webContents));

  // Projector windows (and other pages of the app) open as app windows;
  // anything else (song sites, YouTube…) in the person's browser.
  main.webContents.setWindowOpenHandler(({ url }) => {
    // A song site to import from (#cpp-import=<id>, see the app's
    // importFromBrowser): opened here for the person to look at.
    const importId = /#cpp-import=([\w-]+)$/.exec(url)?.[1];
    if (importId) {
      openImportWindow(url.replace(/#cpp-import=[\w-]+$/, ''), importId);
      return { action: 'deny' };
    }
    if (url.startsWith(ORIGIN)) {
      return {
        action: 'allow',
        overrideBrowserWindowOptions: windowOptions({
          title: 'ChordPro Presenter — Projector',
          backgroundColor: '#000000',
        }),
      };
    }
    shell.openExternal(url);
    return { action: 'deny' };
  });
  main.on('closed', () => {
    main = null;
    // Closing the main window closes the projector windows too.
    for (const w of BrowserWindow.getAllWindows()) w.close();
  });

  await importNativeLibrary(main);
  await main.loadURL(`${ORIGIN}/`).catch(() => {});
}


// Files opened with the app ("Open with…", or given when starting it):
// ChordPro, PDFs, pictures, backups. Handed to the page, which imports
// them as if they'd been dropped on it.
const MAX_OPEN_BYTES = 100 * 1024 * 1024;

function filesFrom(argv) {
  const out = [];
  for (const arg of argv.slice(packaged ? 1 : 2)) {
    if (!arg || arg.startsWith('-')) continue;
    if (arg.startsWith('chordpropresenter:')) {
      out.push(arg);
      continue;
    }
    let p = arg;
    try {
      if (arg.startsWith('file://')) p = decodeURIComponent(new URL(arg).pathname);
      const st = fs.statSync(p);
      if (st.isFile() && st.size <= MAX_OPEN_BYTES) out.push(p);
    } catch {
      // Not a file (an option or a stale path): ignored.
    }
  }
  return out;
}

async function openFiles(paths) {
  if (!main || !paths.length) return;
  // Remote control links (chordpropresenter://next) go as they are.
  const files = paths.map((p) =>
    p.startsWith('chordpropresenter:')
      ? { url: p }
      : { name: path.basename(p), b64: fs.readFileSync(p).toString('base64') },
  );
  // Kept until the page is ready to take them (it may still be starting).
  await main.webContents
    .executeJavaScript(
      `window.__chordproPending = (window.__chordproPending || []).concat(${JSON.stringify(files)});` +
        `window.__chordproOpen && window.__chordproOpen();`,
    )
    .catch(() => {});
}

// ---- Updates ----
// The Windows installer and the AppImage update themselves from the GitHub
// releases (electron-updater: downloads in the background, installs on quit).
// The macOS app (not signed with an Apple certificate, so it can't replace
// itself) and the Flatpak bundle say when a newer release is out instead.
const RELEASES = 'https://api.github.com/repos/bramble-apps/chordpro-presenter/releases/latest';

function newer(a, b) {
  const pa = a.replace(/^v/, '').split('.').map(Number);
  const pb = b.replace(/^v/, '').split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) > (pb[i] || 0);
  }
  return false;
}

function tellAboutNewRelease() {
  const https = require('https');
  const req = https.get(RELEASES, { headers: { 'User-Agent': 'ChordPro-Presenter', Accept: 'application/vnd.github+json' } }, (res) => {
    let body = '';
    res.on('data', (d) => { body += d; });
    res.on('end', async () => {
      try {
        const rel = JSON.parse(body);
        if (!rel.tag_name || !newer(rel.tag_name, app.getVersion())) return;
        const { response } = await dialog.showMessageBox(main, {
          type: 'info',
          message: `ChordPro Presenter ${rel.tag_name.replace(/^v/, '')} is available`,
          detail: `You have ${app.getVersion()}.`,
          buttons: ['Download', 'Later'],
          defaultId: 0,
          cancelId: 1,
        });
        if (response === 0) shell.openExternal(rel.html_url);
      } catch {
        // No answer worth showing (offline, rate-limited): try again next start.
      }
    });
  });
  req.on('error', () => {});
  req.setTimeout(10000, () => req.destroy());
}

function checkForUpdates() {
  if (!packaged) return;
  const flatpak = !!process.env.FLATPAK_ID || fs.existsSync('/.flatpak-info');
  const selfUpdating = process.platform === 'win32' || (process.platform === 'linux' && process.env.APPIMAGE && !flatpak);
  if (selfUpdating) {
    try {
      const { autoUpdater } = require('electron-updater');
      autoUpdater.checkForUpdatesAndNotify().catch(() => {});
    } catch {
      // (electron-updater missing in a local build: no updates.)
    }
  } else {
    tellAboutNewRelease();
  }
}

app.on('second-instance', (_event, argv) => {
  if (main) {
    if (main.isMinimized()) main.restore();
    main.focus();
    openFiles(filesFrom(argv));
  }
});

app.whenReady().then(async () => {
  if (!firstCopy) return;
  Menu.setApplicationMenu(null);
  // Microphone (tuner), full screen (projector) and copying are allowed.
  session.defaultSession.setPermissionRequestHandler((_wc, permission, done) => {
    done(['media', 'fullscreen', 'clipboard-sanitized-write', 'clipboard-read'].includes(permission));
  });
  session.defaultSession.setPermissionCheckHandler((_wc, permission) =>
    ['media', 'fullscreen', 'clipboard-sanitized-write', 'clipboard-read'].includes(permission),
  );
  // Exports (PDF, PPTX, backups…) ask where to save (Electron's default
  // for downloads without a set path is the system "Save as" window).

  startServer();
  if (!(await waitForServer())) {
    dialog.showErrorBox(
      'ChordPro Presenter',
      `The app's local server didn't start (port ${PORT} may be in use).`,
    );
    app.quit();
    return;
  }
  await createWindow();
  await openFiles(filesFrom(process.argv));
  setTimeout(checkForUpdates, 8000);
});

app.on('window-all-closed', () => app.quit());
app.on('will-quit', () => {
  if (server && !server.killed) server.kill();
});
