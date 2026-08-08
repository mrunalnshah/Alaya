import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Shakes its child horizontally when [trigger] changes.
///
/// Used on the PIN pad and on a rejected form. A shake communicates rejection without moving focus or
/// stealing the keyboard, which a snack bar or dialog both do — and on a PIN pad, keeping focus is the
/// difference between retrying immediately and re-tapping the field.
///
/// Keyed on an incrementing [trigger] rather than a bool, so two consecutive failures shake twice. A
/// bool that is already `true` produces no change and therefore no second shake, which reads as the
/// app having ignored the attempt.
///
/// Respects `MediaQuery.disableAnimations`: when a user has asked the platform to reduce motion, the
/// shake is skipped entirely rather than shortened.
class ShakeOnError extends StatefulWidget {
  /// Creates a shake wrapper.
  const ShakeOnError({
    required this.trigger,
    required this.child,
    this.distance = 10,
    super.key,
  });

  /// Increment this to shake.
  final int trigger;

  /// The widget to shake.
  final Widget child;

  /// Peak horizontal displacement in logical pixels.
  final double distance;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    // Four legs plus a settle, each one shakeLeg long.
    duration: AlayaDurations.shakeLeg * 5,
    vsync: this,
  );

  @override
  void didUpdateWidget(ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      // A decaying sine: four crossings, each smaller than the last, settling at zero.
      final t = _controller.value;
      final decay = 1 - t;
      final offset = widget.distance * decay * math.sin(t * 4 * math.pi);
      return Transform.translate(offset: Offset(offset, 0), child: child);
    },
    child: widget.child,
  );
}
