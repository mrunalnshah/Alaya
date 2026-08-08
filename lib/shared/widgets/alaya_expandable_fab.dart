import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One action inside an [AlayaExpandableFab].
class FabAction {
  /// Creates an action.
  const FabAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// The label, already localised. Always shown — an icon alone is a guess.
  final String label;

  /// The leading icon.
  final IconData icon;

  /// What tapping it does.
  final VoidCallback onPressed;
}

/// A FAB that unfolds into labelled actions.
///
/// Every action carries a visible label rather than an icon alone. A row of unlabelled icons is a
/// memory test, and the actions here — expense, income, item — are not distinguishable by any icon a
/// user has seen before.
///
/// Collapses on any action, on a tap anywhere outside itself, and on back.
///
/// ## Why the actions used to unfold on the wrong side of the screen
///
/// Two separate causes, and the first one is the one you see.
///
/// **`SizeTransition` left-aligns.** For a vertical axis it builds
/// `ClipRect(Align(alignment: AlignmentDirectional(-1.0, axisAlignment), heightFactor: t))` — and `-1.0`
/// on the horizontal axis means *left*. An `Align` given a `heightFactor` but no `widthFactor` also
/// **expands to fill the width it is offered**. So each min-width action row was being left-aligned inside
/// a box as wide as the whole FAB slot, while the button — not wrapped in a `SizeTransition` — obeyed
/// `CrossAxisAlignment.end` and stayed in the corner. Button right, actions hard left, which is exactly
/// what shipped. The rows fill the slot and right-align their own content now, so the framework's
/// alignment no longer has anything to decide.
///
/// **The slot's width also moved the anchor.** `FloatingActionButtonLocation.endFloat` answers
/// `x = screenWidth - slotWidth - margin` — it anchors by the slot's *own* width. Sizing to content made
/// that width 56 closed and full-screen open (the `Align` above), so `x` went to `-16` and the whole menu,
/// button included, shifted off the left edge. A slot of `screenWidth - 2 * md` makes it constant: `x = md`
/// open or closed, and off-screen becomes unreachable rather than unlikely.
///
/// The bound also gives the labels something to ellipsise against. `Flexible` was always there for that,
/// but under a full-screen loose constraint it had nothing to push back on and the row simply grew.
///
/// **Still no scrim (ARCH_3 §8.3).** A full-screen dim drawn from inside the FAB slot is either clipped
/// to the slot — invisible, and unable to receive the tap it exists for — or forces the slot wider and
/// reintroduces the anchor drift above. `TapRegion` supplies the dismissal without either failure, and
/// the rows carry opaque surfaces of their own so they stay legible over content.
class AlayaExpandableFab extends StatefulWidget {
  /// Creates an expandable FAB.
  const AlayaExpandableFab({
    required this.actions,
    required this.openLabel,
    required this.closeLabel,
    super.key,
  });

  /// The actions, in the order they unfold upward.
  final List<FabAction> actions;

  /// Accessibility label for the collapsed button.
  final String openLabel;

  /// Accessibility label for the expanded button.
  final String closeLabel;

  @override
  State<AlayaExpandableFab> createState() => _AlayaExpandableFabState();
}

class _AlayaExpandableFabState extends State<AlayaExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: AlayaDurations.slow,
    vsync: this,
  );
  bool _expanded = false;

  void _toggle() => _expanded ? _collapse() : _expand();

  /// Whether the platform has asked for reduced motion.
  ///
  /// **Skipped, not shortened** (ARCH_5 §2.6, §6). `jumpTo` puts the controller at its end state in one frame,
  /// so the actions appear and disappear without travelling — a user who asked for less motion gets none, and
  /// still gets the full affordance. Shortening the duration would be a smaller version of the thing they
  /// switched off.
  bool get _reducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _expand() {
    setState(() => _expanded = true);
    _reducedMotion ? _controller.value = 1 : _controller.forward();
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    _reducedMotion ? _controller.value = 0 : _controller.reverse();
  }

  void _run(FabAction action) {
    _collapse();
    action.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The margin `endFloat` will subtract, on both sides, so the anchor lands at exactly `md`.
    //
    // **Clamped, because Android's first frame reports a zero-width viewport.** The engine logs it twice
    // before the tree builds — `D/FlutterRenderer: Width is zero. 0,0` — and `0 - 32` is `-32`, which is
    // not a width: `SizedBox` asserted `BoxConstraints has a negative minimum width` and the app opened
    // to a red screen on every launch. The fixed extent is still what keeps the anchor still (Law U28);
    // it simply cannot go below nothing. The next frame carries the real width and the slot corrects
    // itself, which is why the fault never survived to a screenshot and never showed up in tests — the
    // widget harness always sets a real viewport before pumping.
    final slotWidth = (MediaQuery.sizeOf(context).width - AlayaSpacing.md * 2)
        .clamp(0.0, double.infinity);

    return PopScope<Object?>(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _collapse();
      },
      child: TapRegion(
        onTapOutside: (_) => _collapse(),
        // Rebuilt per frame so the action rows leave the tree at the end of the reverse rather than the
        // start of it: a SizeTransition zeroes its child's height but not its width, and rows left
        // mounted while collapsed would keep taking hit tests over the content behind them.
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SizedBox(
            width: slotWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!_controller.isDismissed)
                  for (final action in widget.actions)
                    SizeTransition(
                      sizeFactor: _controller,
                      axisAlignment: 1,
                      child: FadeTransition(
                        opacity: _controller,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: AlayaSpacing.sm,
                          ),
                          child: _ActionRow(
                            action: action,
                            onTap: () => _run(action),
                          ),
                        ),
                      ),
                    ),
                FloatingActionButton(
                  onPressed: _toggle,
                  tooltip: _expanded ? widget.closeLabel : widget.openLabel,
                  child: AnimatedRotation(
                    turns: _expanded ? 0.125 : 0,
                    duration: AlayaDurations.base,
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final FabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fills the slot and right-aligns its content, rather than being a min-width row left-aligned by
    // `SizeTransition`. See the class doc: this is the line that puts the actions under the button.
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible against the slot's bounded width: the label ellipsises at the screen edge instead of
        // widening the row past it.
        Flexible(
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AlayaSpacing.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.sm,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      action.label,
                      style: AlayaTypography.button.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AlayaSpacing.sm),
        SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Material(
            color: theme.colorScheme.secondary,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(
                action.icon,
                color: theme.colorScheme.onSecondary,
                size: AlayaIconSize.md,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
