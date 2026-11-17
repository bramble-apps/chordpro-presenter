#!/usr/bin/env python3
"""Local server for ChordPro Presenter.

* Serves the built web app (build/web) to this computer and the network.
* Relays projector messages between every open screen (operator, projector
  windows, phones, TVs, Chromecasts) so they stay in sync from any browser:
    GET  /relay/ping           -> {"ok": true, "url": <projector link>, "cast": bool}
    GET  /relay/events?cid=ID  -> Server-Sent Events stream of messages
    POST /relay/send           -> body is one JSON message; sent to all others
* Casts the projector to Chromecasts / Google TVs (needs pychromecast) by
  starting ChordPro Presenter's own Cast receiver (app 7EAC743B, the page at
  https://chordpro-presenter.web.app, source in cast_receiver/) and telling
  it to open the projector page served here:
    GET  /cast/devices         -> [{"id", "name", "model", "casting"}]
    POST /cast/start {"id"}    /  POST /cast/stop {"id"}  /  POST /cast/stopall
* Edit from another device on the same Wi-Fi: http://chordpro.local:8080/edit
  (this computer is advertised as chordpro.local; port 80 instead of 8080
  when the system allows it). The page edits this app's library live:
    GET  /edit                 -> the app in editing mode (?view=edit)
* Backups and sync (this computer only, not other devices):
    GET  /backup/folder?path=P -> {"path", "ok", "error"}: can backups go there
    POST /backup/save?path=P&name=N&keep=K  (body: the zip) -> {"ok", "file"}
    POST /dav  {"method", "url", "headers", "body"(base64)}
                               -> {"status", "headers", "body"(base64)}: a
                                  WebDAV request passed on (browsers can't
                                  reach WebDAV services themselves)
* Passes pictures from other sites through (YouTube's stills, picture
  links), so the app draws them itself:
    GET  /image?url=URL        -> the picture (pictures only)
* Fetches song pages for "Find songs online" (only the sites in
  SONG_SITES), so the browser isn't blocked by cross-site rules:
    GET  /fetch?url=URL        -> the page (or 403 for other sites)
* Web API: control the open app from anything that can open a link or
  send a request (Stream Deck / Bitfocus Companion, a phone's browser, a
  script). GET or POST, answers JSON, any origin may call it:
    /api/status                     -> {song, slide, slides, blackout, text}
    /api/next  /api/previous  /api/first  /api/last
    /api/slide/N                    -> slide N (from 1)
    /api/next-song  /api/previous-song
    /api/song?title=Amazing%20Grace -> opens the song with that title
    /api/blackout[?on=true|false]   -> toggles, or sets
  /api on its own shows this list.
* Band Sync (JustChords PlayTogether) for the web / Linux app: leads or
  follows sessions on the local network (see the BandSync class).
* Searches Worship Leader's free song database (downloaded per language,
  refreshed weekly, kept in .songdb/):
    GET  /songdb/search?q=TEXT&langs=en,fr -> [{lang, id, title, author}]
    GET  /songdb/song?lang=en&id=N         -> {title, author, lyrics, ...}

Run:  tools/.venv/bin/python tools/serve.py [--port 8080]
"""

import argparse
import json
import os
import queue
import re
import socket
import subprocess
import tempfile
import threading
import time
import uuid
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen

# Song sites the app may search and import from: only ones whose
# robots.txt allows it. Others are opened in the browser instead.
SONG_SITES = {
    "www.chordie.com",
    "chordie.com",
    "www.ultimate-guitar.com",
    "tabs.ultimate-guitar.com",
    "www.chords-and-tabs.net",
    "solr.sscdn.co",  # Cifra Club's search
    "www.worshiptogether.com",
}
FETCH_UA = "ChordProPresenter/1.0 (song import; personal use)"
_fetch_cache: dict = {}  # url -> (time, status, type, bytes)
_fetch_last: dict = {}  # host -> time of the last request
_fetch_lock = threading.Lock()


def fetch_song_page(url: str):
    """(status, content type, body) for an allowed song site: cached for
    ten minutes, at most one request a second per site."""
    host = urlparse(url).hostname or ""
    if urlparse(url).scheme != "https" or host not in SONG_SITES:
        return 403, "text/plain", b"Not an allowed song site"
    now = time.time()
    hit = _fetch_cache.get(url)
    if hit and now - hit[0] < 600:
        return hit[1], hit[2], hit[3]
    with _fetch_lock:
        wait = 1.0 - (time.time() - _fetch_last.get(host, 0))
        if wait > 0:
            time.sleep(wait)
        _fetch_last[host] = time.time()
    try:
        with urlopen(Request(url, headers={"User-Agent": FETCH_UA}), timeout=15) as r:
            body = r.read()
            result = (r.status, r.headers.get("Content-Type", "text/html"), body)
    except Exception as e:  # noqa: BLE001
        code = getattr(e, "code", 502)
        return code, "text/plain", str(e).encode()
    _fetch_cache[url] = (time.time(), *result)
    if len(_fetch_cache) > 200:
        _fetch_cache.pop(next(iter(_fetch_cache)))
    return result


_image_cache: dict = {}  # url -> (type, bytes)


def fetch_image(url: str):
    """(status, content type, body) of a picture on another site (YouTube's
    stills, picture links in the media library), so the app can draw it
    itself (browsers block reading other sites' pictures otherwise).
    Pictures only, up to 20 MB."""
    if urlparse(url).scheme not in ("http", "https"):
        return 400, "text/plain", b"Not a web address"
    hit = _image_cache.get(url)
    if hit:
        return 200, hit[0], hit[1]
    try:
        with urlopen(Request(url, headers={"User-Agent": FETCH_UA}), timeout=15) as r:
            ctype = r.headers.get("Content-Type", "")
            if not ctype.startswith("image/"):
                return 415, "text/plain", b"Not a picture"
            body = r.read(20 * 1024 * 1024 + 1)
            if len(body) > 20 * 1024 * 1024:
                return 413, "text/plain", b"Too big"
    except Exception as e:  # noqa: BLE001
        return getattr(e, "code", 502), "text/plain", str(e).encode()
    _image_cache[url] = (ctype, body)
    if len(_image_cache) > 300:
        _image_cache.pop(next(iter(_image_cache)))
    return 200, ctype, body


HERE = os.path.dirname(os.path.abspath(__file__))
SONGDB = os.path.join(HERE, "..", ".songdb")
_songdb_lock = threading.Lock()


def songdb_path(lang: str) -> str:
    """The Worship Leader database for [lang], downloaded if missing or
    older than a week (their own free download, updated daily)."""
    import sqlite3  # noqa: F401  (checked here so a missing module fails early)

    if not re.fullmatch(r"[A-Za-z]{2,3}(-[A-Za-z]{2,3})?", lang):
        raise ValueError("bad language")
    path = os.path.join(SONGDB, f"{lang}.sqlite")
    with _songdb_lock:
        fresh = os.path.exists(path) and time.time() - os.path.getmtime(path) < 7 * 86400
        if not fresh:
            os.makedirs(SONGDB, exist_ok=True)
            url = f"https://worshipleaderapp.com/download/openlp3/{lang}.sqlite"
            try:
                with urlopen(Request(url, headers={"User-Agent": FETCH_UA}), timeout=60) as r:
                    data = r.read()
                tmp = path + ".part"
                with open(tmp, "wb") as f:
                    f.write(data)
                os.replace(tmp, path)
            except Exception:  # noqa: BLE001
                if not os.path.exists(path):
                    raise
    return path


def songdb_search(q: str, langs: list) -> list:
    import sqlite3

    out = []
    like = "%" + q.strip().lower().replace("%", "") + "%"
    for lang in langs[:4]:
        con = sqlite3.connect(songdb_path(lang))
        try:
            rows = con.execute(
                "select s.id, s.title, group_concat(a.display_name, ', ') "
                "from songs s left join authors_songs x on x.song_id = s.id "
                "left join authors a on a.id = x.author_id "
                "where (s.search_title like ? or lower(s.title) like ?) "
                "and length(s.lyrics) > 80 group by s.id "
                "order by (lower(s.title) like ?) desc, length(s.title) limit 30",
                (like, like, q.strip().lower() + "%"),
            ).fetchall()
        finally:
            con.close()
        out += [{"lang": lang, "id": r[0], "title": r[1], "author": r[2] or ""} for r in rows]
    return out


def songdb_song(lang: str, sid: int) -> dict:
    import sqlite3

    con = sqlite3.connect(songdb_path(lang))
    try:
        r = con.execute(
            "select title, lyrics, verse_order, copyright, ccli_number from songs where id = ?",
            (sid,),
        ).fetchone()
        authors = [
            a[0]
            for a in con.execute(
                "select a.display_name from authors a join authors_songs x "
                "on a.id = x.author_id where x.song_id = ?",
                (sid,),
            )
        ]
    finally:
        con.close()
    if not r:
        raise KeyError(sid)
    return {
        "title": r[0],
        "lyrics": r[1],
        "verseOrder": r[2] or "",
        "copyright": r[3] or "",
        "ccli": r[4] or "",
        "author": ", ".join(authors),
    }


ROOT = os.path.join(HERE, "..", "build", "web")
# Uploaded backgrounds / logos / videos (also served to TVs and Chromecasts).
MEDIA = os.path.join(HERE, "..", ".media")

try:  # Chromecast support is optional.
    import pychromecast
    from pychromecast.controllers import BaseController
except ImportError:  # pragma: no cover
    pychromecast = None
    BaseController = object


def lan_ip() -> str:
    """This computer's address on the local network."""
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))
        return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"
    finally:
        s.close()


# ---- Backups and sync ----

BACKUP_FOLDER_NAME = "ChordPro Presenter Backups"


def default_backup_folder() -> str:
    """In Drime when it's mounted (so backups go online), else Documents."""
    home = os.path.expanduser("~")
    for base in ("Drime", "Dropbox", "Nextcloud", "Documents"):
        if os.path.isdir(os.path.join(home, base)):
            return os.path.join(home, base, BACKUP_FOLDER_NAME)
    return os.path.join(home, BACKUP_FOLDER_NAME)


def backup_folder(path: str) -> str:
    path = os.path.expanduser(path.strip()) if path.strip() else default_backup_folder()
    return os.path.abspath(path)


def check_backup_folder(path: str) -> dict:
    """Whether backups can go to [path] (nothing is made: the folder is
    made by the first backup)."""
    folder = backup_folder(path)
    existing = folder
    while not os.path.isdir(existing):
        parent = os.path.dirname(existing)
        if parent == existing:
            break
        existing = parent
    if os.access(existing, os.W_OK):
        return {"path": folder, "ok": True}
    return {"path": folder, "ok": False, "error": f"Can't write in {existing}"}


def save_backup(path: str, name: str, keep: int, data: bytes) -> dict:
    """Writes backup [name] into the folder; keeps the [keep] newest."""
    folder = backup_folder(path)
    name = re.sub(r'[\\/:*?"<>|]+', "_", name) or "backup.zip"
    os.makedirs(folder, exist_ok=True)
    target = os.path.join(folder, name)
    tmp = target + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, target)
    ours = sorted(
        (f for f in os.listdir(folder) if f.startswith("ChordPro Presenter ") and f.endswith(".zip")),
        key=lambda f: os.path.getmtime(os.path.join(folder, f)),
        reverse=True,
    )
    for old in ours[max(1, keep):]:
        try:
            os.remove(os.path.join(folder, old))
        except OSError:
            pass
    return {"ok": True, "file": target}


def dav_request(req: dict) -> dict:
    """Passes one WebDAV request on and returns its answer."""
    import base64
    from urllib.error import HTTPError

    url = req.get("url", "")
    if urlparse(url).scheme not in ("http", "https"):
        return {"status": 400, "headers": {}, "body": ""}
    body = base64.b64decode(req.get("body") or "")
    r = Request(url, data=body if body else None, method=req.get("method", "GET"))
    for k, v in (req.get("headers") or {}).items():
        r.add_header(k, v)
    if body and "Content-Type" not in (req.get("headers") or {}):
        r.add_header("Content-Type", "application/octet-stream")
    try:
        with urlopen(r, timeout=60) as resp:
            data = resp.read()
            status, headers = resp.status, dict(resp.headers.items())
    except HTTPError as e:
        data = e.read() or b""
        status, headers = e.code, dict(e.headers.items()) if e.headers else {}
    except Exception as e:  # noqa: BLE001 - no connection, bad address…
        return {"status": 0, "headers": {}, "body": "", "error": str(e)}
    return {
        "status": status,
        "headers": {k.lower(): v for k, v in headers.items()},
        "body": base64.b64encode(data).decode(),
    }


# ---- Edit from another device ----------------------------------------------

# The port the short address uses (80 or 8080 when free, else the main one).
EDIT_PORT: int | None = None
EDIT_HOST = "chordpro.local"


def start_edit_listener(main_port: int) -> None:
    """Listens on an easy port too (80, else 8080) for the edit address."""
    global EDIT_PORT
    for port in (80, 8080):
        if port == main_port:
            EDIT_PORT = port
            return
        try:
            extra = ThreadingHTTPServer(("0.0.0.0", port), Handler)
        except OSError:
            continue  # taken, or not allowed (ports under 1024)
        extra.daemon_threads = True
        threading.Thread(target=extra.serve_forever, daemon=True).start()
        EDIT_PORT = port
        return
    EDIT_PORT = main_port


def advertise_host(port: int) -> None:
    """Makes this computer reachable as chordpro.local on the network
    (mDNS: iPhones, Macs, Windows, Linux and most Android browsers)."""

    def run() -> None:
        try:
            from zeroconf import ServiceInfo, Zeroconf
        except ImportError:
            return
        ip = lan_ip()
        if ip.startswith("127."):
            return
        try:
            info = ServiceInfo(
                "_http._tcp.local.",
                "ChordPro Presenter._http._tcp.local.",
                addresses=[socket.inet_aton(ip)],
                port=port,
                server=EDIT_HOST + ".",
                properties={"path": "/edit"},
            )
            Zeroconf().register_service(info, allow_name_change=True)
        except Exception as e:  # noqa: BLE001 - the IP address still works
            print("Could not advertise chordpro.local:", e)

    threading.Thread(target=run, daemon=True).start()


def edit_urls() -> dict:
    port = EDIT_PORT or 8080
    suffix = "" if port == 80 else f":{port}"
    return {
        "edit": f"http://{EDIT_HOST}{suffix}/edit",
        "editIp": f"http://{lan_ip()}{suffix}/edit",
    }


def build_id() -> str:
    """Changes whenever the app is rebuilt (flutter build web)."""
    try:
        return str(int(os.path.getmtime(os.path.join(ROOT, "main.dart.js"))))
    except OSError:
        return "0"


# ---- Relay -----------------------------------------------------------------

clients: dict[str, queue.Queue] = {}
clients_lock = threading.Lock()


def broadcast(message: str, sender: str | None) -> None:
    with clients_lock:
        targets = [q for cid, q in clients.items() if cid != sender]
    for q in targets:
        q.put(message)


# ---- Web API ---------------------------------------------------------------

# What the app last told the projectors (for /api/status).
app_state: dict = {}
app_state_lock = threading.Lock()

API_ACTIONS = {"next", "previous", "first", "last", "next-song", "previous-song"}


def note_state(message: str) -> None:
    """Keeps what /api/status reports from the app's own messages."""
    if '"type":"state"' not in message and '"type":"index"' not in message:
        return
    try:
        m = json.loads(message)
    except ValueError:
        return
    with app_state_lock:
        if m.get("type") == "state":
            stage = m.get("stage") or {}
            song = stage.get("song") or {}
            app_state.update(
                slides=m.get("slides") or [],
                index=m.get("index", 0),
                blackout=bool(m.get("blackout")),
                song=song.get("title") or "",
            )
        elif m.get("type") == "index":
            app_state["index"] = m.get("index", 0)


def api_status() -> dict:
    with app_state_lock:
        slides = app_state.get("slides") or []
        i = app_state.get("index", 0)
        text = slides[i] if 0 <= i < len(slides) else ""
        # The blank and title slides start with an invisible mark.
        if text.startswith("\u2063"):
            text = "" if text == "\u2063blank" else " / ".join(text.split("\n")[1:3]).strip(" /")
        return {
            "ok": bool(app_state),
            "song": app_state.get("song", ""),
            "slide": i + 1 if slides else 0,
            "slides": len(slides),
            "blackout": app_state.get("blackout", False),
            "text": text.replace("\u2029", "\n"),
        }


def api_call(path: str, query: dict) -> tuple[int, dict]:
    """Runs /api/... : tells the open app what to do."""
    parts = [p for p in path.split("/") if p][1:]
    if not parts:
        return 200, {
            "actions": [
                "/api/status", "/api/next", "/api/previous", "/api/first", "/api/last",
                "/api/slide/N", "/api/next-song", "/api/previous-song",
                "/api/song?title=…", "/api/blackout?on=true|false",
            ]
        }
    action = parts[0].lower()
    if action == "status":
        return 200, api_status()
    value = None
    if action == "slide":
        raw = parts[1] if len(parts) > 1 else query.get("n", [""])[0]
        if not raw.isdigit():
            return 400, {"error": "Give the slide number: /api/slide/3"}
        value = int(raw)
    elif action == "song":
        value = (query.get("title") or query.get("q") or [""])[0].strip()
        if not value:
            return 400, {"error": "Give the title: /api/song?title=Amazing%20Grace"}
    elif action == "blackout":
        value = (query.get("on") or ["toggle"])[0]
    elif action not in API_ACTIONS:
        return 404, {"error": f"No action '{action}'. See /api for the list."}
    with clients_lock:
        listening = bool(clients)
    if not listening:
        return 503, {"error": "ChordPro Presenter isn't open."}
    broadcast(json.dumps({"type": "remote", "action": action, "value": value}), None)
    return 200, {"ok": True, "action": action}


# ---- Chromecast ------------------------------------------------------------


# ChordPro Presenter's Cast receiver (registered in the Google Cast console).
RECEIVER_APP = "7EAC743B"
RECEIVER_NS = "urn:x-cast:com.chordpropresenter.slides"
# Shown by older versions of this server (DashCast); still recognised so
# "Stop" works on a TV that was started with it.
DASHCAST_APP = "84912283"


class PresenterController(BaseController):
    """Talks to ChordPro Presenter's receiver on the TV."""

    def __init__(self) -> None:
        super().__init__(RECEIVER_NS, RECEIVER_APP)

    def receive_message(self, _message, _data) -> bool:
        return True

    def start(self, timeout: float = 25) -> None:
        """Starts the receiver on the TV (if it isn't running) and waits."""
        done = threading.Event()
        errors: list[str] = []

        def launched(ok=True, *_args) -> None:
            if ok is False:
                errors.append("the TV did not start ChordPro Presenter")
            done.set()

        self.launch(callback_function=launched)
        if not done.wait(timeout):
            raise RuntimeError("the TV did not start ChordPro Presenter in time")
        if errors:
            raise RuntimeError(errors[0])

    def open(self, url: str, timeout: float = 20) -> None:
        """Starts the receiver if needed, then has it show [url]."""
        done = threading.Event()
        errors: list[str] = []

        def launched(ok=True, *_args) -> None:
            if ok is False:
                errors.append("the TV did not start ChordPro Presenter")
            else:
                try:
                    self.send_message({"type": "open", "url": url})
                except Exception as e:  # noqa: BLE001
                    errors.append(f"could not send the address: {e}")
            done.set()

        self.launch(callback_function=launched)
        if not done.wait(timeout):
            raise RuntimeError("the TV did not start ChordPro Presenter in time")
        if errors:
            raise RuntimeError(errors[0])


class Casts:
    """Finds Chromecasts and opens the projector page on them."""

    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.devices: dict[str, object] = {}
        # TVs showing pictures sent by the app (id -> its receiver link).
        self.active: dict[str, PresenterController] = {}
        self.browser = None
        self.scanned = 0.0

    @staticmethod
    def is_casting(cast) -> bool:
        """Whether the device is showing our projector (judged from what it
        is actually running, so it also works after this server restarts)."""
        status = getattr(cast, "status", None)
        return bool(status and status.app_id in (RECEIVER_APP, DASHCAST_APP))

    def scan(self) -> list[dict]:
        with self.lock:
            if pychromecast is None:
                return []
            if time.time() - self.scanned > 30 or not self.devices:
                if self.browser is not None:
                    self.browser.stop_discovery()
                found, self.browser = pychromecast.get_chromecasts(timeout=6)
                self.devices = {str(c.uuid): c for c in found}
                self.scanned = time.time()
            # Wait (in parallel) for each device to say what it is running.
            waits = [
                threading.Thread(target=c.wait, kwargs={"timeout": 4}, daemon=True)
                for c in self.devices.values()
                if c.status is None
            ]
            for t in waits:
                t.start()
            for t in waits:
                t.join(5)
            return [
                {
                    "id": cid,
                    "name": c.cast_info.friendly_name,
                    "model": c.cast_info.model_name,
                    "audioOnly": c.cast_info.cast_type == "audio",
                    "casting": self.is_casting(c),
                }
                for cid, c in sorted(
                    self.devices.items(), key=lambda kv: kv[1].cast_info.friendly_name
                )
            ]

    def start(self, cid: str, url: str) -> None:
        cast = self.devices[cid]
        cast.wait(timeout=10)
        presenter = PresenterController()
        cast.register_handler(presenter)
        presenter.open(url)
        self.active[cid] = presenter

    def send(self, message: dict) -> int:
        """Sends a message to every TV being cast to; returns how many."""
        sent = 0
        for cid, presenter in list(self.active.items()):
            try:
                presenter.send_message(message)
                sent += 1
            except Exception:  # noqa: BLE001 - that TV went away
                self.active.pop(cid, None)
        return sent

    def stop(self, cid: str) -> None:
        self.active.pop(cid, None)
        cast = self.devices[cid]
        cast.wait(timeout=10)
        cast.quit_app()

    def stop_all(self) -> list[str]:
        """Stops the projector on every device showing it."""
        self.scan()
        stopped = []
        self.active.clear()
        for cid, cast in list(self.devices.items()):
            try:
                if self.is_casting(cast):
                    cast.quit_app()
                    stopped.append(cast.cast_info.friendly_name)
            except Exception:  # noqa: BLE001 - one offline TV shouldn't stop the rest
                pass
        return stopped


casts = Casts()


# ---- HTTP ------------------------------------------------------------------


# ---------------------------------------------------------------------------
# Band Sync: JustChords PlayTogether for the web / Linux app (a browser can't
# advertise on Bonjour or open TCP sockets, so this server does it).
# Wire format: 4-byte big-endian length + UTF-8 JSON, both ways.
#   POST /bandsync/scan | /bandsync/stopscan
#   POST /bandsync/lead {"nickname", "setlistData"} -> {"ok", "port"}
#   POST /bandsync/send {"message"}       (to every follower)
#   POST /bandsync/stoplead
#   POST /bandsync/join {"host", "port", "nickname"} | /bandsync/leave
#   GET  /bandsync/events?after=N         -> {"seq", "events": [...]}
#        (long poll; events: {"kind": "sessions" | "followers" | "message" |
#         "connected", ...})
# ---------------------------------------------------------------------------

BAND_SERVICE = "_jcremote._tcp.local."

try:
    import struct

    from zeroconf import ServiceBrowser, ServiceInfo, ServiceStateChange, Zeroconf
except ImportError:  # pragma: no cover
    Zeroconf = None


def band_frame(obj) -> bytes:
    body = json.dumps(obj, separators=(",", ":"), ensure_ascii=False).encode()
    return struct.pack(">I", len(body)) + body


def band_read(sock, on_message) -> None:
    """Reads framed messages from [sock] until it closes."""
    buf = b""
    while True:
        try:
            data = sock.recv(65536)
        except OSError:
            data = b""
        if not data:
            return
        buf += data
        while len(buf) >= 4:
            n = struct.unpack(">I", buf[:4])[0]
            if len(buf) < 4 + n:
                break
            try:
                m = json.loads(buf[4 : 4 + n])
            except ValueError:
                m = None
            buf = buf[4 + n :]
            if isinstance(m, dict):
                on_message(m)


class BandSync:
    def __init__(self) -> None:
        self.cond = threading.Condition()
        self.seq = 0
        self.events: list = []
        self.zc = None
        self.browser = None
        self.found: dict = {}
        # Leading
        self.server = None
        self.info = None
        self.setlist = {}
        self.followers: dict = {}  # socket -> nickname
        self.flock = threading.Lock()
        # Following
        self.sock = None
        self.last_command = None

    # ---- events for the page ----
    def emit(self, event: dict) -> None:
        with self.cond:
            self.seq += 1
            event["seq"] = self.seq
            self.events.append(event)
            del self.events[:-500]
            self.cond.notify_all()

    def poll(self, after: int, wait: float = 15.0) -> dict:
        deadline = time.time() + wait
        with self.cond:
            while self.seq <= after and time.time() < deadline:
                self.cond.wait(deadline - time.time())
            return {"seq": self.seq, "events": [e for e in self.events if e["seq"] > after]}

    def _zeroconf(self):
        if Zeroconf is None:
            raise RuntimeError("Band Sync needs the zeroconf package")
        if self.zc is None:
            self.zc = Zeroconf()
        return self.zc

    # ---- discovery ----
    def scan(self) -> None:
        zc = self._zeroconf()
        if self.browser is not None:
            self.browser.cancel()
        self.found = {}
        self.emit({"kind": "sessions", "sessions": []})

        def changed(zeroconf, service_type, name, state_change):
            key = name.replace("." + BAND_SERVICE, "")
            if state_change is ServiceStateChange.Removed:
                self.found.pop(key, None)
            else:
                info = zeroconf.get_service_info(service_type, name, 3000)
                if not info or not info.parsed_addresses():
                    return
                props = {
                    (k.decode() if isinstance(k, bytes) else k): (v.decode() if isinstance(v, bytes) else v)
                    for k, v in (info.properties or {}).items()
                }
                addrs = info.parsed_addresses()
                host = next((a for a in addrs if ":" not in a), addrs[0])
                self.found[key] = {
                    "leader": key,
                    "title": props.get("playlist") or "",
                    "host": host,
                    "port": info.port,
                }
            self.emit({"kind": "sessions", "sessions": list(self.found.values())})

        self.browser = ServiceBrowser(zc, BAND_SERVICE, handlers=[changed])

    def stop_scan(self) -> None:
        if self.browser is not None:
            self.browser.cancel()
            self.browser = None

    # ---- leading ----
    def lead(self, nickname: str, setlist: dict) -> int:
        self.stop_lead()
        self.setlist = setlist
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", 0))
        srv.listen()
        self.server = srv
        port = srv.getsockname()[1]
        threading.Thread(target=self._accept, args=(srv,), daemon=True).start()
        threading.Thread(target=self._pinger, args=(srv,), daemon=True).start()
        try:
            name = re.sub(r"[.\x00-\x1f]", " ", nickname).strip() or "ChordPro Presenter"
            self.info = ServiceInfo(
                BAND_SERVICE,
                f"{name}.{BAND_SERVICE}",
                addresses=[socket.inet_aton(lan_ip())],
                port=port,
                properties={"playlist": str(setlist.get("title") or "")},
            )
            self._zeroconf().register_service(self.info, allow_name_change=True)
        except Exception as e:  # noqa: BLE001 - followers can still join by address
            print("Band Sync: could not advertise:", e)
            self.info = None
        return port

    def _accept(self, srv) -> None:
        while self.server is srv:
            try:
                c, _ = srv.accept()
            except OSError:
                return
            with self.flock:
                self.followers[c] = ""
            try:
                c.sendall(band_frame({"type": "setlistData", "setlistData": self.setlist}))
            except OSError:
                self._drop(c)
                continue
            threading.Thread(target=self._follower, args=(c,), daemon=True).start()

    def _follower(self, c) -> None:
        def got(m):
            if m.get("type") == "nickname":
                with self.flock:
                    self.followers[c] = str(m.get("nickname") or "")
                self._followers_changed()

        band_read(c, got)
        self._drop(c)

    def _drop(self, c) -> None:
        with self.flock:
            gone = self.followers.pop(c, None) is not None
        try:
            c.close()
        except OSError:
            pass
        if gone:
            self._followers_changed()

    def _followers_changed(self) -> None:
        with self.flock:
            names = [n for n in self.followers.values() if n]
        self.emit({"kind": "followers", "followers": names})

    def _pinger(self, srv) -> None:
        while self.server is srv:
            time.sleep(5)
            if self.server is srv:
                self.send({"type": "ping"})

    def send(self, message: dict) -> None:
        if message.get("type") == "setlistData":
            self.setlist = message.get("setlistData") or {}
        frame = band_frame(message)
        with self.flock:
            socks = list(self.followers)
        for c in socks:
            try:
                c.sendall(frame)
            except OSError:
                self._drop(c)

    def stop_lead(self) -> None:
        srv = self.server
        if srv is None:
            return
        self.send({"type": "kick"})
        self.server = None
        with self.flock:
            socks = list(self.followers)
            self.followers.clear()
        for c in socks:
            try:
                c.close()
            except OSError:
                pass
        try:
            srv.close()
        except OSError:
            pass
        if self.info is not None and self.zc is not None:
            try:
                self.zc.unregister_service(self.info)
            except Exception:  # noqa: BLE001
                pass
            self.info = None
        self.emit({"kind": "followers", "followers": []})

    # ---- following ----
    def join(self, host: str, port: int, nickname: str) -> None:
        self.leave()
        s = socket.create_connection((host, int(port)), timeout=6)
        s.settimeout(None)
        self.sock = s
        self.last_command = None
        s.sendall(band_frame({"type": "nickname", "nickname": nickname}))
        self.emit({"kind": "connected", "value": True})
        threading.Thread(target=self._listen, args=(s,), daemon=True).start()

    def _listen(self, s) -> None:
        def got(m):
            if m.get("type") == "ping":
                try:
                    s.sendall(band_frame({"type": "pong"}))
                except OSError:
                    pass
                return
            if m.get("type") == "command":
                cid = (m.get("command") or {}).get("id")
                if cid is not None and cid == self.last_command:
                    return
                self.last_command = cid
            self.emit({"kind": "message", "message": m})

        band_read(s, got)
        if self.sock is s:
            self.sock = None
            self.emit({"kind": "connected", "value": False})

    def leave(self) -> None:
        s = self.sock
        self.sock = None
        if s is not None:
            try:
                s.close()
            except OSError:
                pass


bandsync = BandSync()


class Handler(SimpleHTTPRequestHandler):
    server_version = "ChordProPresenter/1"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def log_message(self, fmt, *args):  # quiet for the chatty relay
        if "/relay/" not in self.path:
            super().log_message(fmt, *args)

    def end_headers(self):
        # Always check for the latest build (no stale cached app). This
        # includes assets: the icon font is trimmed to the icons in use, so
        # an old cached copy shows new icons as blanks. Unchanged files
        # still come from the cache (304 Not Modified).
        if not self.path.startswith("/media/"):
            self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def _json(self, data, status=200, cors=False):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        if cors:
            self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> bytes:
        return self.rfile.read(int(self.headers.get("Content-Length") or 0))

    def projector_url(self) -> str:
        return f"http://{lan_ip()}:{self.server.server_address[1]}/?view=projector&net=1"

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/relay/ping":
            return self._json(
                {
                    "ok": True,
                    "url": self.projector_url(),
                    "cast": pychromecast is not None,
                    "build": build_id(),
                    **edit_urls(),
                }
            )
        if url.path == "/backup/folder":
            if not self._local():
                return self.send_error(403)
            return self._json(check_backup_folder(parse_qs(url.query).get("path", [""])[0]))
        if url.path in ("/edit", "/edit/"):
            # The short address: the app, editing this computer's library.
            self.send_response(302)
            self.send_header("Location", "/?view=edit")
            self.end_headers()
            return None
        if url.path == "/relay/events":
            return self.events(parse_qs(url.query).get("cid", ["?"])[0])
        if url.path == "/api" or url.path.startswith("/api/"):
            status, data = api_call(url.path, parse_qs(url.query))
            return self._json(data, status, cors=True)
        m = re.fullmatch(r"/media/([A-Za-z0-9_-]+)", url.path)
        if m:
            return self.serve_media(m.group(1))
        if url.path in ("/fetch", "/image"):
            target = parse_qs(url.query).get("url", [""])[0]
            status, ctype, body = (
                fetch_image(target)
                if url.path == "/image"
                else fetch_song_page(target)
            )
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return None
        if url.path in ("/songdb/search", "/songdb/song"):
            q = parse_qs(url.query)
            try:
                if url.path == "/songdb/search":
                    langs = [x for x in q.get("langs", ["en"])[0].split(",") if x]
                    return self._json(songdb_search(q.get("q", [""])[0], langs))
                return self._json(songdb_song(q.get("lang", ["en"])[0], int(q.get("id", ["0"])[0])))
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 502)
        if url.path == "/bandsync/events":
            q = parse_qs(url.query)
            after = int(q.get("after", ["0"])[0] or 0)
            wait = min(float(q.get("wait", ["15"])[0] or 15), 30.0)
            return self._json(bandsync.poll(after, wait))
        if url.path == "/cast/devices":
            try:
                return self._json(casts.scan())
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 500)
        return super().do_GET()

    def _local(self) -> bool:
        """From this computer (backups and sync aren't for other devices)."""
        return self.client_address[0] in ("127.0.0.1", "::1", "::ffff:127.0.0.1")

    def do_POST(self):
        url = urlparse(self.path)
        if url.path == "/backup/save":
            if not self._local():
                return self.send_error(403)
            q = parse_qs(url.query)
            try:
                return self._json(
                    save_backup(
                        q.get("path", [""])[0],
                        q.get("name", ["backup.zip"])[0],
                        int(q.get("keep", ["10"])[0]),
                        self._body(),
                    )
                )
            except OSError as e:
                return self._json({"ok": False, "error": e.strerror or str(e)}, 500)
        if url.path == "/dav":
            if not self._local():
                return self.send_error(403)
            return self._json(dav_request(json.loads(self._body() or b"{}")))
        if url.path == "/media/upload":
            return self.upload(parse_qs(url.query))
        if url.path == "/relay/send":
            message = self._body().decode()
            note_state(message)
            broadcast(message, self.headers.get("X-Client"))
            return self._json({"ok": True})
        if url.path == "/api" or url.path.startswith("/api/"):
            status, data = api_call(url.path, parse_qs(url.query))
            return self._json(data, status, cors=True)
        if url.path.startswith("/bandsync/"):
            try:
                body = json.loads(self._body() or b"{}")
                what = url.path[len("/bandsync/") :]
                if what == "scan":
                    bandsync.scan()
                elif what == "stopscan":
                    bandsync.stop_scan()
                elif what == "lead":
                    port = bandsync.lead(str(body.get("nickname") or ""), body.get("setlistData") or {})
                    return self._json({"ok": True, "port": port})
                elif what == "send":
                    bandsync.send(body["message"])
                elif what == "stoplead":
                    bandsync.stop_lead()
                elif what == "join":
                    bandsync.join(str(body["host"]), int(body["port"]), str(body.get("nickname") or ""))
                elif what == "leave":
                    bandsync.leave()
                else:
                    return self.send_error(404)
                return self._json({"ok": True})
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 500)
        if url.path == "/cast/stopall":
            try:
                return self._json({"stopped": casts.stop_all()})
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 500)
        if url.path == "/cast/send":
            try:
                message = json.loads(self._body() or b"{}")["message"]
                return self._json({"ok": casts.send(message) > 0})
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 500)
        if url.path in ("/cast/start", "/cast/stop"):
            try:
                cid = json.loads(self._body() or b"{}")["id"]
                if url.path == "/cast/start":
                    casts.start(cid, self.projector_url())
                else:
                    casts.stop(cid)
                return self._json({"ok": True})
            except Exception as e:  # noqa: BLE001
                return self._json({"error": str(e)}, 500)
        self.send_error(404)

    def upload(self, q) -> None:
        """Stores an uploaded picture/video. The browser sends the file
        straight from disk, which avoids browsers (Zen) that stall when a
        page reads a chosen file itself. HEIC photos become JPEG."""
        name = q.get("name", ["file"])[0]
        mime = q.get("type", ["application/octet-stream"])[0] or "application/octet-stream"
        data = self._body()
        os.makedirs(MEDIA, exist_ok=True)
        mid = "m" + uuid.uuid4().hex[:16]
        if mime in ("image/heic", "image/heif") or name.lower().endswith((".heic", ".heif")):
            with tempfile.TemporaryDirectory() as tmp:
                src = os.path.join(tmp, "in.heic")
                dst = os.path.join(tmp, "out.jpg")
                with open(src, "wb") as f:
                    f.write(data)
                r = subprocess.run(["sips", "-s", "format", "jpeg", src, "--out", dst],
                                   capture_output=True)
                if r.returncode == 0:
                    with open(dst, "rb") as f:
                        data = f.read()
                    mime = "image/jpeg"
                    name = re.sub(r"\.[^.]+$", "", name) + ".jpg"
        with open(os.path.join(MEDIA, mid), "wb") as f:
            f.write(data)
        with open(os.path.join(MEDIA, mid + ".json"), "w") as f:
            json.dump({"name": name, "mime": mime}, f)
        self._json({"id": mid, "name": name, "mime": mime, "size": len(data)})

    def serve_media(self, mid: str) -> None:
        path = os.path.join(MEDIA, mid)
        try:
            with open(path + ".json") as f:
                meta = json.load(f)
            size = os.path.getsize(path)
        except OSError:
            return self.send_error(404)
        self.send_response(200)
        self.send_header("Content-Type", meta["mime"])
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "max-age=31536000, immutable")
        self.end_headers()
        with open(path, "rb") as f:
            while chunk := f.read(1 << 20):
                self.wfile.write(chunk)

    def events(self, cid: str) -> None:
        """Server-Sent Events: one connection per open screen."""
        q: queue.Queue = queue.Queue()
        with clients_lock:
            clients[cid] = q
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("X-Accel-Buffering", "no")
        self.end_headers()
        build = build_id()
        try:
            self.wfile.write(b": connected\n\n")
            self.wfile.flush()
            while True:
                try:
                    msg = q.get(timeout=5)
                    self.wfile.write(f"data: {msg}\n\n".encode())
                except queue.Empty:
                    self.wfile.write(b": keep-alive\n\n")
                # A new build: tell this screen so it can load it.
                if build_id() != build:
                    build = build_id()
                    note = json.dumps({"type": "newBuild", "build": build})
                    self.wfile.write(f"data: {note}\n\n".encode())
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            with clients_lock:
                if clients.get(cid) is q:
                    del clients[cid]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8080)
    # The desktop app (Electron) runs this from inside its package: the web
    # app is elsewhere, and song databases / uploads go in its data folder.
    parser.add_argument("--root", help="folder with the built web app")
    parser.add_argument("--data", help="folder for .songdb and .media")
    parser.add_argument(
        "--exit-with-parent",
        action="store_true",
        help="stop when the app that started this stops (even if it crashed)",
    )
    args = parser.parse_args()
    if args.exit_with_parent:
        parent = os.getppid()

        def watch() -> None:
            while os.getppid() == parent:
                time.sleep(1)
            os._exit(0)

        threading.Thread(target=watch, daemon=True).start()
    global ROOT, MEDIA, SONGDB
    if args.root:
        ROOT = os.path.abspath(args.root)
    if args.data:
        os.makedirs(args.data, exist_ok=True)
        MEDIA = os.path.join(args.data, "media")
        SONGDB = os.path.join(args.data, "songdb")
    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.daemon_threads = True
    start_edit_listener(args.port)
    advertise_host(EDIT_PORT or args.port)
    print(f"ChordPro Presenter: http://localhost:{args.port}")
    print("Edit from another device:", edit_urls()["edit"], "or", edit_urls()["editIp"])
    print(f"Projector for other screens: http://{lan_ip()}:{args.port}/?view=projector&net=1")
    print("Chromecast:", "available" if pychromecast else "install pychromecast")
    server.serve_forever()


if __name__ == "__main__":
    main()
