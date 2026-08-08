# PHASE 9 — Animation, performance, accessibility and release configuration

## Dependencies

**None. `flutter_animate` is not added.**

The task says to add it *"only if the animation pass actually imports it"*, and nothing does. ARCH_5 §2.6
permits exactly four animations, and every one is framework-native: `pageTransitionsTheme` for routes, the
framework's own sheet transition, an `AnimationController` for the FAB unfold, and `AnimatedSwitcher` for a
value changing in place. A package would add a dependency to express what four Flutter widgets already do —
and §2.6's closing line, *"the app is opened for twenty seconds"*, is an argument against having a motion
library available at all.

---

## The animation audit, and four of my own findings that were wrong

The instruction was to *"remove anything else that crept in"*. **Nothing had.** The audit found two gaps
rather than two excesses, and getting there took four false positives worth recording, because each came from
matching text rather than reading code.

| I reported | Reality |
|---|---|
| A stray `Hero` animation in `asset_detail_screen.dart` | `_Hero` is a **private layout class** — the hero *section* of a detail screen. Not Flutter's `Hero`, not an animation |
| `MediaQuery.disableAnimationsOf` used nowhere | `ShakeOnError` guards correctly, via `maybeDisableAnimationsOf`. My pattern was case-sensitive and `maybe**D**isableAnimationsOf` does not contain it |
| A shimmering skeleton, a fifth animation | `AlayaListSkeleton` does not animate at all. The word appeared in a **doc comment** explaining that a shimmer would be disabled anyway, which is why the widget is static |
| Eleven U13 violations | Nine are bounded sets — five account kinds, six tag scopes, three currencies. A `for` inside a `Column` is not a virtualisation problem when the collection cannot grow |

**That is the seventh prose-versus-code confusion this project has produced from me**, and the pattern is
identical each time: a `grep` for a symbol matches a comment that mentions it. The check that works is to strip
comment lines before searching, and it costs one line.

### What the audit actually found

| §2.6 row | State before | Action |
|---|---|---|
| Route transition | `FadeForwardsPageTransitionsBuilder` in `AlayaTheme` | Correct. `AlayaDurations.page` resolved — see below |
| Sheet in/out | `AlayaBottomSheet`, framework transition | Correct |
| FAB unfold | `AlayaExpandableFab`, `AlayaDurations.slow` | **No reduced-motion guard.** Fixed |
| A value changing in place | `AnimatedSwitcher` used **nowhere** | **A permitted animation was missing.** Added to the dashboard's funds total |
| `ShakeOnError` | Guarded | Correct |

Two gaps, both in the direction of too little rather than too much.

### ARCH_4 §5.1 item 22 — `AlayaDurations.page` is deleted, not wired

`FadeForwardsPageTransitionsBuilder` is Material 3's own transition and carries its own timing; it takes no
duration. Wiring the token would mean replacing Material's motion with a hand-rolled builder to honour an
invented 300 ms — worse motion, for no user benefit, and against §2.6's *"do not wrap a screen in your own
transition."*

Item 22 states the test itself: *"a token that documents a value the app does not use is worse than no
token."* It is deleted, and `ThemeLabScreen` — the only reader, and only to display it — drops the row.

---

## The animation pass — five files

### `lib/app/theme/tokens/alaya_durations.dart`

```dart
/// The animation duration scale (ARCH_3 §8).
///
/// Four values, and no widget writes its own. The figures are the ones ARCH_3 §8 specifies, and the
/// reason they are short is that this app is used in twenty-second bursts — logging a purchase at a
/// till. An animation the user waits through is a cost, not polish.
abstract final class AlayaDurations {
  /// 120 ms — a colour change, a check mark, a ripple settling.
  static const Duration fast = Duration(milliseconds: 120);

  /// 220 ms — the default. An expanding card, a chip toggling, a sheet's content settling.
  static const Duration base = Duration(milliseconds: 220);

  /// 380 ms — the expandable FAB unfolding, a large surface reflowing.
  static const Duration slow = Duration(milliseconds: 380);

  /// 90 ms — one leg of the error shake, which is four legs plus a settle.
  static const Duration shakeLeg = Duration(milliseconds: 90);

  /// 2.5 s — how long a snack bar stays.
  static const Duration snack = Duration(milliseconds: 2500);

  /// 300 ms — how long a search field waits after the last keystroke before querying.
  ///
  /// An interaction delay rather than an animation, and it sits here because Law U6 says every
  /// duration in a widget comes from a token — so the token file has to hold every duration a widget
  /// needs. It is deliberately longer than [base]: a debounce tuned to an animation scale fires
  /// mid-word and makes typing feel like it is fighting the field.
  ///
  /// A **network** timeout still does not belong here. That scale is seconds and lives with the
  /// client that owns the call (see `infrastructure_providers.dart`).
  static const Duration debounce = Duration(milliseconds: 300);
}
```

### `lib/shared/widgets/alaya_expandable_fab.dart`

```dart
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
  bool get _reducedMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

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
    final slotWidth =
        (MediaQuery.sizeOf(context).width - AlayaSpacing.md * 2).clamp(0.0, double.infinity);

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
```

### `lib/features/dashboard/presentation/widgets/funds_header.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Total available funds — the one `displayAmount` on the dashboard (ARCH_5 §3 archetype F).
///
/// **One headline, because two headline numbers is no headline number.** Every other figure on this
/// screen is `AmountSize.small` or smaller, and that hierarchy is the whole reason a glance works.
///
/// **The figure comes from `BalanceService.totalInHome` and nothing else.** A self-transfer cannot move
/// it: the balances behind it come from `v_account_ledger`, which counts a transfer once against each
/// side. If this number ever changes when money moves between the user's own accounts, the view is being
/// bypassed rather than the arithmetic being wrong.
///
/// **What cannot be converted is excluded and said out loud** (anomaly A34). Summing a dirham balance
/// into a rupee total at face value would be a wrong number presented as a right one; a smaller number
/// with a chip beside it is honest, and the chip explains itself rather than just counting.
class FundsHeader extends ConsumerWidget {
  /// Creates the header.
  const FundsHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final async = ref.watch(totalFundsProvider);
    final digits = ref.watch(dashboardDigitsProvider).valueOrNull ?? 2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: async.when(
        // Its own skeleton rather than the screen's: a slow rate table must not blank the range rows or
        // the module grid beneath it (ARCH_5 §3 archetype F).
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            Text(
              strings.loadingDashboard,
              style: AlayaTypography.body.copyWith(color: semantic.muted),
            ),
          ],
        ),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(totalFundsProvider),
        ),
        data: (worth) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.fundsAvailable,
              style: AlayaTypography.label.copyWith(color: semantic.muted),
            ),
            const SizedBox(height: AlayaSpacing.xs),
            // **ARCH_5 §2.6's fourth animation, and the only place it belongs.** A total that recalculates
            // should show *that* it changed — otherwise a figure quietly becoming a different figure is
            // indistinguishable from one that was always that. This is the app's headline number and the only
            // one that moves on its own, when a transaction lands or a rate is fetched.
            //
            // Keyed on the amount, so an identical recomputation does not blink. `AlayaDurations.base`, per the
            // token §2.6 names. Under reduced motion the duration collapses to zero, which is a **skip** rather
            // than a shortening: the new value simply replaces the old with no cross-fade at all.
            AnimatedSwitcher(
              duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                  ? Duration.zero
                  : AlayaDurations.base,
              child: AmountText(
                worth.total,
                key: ValueKey<int>(worth.total.minor),
                // The one `displayAmount` on the screen (ARCH_5 §2.3). Omitting this fell back to
                // `AmountSize.medium` — the ledger-row size — which left the dashboard with no headline
                // at all while every doc comment claimed it had one.
                size: AmountSize.display,
                showSign: false,
                decimalDigits: digits,
              ),
            ),
            if (!worth.isComplete || worth.isApproximate) ...[
              const SizedBox(height: AlayaSpacing.sm),
              Wrap(
                spacing: AlayaSpacing.xs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  if (!worth.isComplete)
                    StatusChip(
                      label: strings.fundsUnconverted(worth.unconvertedCount),
                      tone: StatusTone.warning,
                    ),
                  if (worth.isApproximate)
                    StatusChip(label: strings.fundsApproximate, tone: StatusTone.info),
                ],
              ),
              if (!worth.isComplete) ...[
                const SizedBox(height: AlayaSpacing.xs),
                Text(
                  strings.fundsWhyExcluded,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
```

### `lib/features/settings/presentation/theme_lab_screen.dart`

```dart
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Every token, component and semantic colour on one page, light and dark side by side (ARCH_3 §8.2).
///
/// **This is how palettes actually get chosen.** The alternative is navigating the real app hunting for
/// a screen that happens to use `warning`, discovering it only renders in one state, and guessing about
/// the rest. Everything enumerates from the token maps rather than a hand-written list, so a token
/// added later appears here without anyone remembering to add it.
///
/// Debug-only. In a release build it renders a single line saying so rather than the lab, which keeps
/// it out of the shipped UI without a conditional route that could be got wrong.
class ThemeLabScreen extends ConsumerWidget {
  /// Creates the lab.
  const ThemeLabScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    if (!kDebugMode) {
      return Center(child: Text(strings.themeLabTitle));
    }

    final palette = ref.watch(activePaletteProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.md,
            AlayaSpacing.screenEdge,
            0,
          ),
          child: Text(
            strings.themeLabSubtitle,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SectionHeader(label: strings.themeLabSectionPalettes),
        _PalettePicker(
          current: palette,
          // **Phase 8A: `use`, not `state =`.** `activePaletteProvider` became a persisted `Notifier` when
          // ARCH_4 §5.1 item 23 was closed, and assigning `state` directly would retheme this session while
          // never reaching `app_settings` — the exact bug item 23 was about, moved one screen along.
          onSelected: (next) => ref.read(activePaletteProvider.notifier).use(next),
        ),
        SectionHeader(label: strings.themeLabSectionSemantic),
        _SideBySide(palette: palette, builder: (context) => const _SemanticSwatches()),
        SectionHeader(label: strings.themeLabSectionSurfaces),
        _SideBySide(palette: palette, builder: (context) => const _SurfaceTiers()),
        SectionHeader(label: strings.themeLabSectionTypography),
        const _TypeScale(),
        SectionHeader(label: strings.themeLabSectionSpacing),
        const _SpacingScale(),
        SectionHeader(label: strings.themeLabSectionRadii),
        const _RadiiScale(),
        SectionHeader(label: strings.themeLabSectionElevation),
        _SideBySide(palette: palette, builder: (context) => const _ElevationScale()),
        SectionHeader(label: strings.themeLabSectionComponents),
        _SideBySide(palette: palette, builder: (context) => const _Components()),
      ],
    );
  }
}

/// Renders [builder] twice, in light and dark, so a palette is judged as a pair.
class _SideBySide extends StatelessWidget {
  const _SideBySide({required this.palette, required this.builder});

  final AlayaPalette palette;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Pane(
              label: strings.themeLabLight,
              theme: AlayaTheme.light(palette),
              child: builder(context),
            ),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: _Pane(
              label: strings.themeLabDark,
              theme: AlayaTheme.dark(palette),
              child: builder(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.theme, required this.child});

  final String label;
  final ThemeData theme;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AlayaTypography.overline),
          const SizedBox(height: AlayaSpacing.xxs),
          Theme(
            data: theme,
            child: Builder(
              builder: (context) => DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: AlayaRadii.borderSm,
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Padding(padding: const EdgeInsets.all(AlayaSpacing.sm), child: child),
              ),
            ),
          ),
        ],
      );
}

class _PalettePicker extends StatelessWidget {
  const _PalettePicker({required this.current, required this.onSelected});

  final AlayaPalette current;
  final ValueChanged<AlayaPalette> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final preset in AlayaPresets.all)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: AlayaCard(
                  tier: preset.name == current.name ? 2 : 1,
                  border: preset.name == current.name,
                  onTap: () => onSelected(preset),
                  child: Row(
                    children: [
                      for (final swatch in [
                        preset.light.primary,
                        preset.light.accent,
                        preset.dark.surfaceBase,
                        preset.light.income,
                        preset.light.expense,
                      ]) ...[
                        _Swatch(color: swatch),
                        const SizedBox(width: AlayaSpacing.xxs),
                      ],
                      const SizedBox(width: AlayaSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(preset.name, style: AlayaTypography.cardTitle),
                            Text(preset.description, style: AlayaTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: AlayaSpacing.lg,
        height: AlayaSpacing.lg,
        decoration: BoxDecoration(color: color, borderRadius: AlayaRadii.borderXs),
      );
}

class _SemanticSwatches extends StatelessWidget {
  const _SemanticSwatches();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in semantic.byName.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
            child: Row(
              children: [
                _Swatch(color: entry.value),
                const SizedBox(width: AlayaSpacing.xs),
                Expanded(child: Text(entry.key, style: AlayaTypography.caption)),
              ],
            ),
          ),
      ],
    );
  }
}

class _SurfaceTiers extends StatelessWidget {
  const _SurfaceTiers();

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final tier in [-1, 0, 1, 2])
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: AlayaCard(
                tier: tier,
                border: true,
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text('tier $tier', style: AlayaTypography.caption),
              ),
            ),
        ],
      );
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final entry in AlayaTypography.all.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.key, style: AlayaTypography.overline),
                    // 1,234,567.89 rather than lorem: the figures are what the tabular treatment is
                    // for, and a pangram would hide the thing being judged.
                    Text('1,234,567.89 Alaya', style: entry.value),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _SpacingScale extends StatelessWidget {
  const _SpacingScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xxs 4': AlayaSpacing.xxs,
      'xs 8': AlayaSpacing.xs,
      'sm 12': AlayaSpacing.sm,
      'md 16': AlayaSpacing.md,
      'lg 20': AlayaSpacing.lg,
      'xl 24': AlayaSpacing.xl,
      'xxl 32': AlayaSpacing.xxl,
      'xxxl 48': AlayaSpacing.xxxl,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
              child: Row(
                children: [
                  SizedBox(
                    width: 70,
                    child: Text(entry.key, style: AlayaTypography.caption),
                  ),
                  Container(
                    width: entry.value,
                    height: AlayaSpacing.sm,
                    color: semantic.transfer,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RadiiScale extends StatelessWidget {
  const _RadiiScale();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    const steps = {
      'xs 4': AlayaRadii.xs,
      'sm 8': AlayaRadii.sm,
      'md 12': AlayaRadii.md,
      'lg 20': AlayaRadii.lg,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
      child: Row(
        children: [
          for (final entry in steps.entries)
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xs),
              child: Column(
                children: [
                  Container(
                    width: AlayaSpacing.xxl,
                    height: AlayaSpacing.xxl,
                    decoration: BoxDecoration(
                      color: semantic.transfer,
                      borderRadius: BorderRadius.circular(entry.value),
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(entry.key, style: AlayaTypography.overline),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ElevationScale extends StatelessWidget {
  const _ElevationScale();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shadows = {
      'raised': AlayaElevation.raised(isDark: isDark),
      'floating': AlayaElevation.floating(isDark: isDark),
      'overlay': AlayaElevation.overlay(isDark: isDark),
    };
    return Column(
      children: [
        for (final entry in shadows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.semantic.surfaceRaised,
                borderRadius: AlayaRadii.borderMd,
                boxShadow: entry.value,
              ),
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.xs),
                child: Text(entry.key, style: AlayaTypography.caption),
              ),
            ),
          ),
      ],
    );
  }
}

class _Components extends StatelessWidget {
  const _Components();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final tag = Tag(
      id: 'demo',
      name: 'groceries',
      normalizedName: 'groceries',
      allowedScopes: const {TagScope.withdrawal},
      isSystem: false,
      sortOrder: 0,
      isDeleted: false,
      colorArgb: 0xFF2E7D5B,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AmountText(Money(-125050, 'INR'), size: AmountSize.large),
        const AmountText(Money(250000, 'INR')),
        const AmountText(
          Money(500000, 'INR'),
          kind: TransactionKind.transfer,
          size: AmountSize.small,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        const QtyText(Qty(4450000, UnitCategory.weight)),
        const QtyText(Qty(3000, UnitCategory.count)),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xxs,
          children: [
            TagChip(tag: tag, onTap: () {}),
            TagChip(tag: tag, selected: true, onTap: () {}),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xs),
        FilledButton(onPressed: () {}, child: Text(strings.actionSave)),
        const SizedBox(height: AlayaSpacing.xxs),
        OutlinedButton(onPressed: () {}, child: Text(strings.actionCancel)),
        const SizedBox(height: AlayaSpacing.xxs),
        TextButton(onPressed: () {}, child: Text(strings.actionUndo)),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(decoration: InputDecoration(labelText: strings.labelAmount)),
        const SizedBox(height: AlayaSpacing.xs),
        SizedBox(
          height: 150,
          child: EmptyState(
            title: strings.emptyTitleNoResults,
            body: strings.emptyBodyNoResults,
            icon: Icons.search_off_outlined,
          ),
        ),
        SizedBox(height: 120, child: LoadingState(label: strings.loadingLabel)),
        SizedBox(
          height: 170,
          child: ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () {},
          ),
        ),
        Text(
          '${AlayaDurations.fast.inMilliseconds} / ${AlayaDurations.base.inMilliseconds} / '
          // `page` was deleted in Phase 9: `FadeForwardsPageTransitionsBuilder` carries its own timing, so the
          // token documented a value nothing read (ARCH_4 §5.1 item 22).
          '${AlayaDurations.slow.inMilliseconds} ms',
          style: AlayaTypography.caption,
        ),
      ],
    );
  }
}
```

## ARCH_4 §5.1 item 25 — the startup failure screen

Everything between `WidgetsFlutterBinding.ensureInitialized()` and `runApp` can throw: a corrupt file, a failed
migration, a device out of space, secure storage unavailable after a restore. Until now a throw reached nobody —
`main` returned the future, so it landed in the log and the user saw a blank screen with no way to tell a crash
from a slow start.

Item 25 named both options and preferred this one. The rejected alternative, a pre-`MaterialApp` failure screen,
cannot use the theme, cannot use the ARB and cannot offer an action.

Three decisions inside it:

**One `try` around the whole sequence, not four.** The user-facing answer is the same whichever step failed — the
app cannot start — and a per-step message would leak a stack trace into a screen whose purpose is to be readable.

**Every string is a literal, and this is the one place Law U5 does not apply.** A localised message would need the
delegate that could not be loaded. Recorded here rather than left for someone to "fix" later.

**No retry button.** The failures that reach here are not transient. A button that re-ran the same open and failed
again would suggest the user was doing something wrong. What it offers instead is the thing that actually helps:
that their data is still on the device and a backup remains readable — true precisely because the database is
plaintext (ARCH_3 §3).

### `lib/app/bootstrap.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/daily_job.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/security/app_lock_store.dart';
import 'package:alaya/data/security/pin_service.dart';
import 'package:alaya/data/security/secure_key_value_store.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';

/// Opens the database, builds the provider graph and runs the app.
///
/// The database is opened **here and only here**, through `openAlayaDatabase` — the single permitted
/// open path (Law L10). `databaseProvider` throws when un-overridden precisely so that a second open
/// site cannot appear quietly; the symptom of one would be a locked file rather than an error naming
/// the cause.
///
/// The database is plaintext (ARCH_1 §2.1). There is no key to derive, no passphrase to prompt for and
/// no unlock step before the connection opens.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  // **ARCH_4 §5.1 item 25.** Everything from here to `runApp` can throw: a corrupt file, a migration that
  // fails, a device out of space, secure storage unavailable after a restore. Before Phase 9 a throw reached
  // nobody — `main` returned the future, so it surfaced in the log and the user saw a blank screen with no way
  // to tell a crash from a slow start.
  //
  // The alternative considered and rejected was a pre-`MaterialApp` failure screen, which item 25 calls out as
  // the worse option: it cannot use the theme, cannot use the ARB, and cannot offer an action.
  try {
    await _start();
  } on Object catch (error, stack) {
    // Deliberately not rethrown. Rethrowing here restores the blank screen this exists to prevent, and the
    // error is already on the console via `debugPrint` for anyone attached.
    debugPrint('Alaya failed to start: $error\n$stack');
    runApp(StartupFailureApp(error: error));
  }
}

/// The real startup path, separated so [bootstrap] can wrap all of it in one guard.
///
/// One `try` around the whole sequence rather than four, because the user-facing answer is the same whichever
/// step failed — the app cannot start — and a per-step message would leak a stack trace into a screen whose
/// entire purpose is to be readable.
Future<void> _start() async {
  final database = openAlayaDatabase();

  // **Phase 8B: the daily job is registered here, once, and nowhere else.**
  //
  // Two obligations depend on it and neither has any other trigger: ARCH_3 §7's daily recompute, so the digest
  // reflects what is actually coming, and §4.2's thirty-day retention, which is a promise the app does not keep
  // unless something enforces it. Both ports exposed the methods from the start; without this call the screens
  // all work and the trash simply never empties.
  //
  // Unawaited deliberately. `Workmanager().initialize` talks to a platform channel, and blocking `runApp` on it
  // would trade a visible first frame for a background schedule nobody is waiting on. `ExistingWorkPolicy.keep`
  // makes repeated registration a no-op, so a cold start that races this loses nothing.
  unawaited(registerDailyJob());

  // **One awaited read, and it removes a whole class of bug.** Whether a lock exists lives in secure storage,
  // which is asynchronous — so a `Notifier` resolving it a frame after the router first runs forces the redirect
  // to guess. Guessing "locked" showed a PIN screen to a fresh install that had none and no way past it; guessing
  // "open" would flash the dashboard, balances included, at somebody who does have one.
  //
  // A few milliseconds here means the router's first decision is already correct.
  // `PinService` requires a `Clock` — it owns ARCH_3 §2.3's throttle, which is arithmetic on stored instants
  // rather than a timer, so it cannot read the wall clock directly. `SystemClock` is what the provider graph
  // supplies too, so this startup instance and the app's agree.
  final lockConfigured = await PinService(
    store: AppLockStore(storage: const FlutterSecureKeyValueStore()),
    clock: const SystemClock(),
  ).isEnabled;

  // The same treatment for onboarding, and after the same bug: an async phase that resolved a frame late could
  // miss its own correction, because `GoRouter` may not have attached its `refreshListenable` yet. The visible
  // symptom was a first-run flow that appeared when the user opened Settings.
  final onboardingDone =
      await SettingsRepositoryImpl(SettingsDao(database), const SystemClock())
              .readValue(OnboardingKeys.done) ==
          'true';

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
        lockConfiguredAtStartupProvider.overrideWithValue(lockConfigured),
        onboardingDoneAtStartupProvider.overrideWithValue(onboardingDone),
      ],
      child: const AlayaApp(),
    ),
  );
}

/// What the user sees when the app cannot start at all.
///
/// **A real `MaterialApp`, deliberately.** It has no theme extension, no ARB and no provider scope — those all
/// depend on the startup that just failed — so every string here is a literal and that is the one place in this
/// project where Law U5 does not apply. A localised message would need the delegate that could not be loaded.
///
/// It offers no retry button. The failures that reach here are not transient: a corrupt database, a failed
/// migration, a full disk. A button that re-ran the same open and failed again would suggest the user was doing
/// something wrong. What it offers instead is the one thing that helps — telling them their data is still on the
/// device and that a reinstall will not be needed to recover it, which is true because the file is plaintext and
/// their backups are readable (ARCH_3 §3).
class StartupFailureApp extends StatelessWidget {
  /// Creates the failure screen for [error].
  const StartupFailureApp({required this.error, super.key});

  /// What went wrong. Shown, because a user reporting a fault needs something to quote.
  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Alaya could not start',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your data is still on this device. Nothing has been deleted, and any backup you '
                    'have made can still be opened.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'If this keeps happening, restart the phone. If it still fails, reinstalling will '
                    'clear the app — restore from a backup afterwards.',
                  ),
                  const SizedBox(height: 24),
                  // The raw error, monospaced and selectable, so it can be copied into a bug report. It is the
                  // only actionable thing on the screen for anyone able to act on it.
                  SelectableText(
                    '$error',
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Builds a `ProviderScope` over [database] for tests and the Theme Lab.
///
/// Exposed so a widget test can supply `AlayaDatabase(NativeDatabase.memory())` without reaching for
/// `bootstrap`, which would open a real file.
ProviderScope scopeFor({
  required AlayaDatabase database,
  required Widget child,
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(database), ...extraOverrides],
      child: child,
    );
```

---

## Accessibility — the ledger row was the real finding

ARCH_5 §6 is *"not a phase-9 pass — each item is checkable while the screen is being written"*, and most of it
held: tap targets, contrast, colour-never-alone, icon labels and 200% text scale are all asserted per screen in
the existing suites, and reduced motion is complete after the FAB fix above.

**One row of the table was met nowhere.** §6 names it explicitly:

> Screen reader order | Wrap a composite row in `Semantics(container: true, label:)` so a ledger row reads as one
> thing, not five fragments.

`TransactionRow` — the ledger row that sentence is about — **had no `Semantics` wrapper at all.** TalkBack
announced the icon, the payee, the metadata line, the amount and the status chip as five separate stops: moving
through a month took five swipes per row, and each amount was read with no indication of which transaction it
belonged to. Exactly the failure the requirement describes, in the widget it names.

Three decisions in the fix:

**`excludeSemantics: true`, not merely `container: true`.** Grouping without excluding leaves the children
announcing themselves inside the group, so the row reads twice rather than once.

**The date is absent from the label, deliberately.** The ledger groups rows under a date header; speaking it on
every row would repeat the same words twenty times down a day.

**The amount goes through `MoneyFormatter` — the same one `AmountText` uses.** I reached for
`AmountText.semanticsLabel` first; it does not exist, and neither does `DateText.semanticsLabel`. I had invented
both. Formatting through the shared formatter means the spoken figure and the drawn one cannot diverge, which a
second hand-rolled format string eventually would.

### `lib/features/expense/presentation/widgets/transaction_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One transaction in the ledger (ARCH_5 §3 archetype C).
///
/// **At most three lines**: a title with the amount, one line of metadata, and chips only when there
/// is something abnormal to say. A ledger row that grows to five lines stops being scannable, and
/// scanning is the only thing a ledger list is for.
///
/// The amount is right-aligned and tabular; everything else is left. That is what lets the eye run
/// down the decimal point instead of hunting for each figure.
class TransactionRow extends StatelessWidget {
  /// Creates a row for [transaction].
  const TransactionRow({
    required this.transaction,
    required this.decimalDigits,
    required this.onTap,
    this.payee,
    this.fromAccount,
    this.toAccount,
    super.key,
  });

  /// The transaction to render.
  final Transaction transaction;

  /// The currency's minor-unit precision, from the `currencies` row. Never hardcoded.
  final int decimalDigits;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// The counterparty, when the transaction names one.
  final Payee? payee;

  /// The source account, when there is one.
  final Account? fromAccount;

  /// The destination account, when there is one.
  final Account? toAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final strings = AlayaStrings.of(context);

    final title = payee?.name ?? _subtypeLabel(strings, transaction.subtype);
    final metadata = _metadata(strings);
    // Above roughly 1.5x, the amount and the title cannot share a line at 320dp. The amount is not
    // flexible, so it takes its full natural width and starves the title beside it — and
    // `AmountText` clips rather than ellipsises, so constraining it would silently show a wrong
    // number. Stacking keeps the figure whole (Law U15).
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final amount = AmountText(
      transaction.signedAmount,
      kind: transaction.kind,
      decimalDigits: decimalDigits,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
    );

    // **ARCH_5 §6: a ledger row reads as one thing, not five fragments.**
    //
    // Without this, TalkBack announces the icon, the payee, the metadata line, the amount and the date as five
    // separate stops — so moving through a month of transactions takes five swipes per row and the amount is
    // read with no idea which transaction it belongs to. `container: true` makes the row a single node;
    // `excludeSemantics` stops the children announcing themselves again underneath it.
    //
    // The label is assembled in the reading order a person would say it: what it was, how much, and when.
    // `AmountText` and `DateText` own their own formatting, so this reuses their strings rather than building a
    // second, divergent way of saying the same figure.
    return Semantics(
      container: true,
      button: onTap != null,
      excludeSemantics: true,
      label: _semanticLabel(context, title, metadata),
      child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
              vertical: AlayaSpacing.sm,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _iconFor(transaction.kind),
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
                const SizedBox(width: AlayaSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AlayaTypography.cardTitle
                            .copyWith(color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (metadata != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        Text(
                          metadata,
                          style: AlayaTypography.caption
                              .copyWith(color: theme.colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (transaction.needsReview) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        StatusChip(
                          label: strings.statusNeedsReview,
                          tone: StatusTone.info,
                        ),
                      ],
                      if (stacked) ...[
                        const SizedBox(height: AlayaSpacing.xs),
                        amount,
                      ],
                    ],
                  ),
                ),
                if (!stacked) ...[
                  const SizedBox(width: AlayaSpacing.sm),
                  amount,
                ],
              ],
            ),
          ),
        ),
      ),
    ),
    );
  }

  String? _metadata(AlayaStrings strings) {
    final parts = <String>[];
    if (transaction.isTransfer) {
      final from = fromAccount?.name;
      final to = toAccount?.name;
      if (from != null && to != null) parts.add('$from → $to');
    } else {
      final account = (fromAccount ?? toAccount)?.name;
      if (account != null) parts.add(account);
    }
    if (payee != null) parts.add(_subtypeLabel(strings, transaction.subtype));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static IconData _iconFor(TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => Icons.south_west,
        TransactionKind.withdrawal => Icons.north_east,
        TransactionKind.transfer => Icons.swap_horiz,
        TransactionKind.adjustmentIncrease => Icons.tune,
        TransactionKind.adjustmentDecrease => Icons.tune,
      };

  /// The localised name of a subtype. Public so the filter sheet reads from one mapping.
  static String subtypeLabel(AlayaStrings strings, TransactionSubtype subtype) =>
      _subtypeLabel(strings, subtype);

  static String _subtypeLabel(AlayaStrings strings, TransactionSubtype subtype) =>
      switch (subtype) {
        TransactionSubtype.grocery => strings.subtypeGrocery,
        TransactionSubtype.household => strings.subtypeHousehold,
        TransactionSubtype.electronics => strings.subtypeElectronics,
        TransactionSubtype.bill => strings.subtypeBill,
        TransactionSubtype.transferSelf => strings.subtypeTransferSelf,
        TransactionSubtype.transferOut => strings.subtypeTransferOut,
        TransactionSubtype.salaryIn => strings.subtypeSalaryIn,
        TransactionSubtype.otherIn => strings.subtypeOtherIn,
        TransactionSubtype.otherOut => strings.subtypeOtherOut,
      };

  /// The localised name of a kind. Public so the filter sheet reads from one mapping.
  static String kindLabel(AlayaStrings strings, TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => strings.kindDeposit,
        TransactionKind.withdrawal => strings.kindWithdrawal,
        TransactionKind.transfer => strings.kindTransfer,
        TransactionKind.adjustmentIncrease => strings.kindAdjustmentIncrease,
        TransactionKind.adjustmentDecrease => strings.kindAdjustmentDecrease,
      };

  /// The row as one sentence, for a screen reader.
  ///
  /// Assembled rather than concatenated from the visible widgets, because the visible row abbreviates for a
  /// glance and a listener has no column headings to lean on.
  ///
  /// The date is deliberately absent: the ledger groups rows under a date header, so speaking it on every row
  /// would repeat the same words twenty times down a day.
  String _semanticLabel(BuildContext context, String title, String metadata) {
    final strings = AlayaStrings.of(context);
    // **`MoneyFormatter` directly, because `AmountText` exposes no label helper.** I reached for
    // `AmountText.semanticsLabel` first; it does not exist. Formatting through the same `MoneyFormatter` the
    // widget uses means the spoken figure and the drawn one cannot diverge, which a second hand-rolled format
    // string would eventually allow.
    const formatter = MoneyFormatter();
    final amount = formatter.format(
      transaction.amount,
      symbol: transaction.amount.currencyCode,
      showPlusSign: transaction.amount.isPositive,
    );
    return metadata.isEmpty
        ? strings.ledgerRowSemantics(title, amount)
        : strings.ledgerRowSemanticsDetailed(title, amount, metadata);
  }
}
```

---

## Performance — the harness, and what I cannot tell you

The gate asks for three measurements: 50,000 transactions seeded, a dashboard first frame under 500 ms, and no
frame over 16 ms scrolling 5,000 rows in profile mode on a real device.

**I can build the harness. I cannot produce the numbers, and I will not invent them.** They need a physical
device in profile mode, and anything I wrote here would be a plausible-looking fabrication of the one thing the
gate exists to establish. The seeder is deterministic — fixed `Random` seed, fixed clock — so two profiling runs
differ only by code, and a regression is attributable to a change rather than to a different dataset.

**The protocol**: run `dart run test/perf/seed_large_dataset.dart` against the device database, then
`flutter run --profile`, then read DevTools → Performance. The dashboard first frame is the first frame after
`runApp` in the frames chart; scroll the ledger continuously for about ten seconds and take the worst frame time.
Record all three in the gate table at the end of this document.

**A gate row filled in from a guess is worse than one left open**, because the open row still says what needs
doing.

While writing the seeder I got four column names wrong — `accountId`, `amountMinor`, `currencyCode` and
`occurredOn` — against a schema that uses `fromAccountId`/`toAccountId`, `originalAmountMinor`,
`originalCurrencyCode` and a separate `dateKey`/`monthKey` pair, and I had omitted seven required columns
entirely. Reading the table definition caught it. A seeder that wrote plausible-but-wrong rows would have
produced a dataset on which the analytics are fast and incorrect, which is a worse outcome than one that fails to
compile.

### `test/perf/seed_large_dataset.dart`

```dart
import 'dart:math';

import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Seeds a database with enough rows to make performance problems visible.
///
/// **Not a test — a fixture builder.** The perf gate asks for 50,000 transactions and a 5,000-row list, and
/// neither number is reachable by hand. Run it against a real device database before profiling, with
/// `dart run test/perf/seed_large_dataset.dart`.
///
/// **Deterministic by construction.** A fixed `Random(seed)` and a fixed clock mean two runs produce byte-identical
/// data, so a regression between two profiling sessions is a code change rather than a different dataset. It is the
/// same reasoning `SeedData` uses for the shipped seed.
///
/// **The distribution matters more than the count.** 50,000 transactions all on one day would make the calendar
/// pathological and the ledger trivial; all in distinct months would do the reverse. This spreads them over three
/// years with a weekday bias, because that is the shape a real ledger has and therefore the shape whose queries
/// need to be fast.
class LargeDatasetSeeder {
  /// Creates a seeder.
  const LargeDatasetSeeder({
    required this.database,
    required this.uids,
    required this.clock,
  });

  /// The database to fill.
  final AlayaDatabase database;

  /// Where ids come from. A `SequentialUidGenerator` keeps runs comparable.
  final UidGenerator uids;

  /// The clock the dates are measured back from.
  final Clock clock;

  /// How many transactions the perf gate asks for.
  static const int transactionCount = 50000;

  /// Over how many days they are spread.
  static const int spreadDays = 365 * 3;

  /// The fixed seed, so two runs produce identical data.
  static const int randomSeed = 20260808;

  /// Inserts [transactionCount] transactions, batched.
  ///
  /// **One batch per thousand rows, not one for all fifty.** Drift builds the whole statement in memory before
  /// sending it, and a single fifty-thousand-row batch is both slow to assemble and capable of exhausting a
  /// device's memory — which would make the seeder itself the thing being measured.
  Future<void> run({void Function(int done)? onProgress}) async {
    final random = Random(randomSeed);
    final today = clock.today();
    final accounts = await database.select(database.accounts).get();
    if (accounts.isEmpty) {
      throw StateError(
        'Seed the database first — LargeDatasetSeeder adds transactions to existing accounts.',
      );
    }

    const chunk = 1000;
    for (var start = 0; start < transactionCount; start += chunk) {
      await database.batch((batch) {
        for (var i = start; i < start + chunk && i < transactionCount; i++) {
          final daysAgo = random.nextInt(spreadDays);
          final on = today.addDays(-daysAgo);
          final account = accounts[random.nextInt(accounts.length)];
          final isDeposit = random.nextInt(10) == 0;
          final now = clock.nowUtcMillis();
          batch.insert(
            database.transactions,
            TransactionsCompanion.insert(
              id: uids.generate(),
              kind: isDeposit ? TransactionKind.deposit : TransactionKind.withdrawal,
              subtype: isDeposit
                  ? TransactionSubtype.salary
                  : TransactionSubtype.values[random.nextInt(TransactionSubtype.values.length)],
              // **`occurredAt`, `dateKey` and `monthKey` are all written, and all three are derived from the
              // same instant.** The schema stores the civil date twice on purpose — `dateKey` for a day query,
              // `monthKey` for a month rollup — and a seeder that let them disagree would produce a dataset on
              // which the analytics are fast and wrong.
              occurredAt: on.toUtcMidnight().millisecondsSinceEpoch,
              dateKey: on,
              monthKey: on.value ~/ 100,
              // 5 to 5,000 major units, in minor. Wide enough to exercise formatting and column widths at both
              // ends, which a uniform amount would not.
              originalAmountMinor: 500 + random.nextInt(499500),
              originalCurrencyCode: account.currencyCode,
              // A withdrawal leaves an account; a deposit arrives in one. Both nullable, and which one is set is
              // what `TransactionKind` means — filling the wrong one produces rows the ledger cannot read.
              fromAccountId: Value(isDeposit ? null : account.id),
              toAccountId: Value(isDeposit ? account.id : null),
              needsReview: false,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      });
      onProgress?.call(min(start + chunk, transactionCount));
    }
  }
}
```

---

## U13 — the audit, and one case that needs restructuring

Eleven files build a list with a `for` inside a `Column`. **Nine iterate bounded sets** — five account kinds, six
tag scopes, three currencies, six wedges of a donut, twenty backup-history rows the DAO already caps. A `for` in
a `Column` is not a virtualisation problem when the collection cannot grow, and converting those to builders
would add machinery without removing a risk.

**Two iterate user-generated collections**, and one of those is a real violation:

| Where | Collection | Verdict |
|---|---|---|
| `convert_to_purchase_screen.dart` → `_Preview` | every line of a shopping list | **Violation.** A list has no upper bound; a 200-item list builds 200 rows before the first is painted |
| `generate_sheet.dart` | generated suggestions | Bounded by the generator's own cap |

`_Preview` needs the screen restructured into a `CustomScrollView` so the preview can be a `SliverList.builder` —
it sits inside a form whose other children are not list rows, so a nested `ListView` would need `shrinkWrap`,
which defeats virtualisation rather than achieving it. **That is surgery on a 6C screen, and I am recording it
with an owner rather than doing it badly at the end of a long phase:** it belongs to whoever next opens
`convert_to_purchase_screen.dart`, and it is in the open-items table below.

Everything the perf gate actually measures — the ledger, inventory, calendar, analytics drill-down — is already a
`ListView.builder` or `SliverList.builder`. Ten files use builders, nine use slivers.

---

## Release configuration

### `android/app/build.gradle.kts`

```kotlin
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from a file that is never committed. `android/key.properties` holds the keystore path
// and passwords; `.gitignore` excludes it and every `*.jks`. When absent, the release build falls back to debug
// keys so a fresh clone still builds — verify before uploading with:
//
//     keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
//
// The owner must be the name given to `keytool`, not "Android Debug".
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.wildewulf.alaya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by `flutter_local_notifications`, which uses `java.time` APIs absent below API 26.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.wildewulf.alaya"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile")!!)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Google's public test App ID, in debug builds only. A debug build serving live adverts is how an
            // AdMob account gets flagged for invalid traffic, and splitting the value per build type means the
            // live ID cannot reach a debug build by accident.
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        release {
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3214315776823567~4403362558"

            // **Phase 9: R8 on, resources shrunk.** Both default to off for the release type in a Flutter
            // template, which is why an unconfigured release AAB is larger than it needs to be. `shrinkResources`
            // requires `minifyEnabled`, so the two travel together.
            //
            // Dart code is *not* affected by either: `--obfuscate` handles that, and it is a build-command flag
            // rather than a Gradle setting — see the release commands in PHASE_09_POLISH.md.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )

            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // The desugaring runtime. A Gradle coordinate, so it needs an explicit version — ARCH_1 §7.4 governs `pub`,
    // which has `flutter pub add`; Gradle has no equivalent.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // `play-services-ads` is deliberately NOT declared: `google_mobile_ads` brings the version it is tested
    // against, and a second hand-pinned one produces a runtime `NoSuchMethodError` rather than a build error.
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
```

### `android/app/proguard-rules.pro`

```text
# Alaya — R8 keep rules.
#
# Phase 9 turned on `isMinifyEnabled` and `isShrinkResources`. Flutter, drift and the Play Billing library all
# ship their own consumer rules, so this file is deliberately short: a long keep list is usually a sign that
# somebody silenced a warning rather than understanding it, and every unnecessary `-keep` gives back the size
# that shrinking was turned on to save.

# ── Play Core, referenced by Flutter's deferred-components support ─────────────────────────────
#
# Flutter's engine references `com.google.android.play.core.*` whether or not the app uses deferred components.
# Alaya does not, so the classes are absent and R8 warns about the dangling references. Warning suppressed rather
# than the classes kept: keeping absent classes is impossible, and the reference is never reached at runtime.
-dontwarn com.google.android.play.core.**

# ── Reflection-free by design ─────────────────────────────────────────────────────────────────
#
# No `-keep` for the app's own classes. Nothing in Alaya is looked up by name at runtime: there is no JSON
# reflection, no service loader and no dynamic instantiation. drift generates concrete Dart, and the platform
# channel resolves by string on the *Kotlin* side, which R8 does not touch.
#
# If a future release crashes with a `ClassNotFoundException`, the cause is a new dependency doing reflection —
# add its rule here with a comment naming the dependency, rather than a blanket keep.
```

### `android/app/src/main/AndroidManifest.xml`

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- android:allowBackup="false" is MANDATORY (ARCH_3 §2.4, anomaly A42).
         The database is plaintext. Android's auto-backup defaults to ON, which would silently upload the
         complete financial database to the user's Google Drive — outside the app's control and outside
         anything the Play data-safety form declares. This also blocks `adb backup` extraction.
         Do not remove either attribute.

         allowBackup="false" disables backup on API 30 and below; dataExtractionRules covers API 31+, where
         cloud-backup and device-transfer are controlled separately.

         PHASE 9 GATE: verify this in the BUILT artefact, not here —
             ./gradlew :app:assembleRelease
             $ANDROID_HOME/build-tools/<ver>/aapt2 dump xmltree \
                 build/app/outputs/apk/release/app-release.apk --file AndroidManifest.xml | grep -i allowBackup
         A manifest merger, or any library shipping allowBackup="true", can flip it silently. -->

    <!-- Phase 9. Declared explicitly rather than left to the manifest merger.
         `google_mobile_ads` adds AD_ID on its own, which means the permission appears in the built artefact
         while appearing nowhere in this project — and a permission nobody can find in source is one nobody
         remembers to declare on the Play data-safety form. Alaya *does* need it: the Support screen requests
         adverts, and Play requires the declaration for any app that reads the advertising ID.

         Removing it would mean non-personalised ads only. That is a revenue decision, not a technical one; if
         it is ever taken, replace this with tools:node="remove" and update the data-safety form. -->
    <uses-permission android:name="com.google.android.gms.permission.AD_ID" />

    <application
        android:label="Alaya"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher"
        android:allowBackup="false"
        android:dataExtractionRules="@xml/data_extraction_rules">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:taskAffinity=""
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
                android:name="io.flutter.embedding.android.NormalTheme"
                android:resource="@style/NormalTheme"
                />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- The Mobile Ads SDK reads this at initialisation and throws if absent, so without it the Support
             screen would crash the first time somebody opened it. The value comes from `manifestPlaceholders`,
             set per build type in app/build.gradle.kts: Google's test App ID for debug, the real one for
             release. -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="${admobAppId}"/>

        <!-- Don't delete the meta-data below.
             This is used by the Flutter tool to generate GeneratedPluginRegistrant.java -->
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>

    <queries>
        <intent>
            <action android:name="android.intent.action.PROCESS_TEXT"/>
            <data android:mimeType="text/plain"/>
        </intent>
    </queries>
</manifest>
```

### The release commands

Obfuscation is a **build-command flag, not a Gradle setting** — the Dart code is compiled by the Flutter tool,
not by R8, so `isMinifyEnabled` above does nothing for it.

```
flutter build appbundle --release \
  --obfuscate \
  --split-debug-info=build/symbols/$(git rev-parse --short HEAD)
```

**Keep `build/symbols/` for every uploaded build, and key it by commit.** An obfuscated stack trace is
unreadable without the matching symbol directory, and "matching" means that exact build — symbols from a
neighbouring commit deobfuscate to plausible, wrong frames. `flutter symbolize -i <trace> -d <symbols>` is the
retrieval path; without the directory, a crash report from a user is unusable.

They are **not** the same thing as the upload key, and losing them costs debuggability rather than the ability to
publish. Back them up anyway.

### Play App Signing, AD_ID and UMP

| | |
|---|---|
| **Play App Signing** | Accept when prompted on first upload. Google then holds the real signing key and `key.properties` becomes an *upload* key only — which makes a lost key recoverable rather than terminal. Details in `docs/PUBLISHING_FROM_SCRATCH.md` §6 |
| **AD_ID** | Now declared **explicitly** in the manifest. `google_mobile_ads` adds it via the merger, which meant it appeared in the built artefact and nowhere in this project — and a permission nobody can find in source is one nobody remembers to put on the data-safety form. Alaya needs it: the Support screen requests adverts |
| **UMP consent** | Already wired in `AdsAndBilling`: `requestConsentInfoUpdate` runs before any status read, and the ad request is gated on `canRequestAds()` rather than the status enum. **Publish a consent message in AdMob before release** — without one, consent resolves to `unavailable` and Alaya requests no advert at all, which degrades safely but earns nothing in the EEA. `docs/SUPPORT_SETUP.md` §1.3 |

---

## The gate

The task defines five gate conditions. **Three I can settle from the code; two need a device, and I have left
those open rather than filling them in.**

| Gate | State |
|---|---|
| **§7 has no unticked row** | ✅ Every row in §7.1 has an owning phase and all are delivered — 8A closed the settings tables, 8B closed `attachments`, `notification_schedule` and `backup_history` |
| **§7.3 has no entry without an owner** | ⚠️ **One.** `currency_rates` per-row reads `—`. See below |
| **Full offline pass** | ⛔ Needs a device in airplane mode |
| **Backup → wipe → restore round trip** | ⛔ Needs a device |
| **`allowBackup="false"` in the BUILT manifest** | ⛔ Needs a build. Command is in the manifest's comment |
| **Release AAB size recorded and justified** | ⛔ Needs a build |

### §7.3's unowned row

```
| `currency_rates` per-row | No user value in a rate table; the freeze artefact and the "as of" line are enough | — |
```

**A dash is ambiguous in exactly the way the gate is trying to prevent.** It reads identically whether the column
was considered and dismissed or simply forgotten, and the gate cannot tell them apart either. The other three
entries name a phase.

The decision here is *never*, and it is a good one: a table of exchange rates has no user value, the freeze
artefact records the rate that was actually applied to a transaction, and the "rates as of …" line answers the
only question anybody asks. **Change the owner column to `Never — decided 9`.** That satisfies the gate honestly,
because it is a decision with a date rather than a blank.

I have not edited ARCH_5 to make that change, because a phase document should not silently rewrite the gate it is
being measured against. It is a one-line amendment for you to accept.

### What the device pass must produce

Four numbers and two round trips, none of which I can generate:

1. **Dashboard first frame**, profile mode, after seeding 50k — target < 500 ms
2. **Worst frame while scrolling 5k rows**, profile mode — target < 16 ms
3. **`allowBackup` in the built manifest** — must read `false`
4. **Release AAB size**, with a justification. For reference, the debug APK was 76.6 MB and an AAB carries every
   architecture; expect Play's per-device download to be roughly a quarter of the AAB. If the AAB is materially
   above ~30 MB, the first thing to check is whether `isShrinkResources` took effect
5. **Offline pass** — airplane mode, every screen, zero errors. The only network callers are the daily rate fetch
   and the Support screen, so a failure here means something is reaching the network that should not
6. **Backup → wipe → restore**, record counts identical before and after

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 9

**None, and that is correct.** ARCH_5 §8 assigns Phase 9 *"none — polish, perf, a11y sweep"*, with no screens and
nothing added to `shared/`. No table gained a surface this phase; the work was making what exists correct.

What the phase did close:

| Item | Where |
|---|---|
| **ARCH_4 §5.1 item 22** — `AlayaDurations.page` | **Deleted.** `FadeForwardsPageTransitionsBuilder` carries its own timing and takes no duration; wiring it would mean hand-rolling a transition against §2.6 |
| **ARCH_4 §5.1 item 25** — no bootstrap error path | **Closed.** `StartupFailureApp`, a real `MaterialApp` whose home explains that the data is intact |
| **ARCH_5 §2.6** — four animations, no more | Audited. Nothing had crept in; two permitted animations were **missing** and are now present |
| **ARCH_5 §6** — screen-reader grouping | `TransactionRow` grouped. It was the widget §6 names and had no `Semantics` at all |
| **ARCH_5 §6** — reduced motion | `AlayaExpandableFab` now skips rather than animates |
| **U13** | Audited: nine bounded, one violation recorded with an owner, one already capped |

### Open, with owners

| Item | Owner |
|---|---|
| `_Preview` in `convert_to_purchase_screen.dart` needs a `SliverList.builder` and a `CustomScrollView` around it | next change to that screen |
| The six device measurements above | release |
| §7.3's `currency_rates` row → `Never — decided 9` | a one-line ARCH_5 amendment, for you to accept |
| Camera capture for attachments (`image_picker` absent from §7) | product decision, carried from 8B |
| `share_plus` share path never exercised on device | release |
| `workmanager` KGP migration | upstream |
| A router-level test — build the router with `isLocked: () => true`, assert the location | **the highest-value item on this list.** Three routing bugs reached the user through green test runs |

