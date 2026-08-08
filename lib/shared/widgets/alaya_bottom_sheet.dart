import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one bottom-sheet scaffold (ARCH_3 §8.3).
///
/// **Every sheet goes through here.** It composes the keyboard inset padding, [SafeArea] and a
/// [SingleChildScrollView] in that order, exactly once — the combination each sheet otherwise gets
/// wrong in the same way. A `MainAxisSize.min` Column inside a `Padding` keyed to
/// `viewInsets.bottom` is correct in each half and broken together: the padding shrinks the
/// available height and the Column has no way to give up the room it already took, so it overflows
/// the instant a keyboard opens and never otherwise. Putting the scroll view *inside* the padding
/// turns that overflow into scroll extent instead.
///
/// Sheets therefore return content only — no `SafeArea`, no `viewInsets` padding and no scroll view
/// of their own. A sheet that adds one is reintroducing the bug.
class AlayaBottomSheet extends StatelessWidget {
  /// Wraps [child] in the sheet scaffold. Prefer [show].
  const AlayaBottomSheet({
    required this.child,
    this.padding = defaultPadding,
    super.key,
  });

  /// The sheet's content, laid out as though the viewport were tall enough for it.
  final Widget child;

  /// Padding around [child]. Inside the scroll view, so it scrolls with the content rather than
  /// eating viewport height a keyboard has already taken.
  final EdgeInsetsGeometry padding;

  /// The default content padding: screen-edge horizontally, tighter at the top where the drag
  /// handle already provides separation.
  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(
    AlayaSpacing.screenEdge,
    AlayaSpacing.xs,
    AlayaSpacing.screenEdge,
    AlayaSpacing.md,
  );

  /// Shows [builder]'s widget as a modal sheet and resolves to whatever it pops.
  ///
  /// `isScrollControlled` is not optional: without it the sheet is capped near half the screen and
  /// cannot grow when a keyboard pushes its content up. `useSafeArea` keeps the sheet clear of the
  /// status bar while deliberately leaving the bottom edge to this widget's own [SafeArea] — so the
  /// sheet's background still runs behind the navigation bar and only its content is inset.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    EdgeInsetsGeometry padding = defaultPadding,
    bool isDismissible = true,
    bool enableDrag = true,
  }) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (context) =>
        AlayaBottomSheet(padding: padding, child: builder(context)),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: padding,
        child: child,
      ),
    ),
  );
}
