"""Builds index.html from site.html: inlines features.json (every feature, by area). Run: python3 store/website/build.py"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
s = open(os.path.join(HERE, 'site.html')).read()
for key, f in (('FEATURES', 'features.json'),):
    data = json.dumps(json.load(open(os.path.join(HERE, f))), ensure_ascii=False).replace('</', '<\\/')
    s = s.replace(f'/*{key}*/null', data)
open(os.path.join(HERE, 'index.html'), 'w').write(s)
print('index.html', len(s))
