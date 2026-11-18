# Releasing

1. Raise the version in **both** `pubspec.yaml` (`version: 1.0.1+2`: the number after `+` must go up for
   Google Play) and `desktop/electron/package.json` (`"version": "1.0.1"`).
2. Run `flutter analyze` and `flutter test`.
3. Commit, then tag and push: `git tag v1.0.1 && git push origin main v1.0.1`.
   GitHub Actions builds Windows, macOS (Apple silicon and Intel), the AppImage and the Flatpak bundle and
   publishes them in the release; the desktop apps find it there. File names carry no version, so the
   website's links (`releases/latest/download/<name>`) always fetch the newest one.
4. Android (signed with the Play upload key, which stays off GitHub):
   - `flutter build apk --release`, then attach it to the release under the app's name (Obtainium
     installs and updates from these):
     `cp build/app/outputs/flutter-apk/app-release.apk ChordPro_Presenter.apk && gh release upload v1.0.1 ChordPro_Presenter.apk`
   - `flutter build appbundle --release` and upload `build/app/outputs/bundle/release/app-release.aab` in
     the Play Console.
