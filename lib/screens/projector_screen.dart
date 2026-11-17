import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../browser.dart';
import '../state.dart';
import '../widgets/projection_view.dart';

/// Audience display. Drag this window to the projector screen and
/// double-click (or press F) for fullscreen. Arrow keys / space also work here.
class ProjectorScreen extends StatefulWidget {
  final ProjectorModel model;
  const ProjectorScreen({super.key, required this.model});

  @override
  State<ProjectorScreen> createState() => _ProjectorScreenState();
}

class _ProjectorScreenState extends State<ProjectorScreen> {
  bool _showHint = true;

  @override
  void initState() {
    super.initState();
    widget.model.start();
    HardwareKeyboard.instance.addHandler(_onKey);
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.space) {
      widget.model.next();
      return true;
    }
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.pageUp) {
      widget.model.previous();
      return true;
    }
    if (key == LogicalKeyboardKey.keyF && event is KeyDownEvent) {
      toggleFullscreen();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTap: toggleFullscreen,
        child: Stack(
          children: [
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Let the operator's preview match this window exactly.
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => model.reportSize(constraints.biggest),
                  );
                  return ListenableBuilder(
                    listenable: model,
                    builder: (context, _) => model.stopped
                        ? const SizedBox.expand()
                        : ProjectorDisplay(data: model.projectionData),
                  );
                },
              ),
            ),
            if (_showHint)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: Center(
                  child: Text(
                    'Double-click or press F for fullscreen',
                    style: TextStyle(color: Colors.white54, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
