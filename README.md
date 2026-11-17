# ChordPro Presenter

Your songbook for rehearsal and the stage. Chord sheets, setlists, projection in two languages and the
band tools you reach for mid-song, in one free app. No account, no ads, no tracking.

A BrambleApps app, for **Android**, **Linux**, **Windows** and **macOS**.

## Download

- **Android**: on Google Play (closed test now), or from the
  [latest release](https://github.com/bramble-apps/chordpro-presenter/releases/latest) with
  [Obtainium](https://obtainium.imranr.dev/), which keeps it up to date.
- **Windows, macOS (Apple silicon and Intel), Linux (AppImage and Flatpak)**: the
  [latest release](https://github.com/bramble-apps/chordpro-presenter/releases/latest).
  The Windows and AppImage versions update themselves; the macOS and Flatpak versions tell you when a new
  release is out.

The macOS app isn't signed with an Apple developer certificate yet: the first time, right-click the app,
choose **Open**, then **Open** again.

## What it does

- **Chord sheets**: ChordPro with chords over the words or inline; guitar, ukulele and piano diagrams;
  tabs with playback; melodies in ABC, engraved with playback; sticky notes, pen and highlighter.
- **Chords your way**: transpose and capo per song or per setlist; letters, Nashville numbers, Roman
  numerals or solfège, or two at once; chord beats and strum patterns.
- **Setlists**: dividers, labels and events; keys and arrangements just for one setlist; Band Sync to send
  the set to everyone's device on the same Wi-Fi.
- **On stage**: metronome, autoscroll, chromatic tuner and level meter, pads that follow the key, reference
  recordings, page-turner pedals.
- **Projection**: lyrics on a projector, TV, Chromecast or any browser on the Wi-Fi, in one or two
  languages, over colours, pictures, videos or 18 animated wallpapers; stage view, countdown, blackout,
  Scripture.
- **Remote control**: scan a QR code and a phone or tablet runs the slides.
- **Import and export**: OnSong, JustChords, SongbookPro, FreeShow, ChordPro, text, PDF and pictures in;
  PDF songbooks, slides, PowerPoint, FreeShow, JustChords and more out.

## Building from source

The app is Flutter (web first); the desktop apps wrap the web build in Electron, with a small Python server
(`tools/serve.py`) for casting, other screens on the network and song search.

- Check the code: `flutter analyze`
- Tests: `flutter test`
- Run in a browser: `./run.sh`, then open http://localhost:8080
- Desktop app: `flutter build web --release --no-web-resources-cdn`, then in `desktop/electron`:
  `pip install --target pylib -r requirements.txt`, `npm ci` and `npm run dist` (Linux AppImage), or
  `npx electron-builder --win` / `--mac` on those systems.
- Android: `flutter build apk --release`

Pushing a `v*` tag builds every desktop download on GitHub Actions and publishes the release
(`.github/workflows/release.yml`); see [RELEASING.md](RELEASING.md).

## Contributing

Issues and pull requests are welcome. Keep a change focused, in the style of the code around it, and run
`flutter analyze` and `flutter test` before sending it. See [AGENTS.md](AGENTS.md) for where things live.

Much of this app's code was written with the help of AI coding tools (Anthropic's Claude), with the
maintainer directing, reviewing and testing it. Commits made with that help say so in a `Co-Authored-By`
line.

## Licence

GPL-3.0-or-later (see [LICENSE](LICENSE)). Bundled fonts, the Salamander piano sound and the World English
and King James Bibles keep their own licences, next to each in `assets/`.
