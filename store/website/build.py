"""Builds index.html from site.html: inlines features.json (every feature, by area). Run: python3 store/website/build.py"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
s = open(os.path.join(HERE, 'site.html')).read()
for key, f in (('FEATURES', 'features.json'),):
    data = json.dumps(json.load(open(os.path.join(HERE, f))), ensure_ascii=False).replace('</', '<\\/')
    s = s.replace(f'/*{key}*/null', data)
open(os.path.join(HERE, 'index.html'), 'w').write(s)
print('index.html', len(s))

# The live site (GitHub Pages): the same page as a full document, with the images.
import shutil
dist = os.path.join(HERE, 'dist')
shutil.rmtree(dist, ignore_errors=True)
shutil.copytree(os.path.join(HERE, 'img'), os.path.join(dist, 'img'))
head = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<link rel="icon" type="image/png" href="img/icon.png">
<meta property="og:title" content="ChordPro Presenter">
<meta property="og:description" content="Your songbook for rehearsal and the stage: chord sheets, setlists, projection and band tools. Free for Android, Windows, macOS and Linux.">
<meta property="og:image" content="https://bramble-apps.github.io/chordpro-presenter/img/desk-tabs-1600.webp">
<meta property="og:url" content="https://bramble-apps.github.io/chordpro-presenter/">
<meta name="twitter:card" content="summary_large_image">
<style>:root{color-scheme:dark;box-sizing:border-box;padding-top:env(safe-area-inset-top,0px);padding-bottom:env(safe-area-inset-bottom,0px)}body{margin:0}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
"""
cut = s.index('<style>')
top, rest = s[:cut], s[cut:]  # (title, description and font links belong in the head)
top = top.replace('<meta name="claude:viewport-fit-sides" content="cover">\n', '')
page = head.replace('</head>', top + rest[:rest.index('</style>') + 8] + '\n</head>') + rest[rest.index('</style>') + 8:]
open(os.path.join(dist, 'index.html'), 'w').write(page + '\n</body>\n</html>\n')
open(os.path.join(dist, '.nojekyll'), 'w').write('')
print('dist/index.html')

# The Android beta page: https://bramble-apps.github.io/chordpro-presenter/beta/
os.makedirs(os.path.join(dist, 'beta'))
shutil.copy(os.path.join(HERE, 'beta.html'), os.path.join(dist, 'beta', 'index.html'))
print('dist/beta/index.html')
