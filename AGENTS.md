# Bilingual Projector — agent notes

Flutter app (web first, also Linux/Android/desktop) for projecting song lyrics
with chords in two languages. Port of a macOS SwiftUI app.

## Where things live (lib/)

- `state.dart` — app state, songs, setlists, settings (largest file; read only the part you need)
- `chordpro.dart` — ChordPro parsing, chords, transposing
- `projection.dart` — settings for what the projector shows
- `translation.dart` — machine-translated copy of each section ("Verse 1 (FR)")
- `justchords.dart` — JustChords import/export (format spec: `~/Downloads/instructions.txt`, follow it exactly)
- `library_import.dart`, `song_sources.dart` — importing songs/backups
- `export.dart`, `slide_export.dart`, `freeshow.dart` — exports
- `cast_*.dart`, `native_cast.dart`, `tools/serve.py` — casting to TVs
- `browser*.dart`, `native*.dart` — platform-specific code (web vs desktop vs none stubs)
- Tests are in `test/`, one file per feature (e.g. `chordpro.dart` → `test/chordpro_test.dart`)

## Commands

- Check code: `flutter analyze`
- Run one test file: `flutter test test/chordpro_test.dart`
- Run all tests: `flutter test`
- Run the app: `./run.sh` (http://localhost:8080)

## Rules

- Before editing, use grep to find the right file and function. Do not guess names.
- Make small, focused changes. Do not rewrite or reformat whole files.
- Match the surrounding code style.
- After an edit, run `flutter analyze` and the related test file, and fix what fails.
- Do not touch `build/`, `.dart_tool/`, or generated platform folders unless asked.
- Do not change `pubspec.yaml` dependencies unless asked.
