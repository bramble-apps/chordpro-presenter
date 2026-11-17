"""Looks at the dynamic wallpaper: projector frames for a few presets, and the Format → Projection pane."""
import json, os, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from mario import Firefox
from capture import SEED, URL, ROOT
OUT = os.path.join(HERE, 'wall')
os.makedirs(OUT, exist_ok=True)
d = json.load(open(os.path.join(ROOT, 'demo', 'state_wall.json')))
ff = Firefox(URL, width=1280, height=720, dpr=1)
try:
    op = ff.cmd('WebDriver:GetWindowHandle')['value']
    pj = None
    for preset in ('Nebula', 'Ocean Floor', 'Purple Vista', 'Lava Lamp'):
        if pj:
            ff.switch(pj); ff.cmd('WebDriver:CloseWindow'); ff.switch(op)
        d['state']['projection']['bgDynamic'] = {'preset': preset}
        assert ff.js_async(SEED, [d['state'], d['selection']]) == 'ok'
        ff.go(URL); time.sleep(8)
        pj = ff.new_tab(); ff.switch(pj); ff.go(URL + '?view=projector'); time.sleep(6)
        ff.switch(op); time.sleep(1)
        ff.click(640, 300); ff.key('\ue014'); time.sleep(1); ff.key('\ue014'); time.sleep(1)
        ff.switch(pj); time.sleep(4)
        ff.shot(os.path.join(OUT, preset.replace(' ', '_') + '-a.png')); time.sleep(2.5)
        ff.shot(os.path.join(OUT, preset.replace(' ', '_') + '-b.png'))
        ff.switch(op)
        print('shot', preset)
    if pj:
        ff.switch(pj); ff.cmd('WebDriver:CloseWindow'); ff.switch(op)
    ff.go(URL); time.sleep(7)
    ff.fit(1400, 900); time.sleep(2)
    ff.click(1232, 32); time.sleep(2)  # Format (brush) in the desktop toolbar
    ff.shot(os.path.join(OUT, 'format-desktop.png'))
finally:
    ff.quit()
