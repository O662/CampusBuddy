import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A draggable that engages **immediately for a mouse** (plain click-and-drag)
/// while keeping the **long-press** affordance for touch, so finger-scrolling
/// a list/page still works.
///
/// It nests two device-disjoint draggables: an outer [Draggable] whose
/// recognizer is restricted to [PointerDeviceKind.mouse], and the regular
/// [LongPressDraggable] for everything else. The mouse recognizer only claims
/// the gesture once the pointer actually moves past the slop, so a plain
/// click still falls through to child buttons, and the scroll wheel (a
/// pointer-signal, not a drag) is never intercepted.
class AdaptiveDraggable<T extends Object> extends StatelessWidget {
  const AdaptiveDraggable({
    super.key,
    required this.data,
    required this.feedback,
    required this.child,
    this.childWhenDragging,
    this.dragAnchorStrategy = childDragAnchorStrategy,
    this.onDragStarted,
    this.onDragEnd,
  });

  final T data;
  final Widget feedback;
  final Widget child;
  final Widget? childWhenDragging;
  final DragAnchorStrategy dragAnchorStrategy;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    void Function(DraggableDetails)? end =
        onDragEnd == null ? null : (_) => onDragEnd!();
    return _MouseDraggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      dragAnchorStrategy: dragAnchorStrategy,
      onDragStarted: onDragStarted,
      onDragEnd: end,
      child: LongPressDraggable<T>(
        data: data,
        feedback: feedback,
        childWhenDragging: childWhenDragging,
        dragAnchorStrategy: dragAnchorStrategy,
        onDragStarted: onDragStarted,
        onDragEnd: end,
        child: child,
      ),
    );
  }
}

class _MouseDraggable<T extends Object> extends Draggable<T> {
  const _MouseDraggable({
    required super.child,
    required super.feedback,
    required super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragEnd,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
      GestureMultiDragStartCallback onStart) {
    return ImmediateMultiDragGestureRecognizer(
      supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.mouse},
    )..onStart = onStart;
  }
}
