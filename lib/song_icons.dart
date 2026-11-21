// A small icon a song can carry (OnSong's song icons): shown beside its
// title in the song list and setlists, to spot songs at a glance. Kept in
// the song's extra fields (`icon`), so it travels in backups.

import 'package:flutter/material.dart';

import 'state.dart';
import 'bramble_icons.dart';

/// The icons to choose from, by the name saved with the song.
const Map<String, (IconData, String)> songIcons = {
  'star': (BrambleIcons.starFill, 'Star'),
  'heart': (BrambleIcons.heartFill, 'Favourite'),
  'hymn': (BrambleIcons.bookOpenText, 'Hymn'),
  'church': (BrambleIcons.church, 'Church'),
  'piano': (BrambleIcons.pianoKeys, 'Piano'),
  'mic': (BrambleIcons.microphone, 'Vocal'),
  'note': (BrambleIcons.musicNote, 'Music'),
  'globe': (BrambleIcons.globeHemisphereWest, 'Bilingual'),
  'kids': (BrambleIcons.baby, 'Kids'),
  'christmas': (BrambleIcons.tree, 'Christmas'),
  'easter': (BrambleIcons.egg, 'Easter'),
  'communion': (BrambleIcons.bread, 'Communion'),
  'baptism': (BrambleIcons.drop, 'Baptism'),
  'fire': (BrambleIcons.fire, 'Upbeat'),
  'calm': (BrambleIcons.moon, 'Slow'),
  'sun': (BrambleIcons.sun, 'Opener'),
  'new': (BrambleIcons.tbNewSection, 'New'),
  'check': (BrambleIcons.checkCircleFill, 'Ready'),
  'flag': (BrambleIcons.flag, 'Needs work'),
  'bolt': (BrambleIcons.lightning, 'Special'),
};

/// [song]'s icon, if it has one.
IconData? songIconOf(Song song) => songIcons[song.extra['icon']]?.$1;

void setSongIcon(Song song, String? name) {
  if (name == null || !songIcons.containsKey(name)) {
    song.extra.remove('icon');
  } else {
    song.extra['icon'] = name;
  }
}
