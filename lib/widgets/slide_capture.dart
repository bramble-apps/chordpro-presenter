import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../projection.dart';
import '../slide_export.dart';
import 'dynamic_background.dart';
import 'projection_view.dart';
import '../ink.dart';

/// Draws each slide exactly as the projector would (background, text,
/// layout, linked translations) out of sight, and takes a picture of it.
/// [width] is the picture's width in pixels; the height follows the
/// projector's shape. Video backgrounds come out as a still (or plain).
Future<List<SlideImage>> captureSlides(
  BuildContext context, {
  required List<String> slides,
  required ProjectionSettings settings,
  required String font,
  required Size projectorSize,
  StageData? stage,
  double width = 1920,
  void Function(int done, int total)? onProgress,

  /// Each slide's annotations (same order as [slides]), drawn in.
  List<List<InkStroke>>? ink,

  /// How long the first slide waits for its background and fonts (later
  /// captures of the same song can wait less: they're already loaded).
  Duration firstWait = const Duration(milliseconds: 500),
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey();
  final current = ValueNotifier<int>(0);
  final zero = ValueNotifier<int>(0);
  final size = projectorSize;
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      // Laid out and painted, but off to the side where no one sees it.
      left: -size.width - 200,
      top: 0,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: RepaintBoundary(
          key: key,
          // The app's text defaults (out here there's no page around it).
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<int>(
              valueListenable: current,
              builder: (_, i, _) => ProjectorDisplay(
                tile: true,
                data: ProjectionData(
                  settings: settings,
                  slides: [slides[i]],
                  selection: zero,
                  transitionSeconds: 0,
                  projectorFont: font,
                  blackout: false,
                  stage: stage,
                  ink: ink == null || i >= ink.length ? null : [ink[i]],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  final out = <SlideImage>[];
  try {
    onProgress?.call(0, slides.length);
    for (var i = 0; i < slides.length; i++) {
      current.value = i;
      // Let it lay out and paint; the first one also waits for the
      // background picture and fonts to arrive.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(
        i == 0 ? firstWait : const Duration(milliseconds: 30),
      );
      // (A dynamic background's still may take longer to draw.)
      await dynamicStillsReady();
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) break;
      final image = await boundary.toImage(pixelRatio: width / size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) continue;
      out.add(
        SlideImage(
          data.buffer.asUint8List(),
          slides[i].replaceAll(' ', '\n\n'),
        ),
      );
      onProgress?.call(i + 1, slides.length);
    }
  } finally {
    entry.remove();
    current.dispose();
    zero.dispose();
  }
  return out;
}

/// Stage view pictures: the whole chord sheet with slide `i` highlighted
/// (and scrolled to), for each `i` in [indices], as the projector shows it.
/// Used for casting from the phone; the live clock is left out.
Future<List<Uint8List>> captureStageSlides(
  BuildContext context, {
  required List<String> slides,
  required List<int> indices,
  required ProjectionSettings settings,
  required String font,
  required Size projectorSize,
  required StageData? stage,
  double width = 1280,
  Duration firstWait = const Duration(milliseconds: 500),

  /// Each slide's annotations (same order as [slides]), drawn in.
  List<List<InkStroke>>? ink,
}) async {
  final overlay = Overlay.of(context, rootOverlay: true);
  final key = GlobalKey();
  final selection = ValueNotifier<int>(indices.isEmpty ? 0 : indices.first);
  final size = projectorSize;
  final entry = OverlayEntry(
    builder: (_) => Positioned(
      left: -size.width - 200,
      top: 0,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: RepaintBoundary(
          key: key,
          child: Material(
            type: MaterialType.transparency,
            child: ProjectorDisplay(
              picture: true,
              data: ProjectionData(
                settings: settings,
                slides: slides,
                selection: selection,
                transitionSeconds: 0,
                projectorFont: font,
                blackout: false,
                stage: stage,
                ink: ink,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  overlay.insert(entry);
  final out = <Uint8List>[];
  try {
    for (var k = 0; k < indices.length; k++) {
      selection.value = indices[k];
      await WidgetsBinding.instance.endOfFrame;
      if (k == 0) await Future<void>.delayed(firstWait);
      // Let the sheet finish scrolling to the highlighted part.
      for (var f = 0; f < 90; f++) {
        await WidgetsBinding.instance.endOfFrame;
        if (!SchedulerBinding.instance.hasScheduledFrame) break;
      }
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) break;
      final image = await boundary.toImage(pixelRatio: width / size.width);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      out.add(data?.buffer.asUint8List() ?? Uint8List(0));
    }
  } finally {
    entry.remove();
    selection.dispose();
  }
  return out;
}
