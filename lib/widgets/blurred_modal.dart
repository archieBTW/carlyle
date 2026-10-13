import 'dart:ui';
import 'package:flutter/material.dart';

/// Wraps bottom sheets in a BackdropFilter so the background behind the modal is blurred.
class BlurredModalSheet extends StatelessWidget {
  final Widget child;
  final bool isDraggable;

  const BlurredModalSheet({
    super.key,
    required this.child,
    this.isDraggable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).pop(),
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
        if (isDraggable)
          child
        else
          Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: child,
            ),
          ),
      ],
    );
  }
}

/// Wraps dialogs in a BackdropFilter so the background behind the dialog is blurred.
class BlurredDialog extends StatelessWidget {
  final Widget child;
  final bool dismissible;

  const BlurredDialog({
    super.key,
    required this.child,
    this.dismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: dismissible ? () => Navigator.of(context).pop() : null,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: child,
          ),
        ),
      ],
    );
  }
}
