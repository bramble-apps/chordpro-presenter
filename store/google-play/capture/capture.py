"""Captures the app screens for the Play screenshots at 3x from headless Firefox.
Run: python3 capture/capture.py [shot ...]   (needs the web app on http://localhost:8096; writes raw/*.png)
Coordinates are CSS px in the 500 x 1083 viewport."""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mario import Firefox

ROOT = os.path.dirname(HERE)
RAW = os.path.join(ROOT, 'raw')
URL = 'http://localhost:8096/'
EDIT, ANNOTATE, FORMAT, PRESENT, PROJECT, MORE = (258, 47), (299, 47), (341, 47), (383, 47), (425, 47), (467, 47)

SEED = '''
const [state, selection, done] = arguments;
const r = indexedDB.open('bilingual_projector', 1);
r.onupgradeneeded = () => r.result.createObjectStore('kv');
r.onsuccess = () => {
  const tx = r.result.transaction('kv', 'readwrite'); const s = tx.objectStore('kv');
  s.put(JSON.stringify(state), 'bilingual_projector_state');
  s.put(JSON.stringify(selection), 'bilingual_projector_selection');
  tx.oncomplete = () => done('ok'); tx.onerror = () => done('error');
};
r.onerror = () => done('error');
'''


def seed(ff, shot, url=URL):
    d = json.load(open(os.path.join(ROOT, 'demo', f'state_{shot}.json')))
    assert ff.js_async(SEED, [d['state'], d['selection']]) == 'ok'
    ff.go(url)
    time.sleep(7)


def save(ff, name):
    ff.move(496, 600)
    time.sleep(1.2)
    ff.shot(os.path.join(RAW, name))
    print('saved', name)


def chords(ff):
    seed(ff, 'chords'); save(ff, '01-chords.png')


def editing(ff):
    seed(ff, 'editing'); ff.click(*EDIT); time.sleep(2.5); save(ff, '02-editing.png')


def format_(ff):
    seed(ff, 'format'); ff.click(*FORMAT); time.sleep(2)
    ff.wheel(350, 700, 400); time.sleep(1.5)
    save(ff, '03-format.png')


def present(ff):
    seed(ff, 'present'); ff.click(*PRESENT); time.sleep(2.5)
    ff.click(137, 690); time.sleep(1.5)
    save(ff, '04-present.png')


def tabs(ff):
    seed(ff, 'tabs'); save(ff, '05-tabs.png')


def sheet(ff):
    seed(ff, 'sheet'); save(ff, '06-sheet.png')


def export(ff):
    seed(ff, 'export'); ff.click(*MORE); time.sleep(1.2)
    ff.click(430, 93); time.sleep(6)
    time.sleep(4)
    save(ff, '08-export.png')


def bilingual(ff):
    seed(ff, 'bilingual')
    a = ff.cmd('WebDriver:GetWindowHandle')['value']
    b = ff.new_tab(); ff.switch(b); ff.go(URL + '?view=projector'); time.sleep(7)
    ff.switch(a); time.sleep(1)
    ff.click(468, 1056); time.sleep(1.2); ff.click(468, 1056); time.sleep(1.5)
    ff.switch(b)
    ff.fit(1280, 720); time.sleep(3)
    ff.shot(os.path.join(RAW, '07-tv.png'))
    # The operator tab keeps its phone size only while it isn't resized with the window:
    # open a second operator in a new phone-sized window instead.
    c = ff.cmd('WebDriver:NewWindow', {'type': 'window'})['handle']
    ff.switch(c); ff.go(URL); ff.fit(500, 1083); time.sleep(8)
    save(ff, '07-phone.png')
    ff.cmd('WebDriver:CloseWindow'); ff.switch(b)
    ff.cmd('WebDriver:CloseWindow'); ff.switch(a); return
    ff.switch(b); ff.cmd('WebDriver:CloseWindow'); ff.switch(a)


SHOTS = {'chords': chords, 'editing': editing, 'format': format_, 'present': present,
         'tabs': tabs, 'sheet': sheet, 'export': export, 'bilingual': bilingual}

if __name__ == '__main__':
    names = sys.argv[1:] or list(SHOTS)
    ff = Firefox(URL, width=500, height=1083)
    try:
        time.sleep(6)
        print(ff.js('return [innerWidth, innerHeight, devicePixelRatio]'))
        for n in names:
            SHOTS[n](ff)
    finally:
        ff.quit()
