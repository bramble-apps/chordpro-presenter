// A small icon a song can carry (OnSong's song icons): shown beside its
// title in the song list and setlists, to spot songs at a glance. Kept in
// the song's extra fields (`icon`), so it travels in backups.

import 'package:flutter/material.dart';

import 'state.dart';

/// The icons to choose from, by the name saved with the song.
const Map<String, (IconData, String)> songIcons = {
  'star': (Icons.star_rounded, 'Star'),
  'heart': (Icons.favorite_rounded, 'Favourite'),
  'hymn': (Icons.menu_book_rounded, 'Hymn'),
  'church': (Icons.church_rounded, 'Church'),
  'piano': (Icons.piano, 'Piano'),
  'mic': (Icons.mic_rounded, 'Vocal'),
  'note': (Icons.music_note_rounded, 'Music'),
  'globe': (Icons.public, 'Bilingual'),
  'kids': (Icons.child_care_rounded, 'Kids'),
  'christmas': (Icons.park_rounded, 'Christmas'),
  'easter': (Icons.egg_rounded, 'Easter'),
  'communion': (Icons.bakery_dining_rounded, 'Communion'),
  'baptism': (Icons.water_drop_rounded, 'Baptism'),
  'fire': (Icons.local_fire_department_rounded, 'Upbeat'),
  'calm': (Icons.nightlight_round, 'Slow'),
  'sun': (Icons.wb_sunny_rounded, 'Opener'),
  'new': (Icons.fiber_new_rounded, 'New'),
  'check': (Icons.check_circle_rounded, 'Ready'),
  'flag': (Icons.flag_rounded, 'Needs work'),
  'bolt': (Icons.bolt_rounded, 'Special'),
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
