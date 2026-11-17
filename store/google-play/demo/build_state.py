"""Demo library for the Google Play screenshots: public-domain songs (hymns, traditional,
and popular songs whose writers died long ago) that show off the app's features.
Writes demo/state_<shot>.json: the app's saved state (IndexedDB 'bilingual_projector_state')
plus the selection, one per screenshot (different theme/settings each)."""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))

AMAZING_GRACE = """{title: Amazing Grace}
{artist: John Newton}
{key: G}

Verse 1:
{rhythm: D--D-U}
{comment_italic: Gently, with room to breathe}
A[G]mazing [G7]grace, how [C]sweet the [G]sound
That [G]saved a wretch like [D]me
I [G]once was [G7]lost, but [C]now am [G]found
<@yellow>Was [Em]blind, but [D]now I [G]see<

Verse 1 (FR):
Grâce é[G]tonnante, au [G7]son si [C]doux[G]
Qui sauva le [G]misérable que j'é[D]tais
J'étais per[G]du, mais [G7]je suis re[C]trou[G]vé
J'étais a[Em]veugle, mais main[D]tenant je [G]vois

Verse 2:
'Twas [G]grace that [G7]taught my [C]heart to [G]fear
And [G]grace my fears re[D]lieved
How [G]precious [G7]did that [C]grace ap[G]pear
The [Em]hour I [D]first be[G]lieved

Verse 2 (FR):
C'est la [G]grâce qui ap[G7]prit la crainte à mon [C]cœur[G]
Et la [G]grâce qui a[D]paisa mes peurs
Combien pré[G]cieuse [G7]cette grâce m'ap[C]pa[G]rut
À l'[Em]heure où j'ai [D]cru pour la première [G]fois

Verse 3:
When [G]we've been [G7]there ten [C]thousand [G]years
Bright [G]shining as the [D]sun
We've [G]no less [G7]days to [C]sing God's [G]praise
Than [Em]when we'd [D]first be[G]gun

Verse 3 (FR):
Quand nous se[G]rons là de[G7]puis dix [C]mille [G]ans
Bril[G]lants comme le so[D]leil
Nous n'aurons [G]pas moins de [G7]jours pour chanter la [C]louange de [G]Dieu
Qu'au [Em]tout pre[D]mier [G]jour
"""

SAINTS = """{title: When the Saints Go Marching In}
{artist: Traditional}
{key: C}
{rhythm: swing}

Intro:
{start_of_tab}
e|-----0-1-3-------------0-1-3-------|
B|---1-----------------1-------------|
G|-----------------------------------|
D|-----------------------------------|
A|-----------------------------------|
E|-----------------------------------|
{end_of_tab}

Verse 1:
Oh, when the [C]saints go marching in
Oh, when the saints go marching [G7]in
Oh, Lord, I [C]want to be [C7]in that [F]number
When the [C]saints go [G7]marching [C]in

Verse 2:
Oh, when the [C]sun refuse to shine
Oh, when the sun refuse to [G7]shine
Oh, Lord, I [C]want to be [C7]in that [F]number
When the [C]sun re[G7]fuse to [C]shine

Outro:
{comment: <orange>Tag the last line twice, then a *big* ending<}
When the [C]saints go [G7]marching [C]in [F] [C]
"""

DAISY = """{title: Daisy Bell}
{subtitle: A Bicycle Built for Two}
{artist: Harry Dacre, 1892}
{key: C}

Melody:
{start_of_abc}
X:1
T:Daisy Bell
M:3/4
L:1/4
K:C
"C"G3 | E3 | C3 | G,3 | "F"A, B, C | A,2 C | "C"G,3- | G,3 |
w: Dai-sy, Dai-sy, give me your an-swer, do_
"G7"D3 | G3 | "C"E3 | C3 | "Dm"A, B, C | "G"D2 E | D3- | D2 E |
w: I'm half cra-zy, all for the love of you_ It
"C"F E D | G2 E | "F"D C2- | C2 D | "C"E2 C | A,2 C | "G"A, G,2- | G,2 G, |
w: won't be a sty-lish mar-riage, I can't af-ford a car-riage, But
"C"C2 E | "G7"D2 G, | "C"C2 E | "G7"D E F | "C"G E C | "G7"D2 G, | "C"C3- | C3 |]
w: you'll look sweet up-on the seat of a bi-cy-cle built for two_
{end_of_abc}

Chorus:
[C]Daisy, Daisy, [F]give me your answer, [C]do
[G7]I'm half crazy, [C]all for the love of [G]you
It [G7]won't be a stylish [C]marriage
I [F]can't af[C]ford a [G]carriage
But you'll [G7]look [C]sweet up[G7]on the [C]seat
Of a [G7]bicycle built for [C]two
"""

AULD = """{title: Auld Lang Syne}
{artist: Robert Burns, 1788}
{key: F}
{tempo: 84}
{rhythm: D-DU-DU}
# Everyone links arms on the last chorus

Verse 1:
Should [F]auld acquaintance [C7]be forgot
And [F]never brought to [Bb]mind?
Should [F]auld acquaintance [C7]be forgot
And [Dm]days o' [Bb]auld [C7]lang [F]syne?

Chorus:
{comment: <orange>Everyone sings!<}
For [F]auld lang syne, my [C7]dear
For [F]auld lang [Bb]syne
We'll [F]tak a cup o' [C7]kindness yet
For *[Dm]days o' [Bb]auld [C7]lang [F]syne*

Verse 2:
We [F]twa hae run a[C7]bout the braes
And [F]pou'd the gowans [Bb]fine
But we've [F]wander'd mony a [C7]weary fit
Sin' [Dm]auld [Bb]lang [C7]syne[F]
"""

IT_IS_WELL = """{title: It Is Well with My Soul}
{artist: Horatio Spafford & Philip Bliss, 1876}
{key: C}

Verse 1:
When [C]peace like a [F]river at[C]tendeth my way
When [Am]sorrows like [D7]sea billows [G]roll
What[C]ever my [F]lot, Thou hast [C]taught me to [Am]say
It is [C]well, it is [G7]well with my [C]soul

Chorus:
It is [G]well (it is [C]well)
With my [G7]soul (with my [C]soul)
It is [F]well, it is [G7]well with my [C]soul
"""

BE_THOU = """{title: Be Thou My Vision}
{artist: Irish traditional, tr. Mary Byrne & Eleanor Hull}
{key: D}

Verse 1:
[D]Be Thou my [G]Vision, O [D]Lord of my [Bm]heart
[G]Naught be all [D]else to me, [Em]save that Thou [A]art
[D]Thou my best [G]thought, by [D]day or by [Bm]night
[G]Waking or [D]sleeping, Thy [A]presence my [D]light
"""

TAGS = [
    {'id': 't-hymn', 'name': 'Hymn', 'color': 'indigo'},
    {'id': 't-jazz', 'name': 'Jazz', 'color': 'orange'},
    {'id': 't-fr', 'name': 'Bilingual', 'color': 'teal'},
    {'id': 't-fun', 'name': 'Sing-along', 'color': 'pink'},
]

SONGS = [
    dict(id='s-grace', title='Amazing Grace', raw=AMAZING_GRACE, key='G', artist='John Newton',
         tempo='72', timeSignature='3/4', duration='3:30', copyright='Public domain',
         tags=['t-hymn', 't-fr'], extra={'icon': 'hymn'}),
    dict(id='s-saints', title='When the Saints Go Marching In', raw=SAINTS, key='C', artist='Traditional',
         tempo='120', timeSignature='4/4', duration='2:40', copyright='Public domain',
         tags=['t-jazz', 't-fun'], extra={
             'icon': 'bolt',
             'stickies': [
                 {'id': 'n1', 'text': 'Swing feel!\nPercussion joins on verse 2', 'x': 252, 'y': 372,
                  'w': 160, 'h': 104, 'colour': 0xFFFFF475, 'bold': True, 'size': 15, 'pinned': True},
                 {'id': 'n2', 'text': 'Drums: stop on beat 4 before the outro', 'x': 232, 'y': 610,
                  'w': 176, 'h': 74, 'colour': 0xFFB5EAD7, 'size': 14, 'pinned': True},
             ],
             'ink': [
                 {'id': 'k1', 'h': True, 'c': 0x88FFD54F, 'w': 0.035, 'p': [0.05, 1.262, 0.30, 1.260, 0.64, 1.264]},
                 {'id': 'k2', 'c': 0xFFE53935, 'w': 0.006, 'p': [0.502, 1.219, 0.4969, 1.2344, 0.4826, 1.2465, 0.4624, 1.2526, 0.4405, 1.2513, 0.4218, 1.243, 0.4103, 1.2295, 0.4086, 1.2137, 0.417, 1.199, 0.4337, 1.1887, 0.455, 1.185, 0.4763, 1.1887, 0.493, 1.199, 0.5014, 1.2137, 0.4997, 1.2295]},
             ]}),
    dict(id='s-daisy', title='Daisy Bell', raw=DAISY, key='C', artist='Harry Dacre, 1892',
         subtitle='A Bicycle Built for Two', tempo='168', timeSignature='3/4', duration='2:10',
         copyright='Public domain', tags=['t-fun'], extra={'icon': 'note'}),
    dict(id='s-auld', title='Auld Lang Syne', raw=AULD, key='F', artist='Robert Burns, 1788',
         tempo='84', timeSignature='4/4', duration='2:30', copyright='Public domain',
         tags=['t-fun'], extra={'icon': 'star'}),
    dict(id='s-well', title='It Is Well with My Soul', raw=IT_IS_WELL, key='C',
         artist='Horatio Spafford & Philip Bliss, 1876', tempo='76', timeSignature='4/4',
         copyright='Public domain', tags=['t-hymn'], extra={'icon': 'calm'}),
    dict(id='s-vision', title='Be Thou My Vision', raw=BE_THOU, key='D',
         artist='Irish traditional', tempo='84', timeSignature='3/4',
         copyright='Public domain', tags=['t-hymn'], extra={'icon': 'church'}),
]

SETLIST = {
    'id': 'l-sunday', 'name': 'Sunday Morning', 'setSpecific': True, 'eventDate': '2026-11-22T10:00:00.000',
    'entries': [
        {'id': 'e0', 'type': 'event', 'title': 'Welcome & announcements', 'color': 'teal'},
        {'id': 'e1', 'type': 'divider', 'title': 'Worship', 'color': 'indigo'},
        {'id': 'e2', 'type': 'song', 'songId': 's-vision'},
        {'id': 'e3', 'type': 'song', 'songId': 's-grace', 'transpose': -2},
        {'id': 'e4', 'type': 'song', 'songId': 's-well', 'capo': 2},
        {'id': 'e5', 'type': 'label', 'title': 'Offering', 'color': 'orange'},
        {'id': 'e6', 'type': 'divider', 'title': 'Kids & family', 'color': 'pink'},
        {'id': 'e7', 'type': 'song', 'songId': 's-saints'},
        {'id': 'e8', 'type': 'song', 'songId': 's-daisy'},
    ]}
SETLIST2 = {'id': 'l-ny', 'name': "New Year's Eve", 'setSpecific': True, 'entries': [
    {'id': 'j1', 'type': 'song', 'songId': 's-auld'},
    {'id': 'j2', 'type': 'song', 'songId': 's-saints'},
    {'id': 'j3', 'type': 'song', 'songId': 's-daisy'},
]}

BASE_SETTINGS = {'showChordDiagrams': False, 'chordInstrument': 'guitar', 'showDiagramFingers': True,
                 'showMetronome': True, 'showAutoscroll': True, 'showPads': True, 'showTuner': True,
                 'translateTo': 'fr'}

# shot name -> (song id, settings overrides, format overrides, projection overrides, setlist id)
SHOTS = {
    'chords':   ('s-grace', {'themeId': 'default', 'mode': 'light', 'showChordDiagrams': True},
                 {'styles': {'chords': {'bold': True, 'color': '#C64600'}, 'headings': {'highlightHex': '#FFE8A3', 'bold': True}}}, {}, None),
    'editing':  ('s-auld', {'themeId': 'ocean', 'mode': 'light'}, {}, {}, None),
    'format':   ('s-well', {'themeId': 'sunset', 'mode': 'light', 'themeMusic': True},
                 {'notation': 'numbers', 'dualNotation': 'solfege'}, {}, None),
    'present':  ('s-grace', {'themeId': 'midnight', 'mode': 'dark'}, {}, {}, 'l-sunday'),
    'tabs':     ('s-saints', {'themeId': 'forest', 'mode': 'dark', 'showChordDiagrams': True, 'chordInstrument': 'ukulele'},
                 {'tabsModern': True}, {}, None),
    'sheet':    ('s-daisy', {'themeId': 'rose', 'mode': 'light', 'showChordDiagrams': True, 'chordInstrument': 'piano'},
                 {}, {}, None),
    'bilingual': ('s-grace', {'themeId': 'teal', 'mode': 'dark'}, {'linked': {'show': True, 'italic': True, 'dim': True}},
                  {'linked': {'sideBySide': False, 'italic': True, 'dim': False, 'color': 0xFFC9CDD6},
                   'bgColor': 0xFF1A1033, 'gradient': True, 'gradientTwoColors': True,
                   'gradientColor1': 0xFF0E7490, 'gradientOpacity1': 100.0, 'gradientColor2': 0xFF3B0764,
                   'gradientOpacity2': 100.0, 'gradientAngle': 45.0, 'textShadow': True, 'textColor': 0xFFFFFFFF}, None),
    'export':   ('s-grace', {'themeId': 'lavender', 'mode': 'light'}, {}, {}, 'l-sunday'),
}


def state_for(shot):
    song, settings, fmt, proj, setlist = SHOTS[shot]
    songs = SONGS
    if shot == 'export':
        # The PDF export prints a {rhythm:} line as raw text: leave it out of this shot.
        songs = [dict(x, raw=x['raw'].replace('{rhythm: D--D-U}\n', '')) if x['id'] == 's-grace' else x for x in SONGS]
    st = {
        'songs': songs, 'tags': TAGS, 'setlists': [SETLIST, SETLIST2], 'trash': [],
        'settings': {**BASE_SETTINGS, **settings}, 'format': fmt, 'projection': proj,
        'selectedSongID': song, 'libraries': [{'id': 'main', 'name': 'My Library'}], 'libraryId': 'main',
    }
    entry = None
    if setlist:
        entry = next(e['id'] for s in (SETLIST, SETLIST2) if s['id'] == setlist
                     for e in s['entries'] if e.get('songId') == song)
    sel = {'song': song, 'setlist': setlist, 'entry': entry, 'slide': 2 if shot == 'bilingual' else 0}
    return st, sel


if __name__ == '__main__':
    for shot in SHOTS:
        st, sel = state_for(shot)
        with open(os.path.join(HERE, f'state_{shot}.json'), 'w') as f:
            json.dump({'state': st, 'selection': sel}, f, ensure_ascii=False)
        print(shot)
