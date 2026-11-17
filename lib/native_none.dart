import 'package:flutter/widgets.dart';

import 'cast_feeder.dart';
import 'state.dart';

Future<void> setUpNativeIO() async {}

Future<void> setUpProjectorIO() async {}

Future<bool> runDesktopProjector() async => false;

Future<void> setUpDesktopOperator(PresenterModel model) async {}

class DesktopWindowFrame extends StatelessWidget {
  final Widget child;
  const DesktopWindowFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

Widget externalProjector(ProjectorModel model, Widget child) => child;

class NativeDisplaySection extends StatelessWidget {
  final PresenterModel model;
  const NativeDisplaySection({super.key, required this.model});

  static bool get available => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Casting with pictures from the app itself (none on the web).
SlideCaster? get nativeCaster => null;

class NativeCastSection extends StatelessWidget {
  final PresenterModel model;
  const NativeCastSection({super.key, required this.model});

  static bool get available => false;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
