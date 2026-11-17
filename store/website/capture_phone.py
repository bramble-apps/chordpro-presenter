"""Phone screens for the website that the store set doesn't have: the web app at 500 x 1083 (3x)
in headless Firefox, seeded with the store's demo libraries, in dark mode. Needs the app on
http://localhost:8096. Run: python3 store/website/capture_phone.py  (writes raw/p-*.png)"""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
GP = os.path.join(os.path.dirname(HERE), 'google-play')
sys.path.insert(0, os.path.join(GP, 'capture'))
from mario import Firefox  # noqa: E402
from capture import SEED  # noqa: E402
import capture_desktop as cd  # noqa: E402

if __name__ == '__main__':
    ff = Firefox(cd.URL, width=500, height=1083, dpr=3, port=2832)
    try:
        time.sleep(6)
        # It Is Well with My Soul, in Nashville numbers with solfège
        d = json.load(open(os.path.join(GP, 'demo', 'state_format.json')))
        st = d['state']
        st['settings']['mode'] = 'dark'
        st['selectedSongID'] = 's-well'
        assert ff.js_async(SEED, [st, {'song': 's-well', 'setlist': None, 'entry': None, 'slide': 0}]) == 'ok'
        ff.go(cd.URL); time.sleep(8)
        ff.move(496, 600); time.sleep(1.2)
        ff.shot(os.path.join(cd.RAW, 'p-notation.png')); print('saved p-notation.png')
    finally:
        ff.quit()
