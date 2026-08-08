import 'package:flutter/material.dart';

/// Centres [child] in the available space, and scrolls instead of overflowing when there is not
/// enough of it (ARCH_3 §8.3).
///
/// The shape the full-height state widgets share, in one place. A bare `Center` hands its child
/// loose constraints and then lets it exceed them, which is why a state widget that looks right on a
/// phone in portrait paints an overflow stripe in a short list area, in landscape, or at a large
/// accessibility text scale. The `minHeight` is what keeps the content vertically centred when the
/// space *is* sufficient, so the common case is indistinguishable from a plain `Center`.
///
/// Falls back to a bare `Center` when the incoming height is unbounded, because a vertical
/// `SingleChildScrollView` given infinite height asserts rather than degrading.
class ScrollSafeCenter extends StatelessWidget {
  /// Centres and, when necessary, scrolls [child].
  const ScrollSafeCenter({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The content to centre.
  final Widget child;

  /// Padding around [child], inside the scrollable area so it scrolls with the content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Padding(
        padding: padding,
        child: Center(child: child),
      );
      if (!constraints.hasBoundedHeight) return content;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: content,
        ),
      );
    },
  );
}
