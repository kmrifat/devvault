import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' show Material, MaterialType;

import '../../shared/desktop_ui.dart';

/// Drags [data] (an item from the list, an app in the sidebar) to a
/// sidebar row, with a [DragChip] under the pointer.
///
/// Only a mouse starts a drag, as soon as it moves with the button held:
/// on a touch screen, dragging a list keeps scrolling it.
class TreeDraggable<T extends Object> extends Draggable<T> {
  const TreeDraggable({
    super.key,
    required T super.data,
    required super.feedback,
    required super.child,
  }) : super(dragAnchorStrategy: pointerDragAnchorStrategy);

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) => ImmediateMultiDragGestureRecognizer(
    supportedDevices: const {PointerDeviceKind.mouse},
    allowedButtonsFilter: allowedButtonsFilter,
  )..onStart = onStart;
}

/// What follows the pointer while an item or app is dragged to a sidebar
/// row: its icon and name on a small menu-coloured pill.
class DragChip extends StatelessWidget {
  const DragChip({super.key, required this.label, required this.leading});

  final String label;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final colors = context.desktopColors;
    // A drag's feedback is in the overlay, outside any Material.
    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 240),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colors.menu,
          border: Border.all(color: colors.groupBoxStroke, width: 0.5),
          borderRadius: const BorderRadius.all(
            Radius.circular(DesktopMetrics.menuRadius),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            SizedBox(width: 16, child: Center(child: leading)),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: DesktopMetrics.bodySize,
                  color: colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
