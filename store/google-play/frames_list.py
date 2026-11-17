# Google Play screenshots, in order:
# (raw screen, headline, subline, unused, unused, TV image or None, style)
# style: angle (degrees, + = counter-clockwise), dx / dy (move the phone), w (phone screen width in px)
FRAMES = [
    ('05-tabs.png', 'Every song, stage-ready', 'Chord sheets, tabs, notes and setlists, ready for every rehearsal and service',
     None, None, None, {'angle': -6, 'dx': 25}),
    ('01-chords.png', 'Beautiful chord sheets', 'Guitar, ukulele and piano diagrams, strum patterns, colours and highlights',
     None, None, None, {'angle': 6, 'dx': -25}),
    ('02-editing.png', 'Write songs fast', 'Plain ChordPro text with highlighted chords and one-tap chord buttons',
     None, None, None, {}),
    ('03-format.png', 'Format it your way', 'Nashville numbers, solfège, Roman numerals, fonts and layouts',
     None, None, None, {'angle': -6, 'dx': 25}),
    ('04-present.png', 'Run the whole service', 'Live preview, slide tiles, blackout, and setlists with their own keys',
     None, None, None, {}),
    ('06-sheet.png', 'Sheet music built in', 'Engraved melodies with playback, plus piano chord charts',
     None, None, None, {'angle': 6, 'dx': -25}),
    ('07-phone.png', 'Bilingual projection', 'Project bilingual lyrics to a TV, projector or Chromecast',
     None, None, '07-tv.png', {'angle': -6, 'dx': 190, 'w': 520}),
    ('08-export.png', 'Share in any format', 'PDF, ChordPro, text, slides, PowerPoint, FreeShow and more',
     None, None, None, {}),
]
