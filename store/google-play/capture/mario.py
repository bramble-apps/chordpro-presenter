"""Tiny Marionette client: drives headless Firefox (no extra installs) to capture the web app at 3x.
Firefox is started with a throwaway profile beside this file (the snap can't use /tmp)."""
import base64, json, os, socket, subprocess, time, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE = os.path.join(HERE, 'ffprofile')


class Firefox:
    def __init__(self, url, width=450, height=960, dpr=3, port=2829):
        shutil.rmtree(PROFILE, ignore_errors=True)
        os.makedirs(PROFILE)
        with open(os.path.join(PROFILE, 'user.js'), 'w') as f:
            f.write(f'user_pref("layout.css.devPixelsPerPx", "{dpr}");\n'
                    f'user_pref("marionette.port", {port});\n'
                    'user_pref("browser.shell.checkDefaultBrowser", false);\n'
                    'user_pref("datareporting.policy.dataSubmissionEnabled", false);\n'
                    'user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);\n'
                    'user_pref("browser.aboutwelcome.enabled", false);\n'
                    'user_pref("webgl.force-enabled", true);\n'
                    'user_pref("ui.systemUsesDarkTheme", 0);\n')
        self.proc = subprocess.Popen(
            ['firefox', '--headless', '--no-remote', '--marionette', '--remote-allow-system-access', '--profile', PROFILE,
             f'--window-size={width},{height + 120}'],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            env={**os.environ, 'MOZ_REMOTE_ALLOW_SYSTEM_ACCESS': '1'})
        self.sock = None
        for _ in range(120):
            try:
                self.sock = socket.create_connection(('127.0.0.1', port), timeout=2)
                break
            except OSError:
                time.sleep(0.5)
        if not self.sock:
            raise RuntimeError('Firefox did not start')
        self.sock.settimeout(120)
        self._read()  # hello
        self.id = 0
        self.scale = 1.0  # pointer px per CSS px (page zoom)
        try:
            self.cmd('WebDriver:NewSession', {'capabilities': {}})
            self.go(url)
            self.fit(width, height)
        except Exception:
            self.quit()
            raise

    def _read(self):
        buf = b''
        while b':' not in buf:
            buf += self.sock.recv(1)
        n, rest = buf.split(b':', 1)
        n = int(n)
        while len(rest) < n:
            rest += self.sock.recv(n - len(rest))
        return json.loads(rest)

    def cmd(self, name, params=None):
        self.id += 1
        msg = json.dumps([0, self.id, name, params or {}])
        self.sock.sendall(f'{len(msg.encode())}:{msg}'.encode())
        while True:
            r = self._read()
            if r[1] == self.id:
                if r[2]:
                    raise RuntimeError(f'{name}: {r[2]}')
                return r[3]

    def js(self, script, args=()):
        return self.cmd('WebDriver:ExecuteScript', {'script': script, 'args': list(args)}).get('value')

    def js_async(self, script, args=()):
        return self.cmd('WebDriver:ExecuteAsyncScript', {'script': script, 'args': list(args)}).get('value')

    def fit(self, width, height):
        """Size the window so the page's viewport is exactly width x height (CSS px)."""
        for _ in range(4):
            iw, ih = self.js('return [window.innerWidth, window.innerHeight]')
            if (iw, ih) == (width, height):
                return
            r = self.cmd('WebDriver:GetWindowRect')
            self.cmd('WebDriver:SetWindowRect', {'width': r['width'] + width - iw, 'height': r['height'] + height - ih})
            time.sleep(0.5)

    def zoom(self, factor):
        """Full-page zoom (Firefox won't go narrower than 500 px; zooming gives a phone-width viewport)."""
        before = self.js('return window.innerWidth')
        self.cmd('Marionette:SetContext', {'value': 'chrome'})
        try:
            self.js('gBrowser.selectedBrowser.fullZoom = arguments[0];', [factor])
        finally:
            self.cmd('Marionette:SetContext', {'value': 'content'})
        time.sleep(1)
        after = self.js('return window.innerWidth')
        if after != before:
            self.scale = before / after

    def go(self, url):
        self.cmd('WebDriver:Navigate', {'url': url})

    # Pointer input is sent as DOM events at CSS coordinates: with page zoom on, WebDriver's own
    # pointer actions land scaled and can't reach the lower part of the page.
    _EV = """
    const [kind, x, y, dy] = arguments;
    const t = document.elementFromPoint(x, y) || document.querySelector('flutter-view') || document.body;
    const base = {clientX: x, clientY: y, screenX: x, screenY: y, bubbles: true, cancelable: true, composed: true, view: window};
    const p = (type, buttons) => t.dispatchEvent(new PointerEvent(type, {...base, pointerId: 1, pointerType: 'mouse', isPrimary: true, button: type === 'pointermove' ? -1 : 0, buttons}));
    if (kind === 'move') { p('pointermove', 0); }
    else if (kind === 'down') { p('pointermove', 0); p('pointerdown', 1); }
    else if (kind === 'up') { p('pointerup', 0); }
    else if (kind === 'wheel') { t.dispatchEvent(new WheelEvent('wheel', {...base, deltaX: 0, deltaY: dy, deltaMode: 0})); }
    """

    def click(self, x, y):
        self.js(self._EV, ['down', x, y, 0])
        time.sleep(0.08)
        self.js(self._EV, ['up', x, y, 0])

    def move(self, x, y):
        self.js(self._EV, ['move', x, y, 0])

    def wheel(self, x, y, dy):
        for _ in range(max(1, abs(int(dy)) // 60)):
            self.js(self._EV, ['wheel', x, y, 60 if dy > 0 else -60])
            time.sleep(0.03)

    def key(self, value):
        self.cmd('WebDriver:PerformActions', {'actions': [{'type': 'key', 'id': 'kbd', 'actions': [
            {'type': 'keyDown', 'value': value}, {'type': 'keyUp', 'value': value}]}]})
        self.cmd('WebDriver:ReleaseActions')

    def shot(self, path):
        data = self.cmd('WebDriver:TakeScreenshot', {'full': False})['value']
        with open(path, 'wb') as f:
            f.write(base64.b64decode(data))

    def new_tab(self):
        h = self.cmd('WebDriver:NewWindow', {'type': 'tab'})['handle']
        return h

    def handles(self):
        return self.cmd('WebDriver:GetWindowHandles')

    def switch(self, handle):
        self.cmd('WebDriver:SwitchToWindow', {'handle': handle, 'focus': True})

    def quit(self):
        try:
            self.cmd('Marionette:Quit', {'flags': ['eForceQuit']})
        except Exception:
            pass
        try:
            self.proc.wait(timeout=40)
        except Exception:
            try:
                self.proc.kill()
            except Exception:
                pass
        shutil.rmtree(PROFILE, ignore_errors=True)
