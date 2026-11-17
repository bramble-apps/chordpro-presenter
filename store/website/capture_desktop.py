"""Desktop screenshots for the website: the web app at 1440 x 900 (2x) in headless Firefox, seeded
with the store's demo libraries, in dark mode. Needs the app on http://localhost:8096.
Run: python3 store/website/capture_desktop.py [shot ...]  (writes store/website/raw/*.png)"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
GP = os.path.join(os.path.dirname(HERE), 'google-play')
sys.path.insert(0, os.path.join(GP, 'capture'))
from mario import Firefox  # noqa: E402
from capture import SEED  # noqa: E402

URL = 'http://localhost:8096/'
RAW = os.path.join(HERE, 'raw')
W, H = 1440, 900


def seed(ff, shot, change=None):
    d = json.load(open(os.path.join(GP, 'demo', f'state_{shot}.json')))
    st = d['state']
    st['settings']['mode'] = 'dark'
    if change:
        change(st)
    assert ff.js_async(SEED, [st, d['selection']]) == 'ok'
    ff.go(URL)
    time.sleep(8)


def save(ff, name):
    ff.move(W - 4, H // 2)
    time.sleep(1.2)
    os.makedirs(RAW, exist_ok=True)
    ff.shot(os.path.join(RAW, name))
    print('saved', name)


def probe(ff):
    for s in ('chords', 'tabs', 'sheet', 'present', 'bilingual', 'format', 'editing', 'export'):
        seed(ff, s)
        save(ff, f'probe-{s}.png')


TB = 30  # toolbar row (CSS px)
EDIT, FORMAT, PRESENT = (1192, TB), (1276, TB), (1318, TB)


def gospel(on_keep):
    def change(st):
        for song in st['songs']:
            if song['title'] == 'Amazing Grace':
                song.setdefault('extra', {})['gospel'] = {'on': True, 'keep': on_keep}
    return change


def hero(ff):
    seed(ff, 'chords', gospel(False)); save(ff, 'd-gospel.png')


def chords(ff):
    seed(ff, 'chords'); save(ff, 'd-chords.png')


def tabs(ff):
    seed(ff, 'tabs'); save(ff, 'd-tabs.png')


def sheet(ff):
    seed(ff, 'sheet'); save(ff, 'd-sheet.png')


def notation(ff):
    seed(ff, 'export'); save(ff, 'd-notation.png')


def present(ff):
    seed(ff, 'present'); ff.click(*PRESENT); time.sleep(3); save(ff, 'd-present.png')


def format_(ff):
    seed(ff, 'format'); ff.click(*FORMAT); time.sleep(2.5); save(ff, 'd-format.png')


def editing(ff):
    seed(ff, 'editing'); ff.click(*EDIT); time.sleep(3); save(ff, 'd-editing.png')


def projector(ff):
    seed(ff, 'bilingual')
    ff.go(URL + '?view=projector'); time.sleep(8)
    save(ff, 'd-projector.png')


SHOTS = {'probe': probe, 'hero': hero, 'chords': chords, 'tabs': tabs, 'sheet': sheet,
         'notation': notation, 'present': present, 'format': format_, 'editing': editing,
         'projector': projector}
ALL = ['hero', 'chords', 'tabs', 'sheet', 'notation', 'present', 'format', 'editing', 'projector']

if __name__ == '__main__':
    names = sys.argv[1:] or ALL
    ff = Firefox(URL, width=W, height=H, dpr=2, port=2831)
    try:
        time.sleep(6)
        print(ff.js('return [innerWidth, innerHeight, devicePixelRatio]'))
        for n in names:
            SHOTS[n](ff)
    finally:
        ff.quit()
