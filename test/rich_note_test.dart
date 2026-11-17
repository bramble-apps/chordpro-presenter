import 'package:bilingual_projector/widgets/rich_note_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RichNoteController make(String text) =>
      RichNoteController(text: text, base: const CharStyle());

  test('formatting applies to the selection only', () {
    final c = make('Hello world');
    c.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    c.toggleBold();
    expect(c.toRuns(), [
      {'t': 'Hello ', 'b': false, 'i': false, 's': 16.0},
      {'t': 'world', 'b': true, 'i': false, 's': 16.0},
    ]);
    // All bold already: the same button turns it off.
    c.toggleBold();
    expect(c.toRuns(), hasLength(1));
  });

  test('nothing selected: the whole note', () {
    final c = make('Hello world');
    c.selection = const TextSelection.collapsed(offset: 3);
    c.toggleItalic();
    c.resize(4);
    expect(c.toRuns(), [
      {'t': 'Hello world', 'b': false, 'i': true, 's': 20.0},
    ]);
    expect(c.base.italic, isTrue, reason: 'new text too');
  });

  test('typing and deleting keep the styles in step', () {
    final c = make('ab cd');
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    c.toggleBold();
    // Type after "ab": takes its look (bold).
    c.value = const TextEditingValue(
      text: 'abX cd',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(c.toRuns().first, {'t': 'abX', 'b': true, 'i': false, 's': 16.0});
    // Delete "X c": the rest stays where it was.
    c.value = const TextEditingValue(
      text: 'abd',
      selection: TextSelection.collapsed(offset: 2),
    );
    expect(c.toRuns(), [
      {'t': 'ab', 'b': true, 'i': false, 's': 16.0},
      {'t': 'd', 'b': false, 'i': false, 's': 16.0},
    ]);
  });

  test('saved runs come back the same', () {
    final c = make('one two three');
    c.selection = const TextSelection(baseOffset: 4, extentOffset: 7);
    c.toggleItalic();
    c.resize(6);
    final again = RichNoteController.fromRuns(
      c.toRuns(),
      text: '',
      base: const CharStyle(),
    );
    expect(again.text, 'one two three');
    expect(again.toRuns(), c.toRuns());
  });
}
