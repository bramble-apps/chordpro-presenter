import sys, time, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mario import Firefox
ff = Firefox('http://localhost:8096/', width=500, height=1083)
try:
    ff.zoom(1.2)
    time.sleep(10)
    print(ff.js('return [innerWidth, innerHeight, devicePixelRatio]'))
    ff.shot(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'probe.png'))
finally:
    ff.quit()
