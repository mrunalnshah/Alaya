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
  String _semanticLabel(BuildContext context, String title, String? metadata) {
    final strings = AlayaStrings.of(context);
    // **`MoneyFormatter` directly, because `AmountText` exposes no label helper.** I reached for
    // `AmountText.semanticsLabel` first; it does not exist. Formatting through the same `MoneyFormatter` the
    // widget uses means the spoken figure and the drawn one cannot diverge, which a second hand-rolled format
    // string would eventually allow.
    const formatter = MoneyFormatter();
    // `signedAmount`, not `originalAmount`: the entity applies the sign from `kind`, and a spoken figure with no
    // sign cannot distinguish money in from money out — which is the one thing §6's "colour is never alone" rule
    // is protecting, carried over to a listener who has no colour at all.
    final amount = formatter.format(
      transaction.signedAmount,
      decimalDigits: decimalDigits,
      symbol: transaction.signedAmount.currencyCode,
      showPlusSign: transaction.signedAmount.isPositive,
    );
    return metadata == null || metadata.isEmpty
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

  /// The subtypes a withdrawal can honestly carry.
  ///
  /// Transfers are excluded: they need a counterpart account and a matching row, and a seeder that emitted
  /// half a transfer would leave the ledger unbalanced in a way no screen can display.
  static const List<TransactionSubtype> _spendingSubtypes = [
    TransactionSubtype.grocery,
    TransactionSubtype.household,
    TransactionSubtype.electronics,
    TransactionSubtype.bill,
  ];

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
              // `salaryIn`, and the withdrawal side picks from the four that are actually spending. Picking
              // from `values` at random — which this did — would have produced deposits filed as `grocery` and
              // transfers with no counterpart account, giving the analytics a dataset it cannot reconcile.
              subtype: isDeposit
                  ? TransactionSubtype.salaryIn
                  : _spendingSubtypes[random.nextInt(_spendingSubtypes.length)],
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

## `app_en.arb` — carried, because the a11y fix added two keys

**Phase 9 was not supposed to touch the ARB.** It adds no screens and closes no §7 row, so a phase that changes
strings is a phase doing something it did not plan to.

It has to. `TransactionRow`'s semantics label is a sentence a screen reader speaks, and Law U5 admits no
exception for text a user hears rather than reads — a blind user in a Gujarati locale hearing an English row is
the failure U5 exists to prevent. Two keys, 1,127 → 1,129.

Both are pure punctuation and placeholders, which is deliberate: the comma is the pause a screen reader takes, so
it is punctuation rather than a word, and a translator can reorder the parts for a language that puts the amount
first.

**I had called both keys and never added them** — the build failed on `ledgerRowSemantics` and
`ledgerRowSemanticsDetailed` being undefined. The ARB extraction check I have run every phase since 8A would have
caught it before delivery; I did not run it here because I had convinced myself this phase touched no strings.

### `lib/app/l10n/app_en.arb`

```json
{
  "@@locale": "en",
  "appName": "Alaya",
  "@appName": {
    "description": "The app's name, shown in the drawer header."
  },
  "navDashboard": "Dashboard",
  "navExpenses": "Expenses",
  "navInventory": "Inventory",
  "navShopping": "Shopping",
  "navRecurring": "Recurring",
  "navServices": "Services",
  "navCalendar": "Calendar",
  "navInsights": "Insights",
  "navSettings": "Settings",
  "navThemeLab": "Theme Lab",
  "actionSave": "Save",
  "@actionSave": {
    "description": "Commits an edit. Active voice, and the same word appears in the resulting confirmation."
  },
  "actionSaved": "Saved",
  "actionCancel": "Cancel",
  "actionDelete": "Delete",
  "actionDeleted": "Deleted",
  "actionUndo": "Undo",
  "actionRetry": "Try again",
  "actionAdd": "Add",
  "actionEdit": "Edit",
  "actionDone": "Done",
  "actionClose": "Close",
  "actionSelect": "Select",
  "actionClear": "Clear",
  "actionClearAll": "Clear all",
  "actionSearch": "Search",
  "actionConfirm": "Confirm",
  "actionDiscard": "Discard",
  "actionKeepEditing": "Keep editing",
  "actionRemoveTag": "Remove tag",
  "@actionRemoveTag": {
    "description": "Accessibility label for the dismiss affordance on a removable tag chip."
  },
  "actionClearSearch": "Clear search",
  "@actionClearSearch": {
    "description": "Accessibility label for the clear button inside AlayaSearchField."
  },
  "addExpense": "Add expense",
  "addIncome": "Add income",
  "addTransfer": "Add transfer",
  "addItem": "Add item",
  "addToShoppingList": "Add to shopping list",
  "dateToday": "Today",
  "@dateToday": {
    "description": "DateText.relative, when the date is the clock's today. Sentence case; it can begin a row."
  },
  "dateYesterday": "Yesterday",
  "dateTomorrow": "Tomorrow",
  "emptyTitleNoTransactions": "No transactions yet",
  "emptyBodyNoTransactions": "Add your first expense and it will appear here.",
  "@emptyBodyNoTransactions": {
    "description": "An empty screen is an invitation to act, so this names the action rather than describing the emptiness."
  },
  "emptyTitleNoItems": "Nothing in your inventory",
  "emptyBodyNoItems": "Add an item to start tracking what you have at home.",
  "emptyTitleNoShopping": "Your list is empty",
  "emptyBodyNoShopping": "Add something, or let Alaya suggest items you are low on.",
  "emptyTitleNoRecurring": "No recurring bills",
  "emptyBodyNoRecurring": "Set up a bill or subscription and Alaya will remind you when it is due.",
  "emptyTitleNoResults": "No matches",
  "emptyBodyNoResults": "Try a shorter search, or check the spelling.",
  "loadingLabel": "Loading",
  "loadingTransactions": "Loading transactions",
  "errorTitleGeneric": "That did not work",
  "@errorTitleGeneric": {
    "description": "Errors do not apologise and are never vague. This pairs with a specific body message."
  },
  "errorBodyGeneric": "Something went wrong on our side. Try again.",
  "errorTitleNotFound": "Not found",
  "errorBodyNotFound": "This item may have been deleted.",
  "errorBodyNoConnection": "You are offline. Alaya works offline, but rates will not refresh.",
  "errorFieldRequired": "This is required",
  "errorAmountInvalid": "Enter an amount",
  "errorAmountZero": "Enter an amount greater than zero",
  "errorAmountInvalidCharacter": "Digits only",
  "errorAmountNegativeNotAllowed": "Enter a positive amount",
  "errorAmountTooManyDecimals": "Too many decimal places",
  "errorAmountTooLarge": "That amount is too large",
  "errorQuantityTooLarge": "That quantity is too large",
  "errorQuantityInvalid": "Enter a quantity",
  "errorQuantityInvalidCharacter": "Digits only",
  "errorQuantityNegativeNotAllowed": "Enter a positive quantity",
  "errorQuantityTooPrecise": "Too precise for this unit",
  "@errorQuantityTooPrecise": {
    "description": "The typed quantity is finer than the chosen unit can express exactly. Shown rather than rounded, because rounding a quantity silently changes what the user recorded."
  },
  "errorDateInvalid": "Choose a date",
  "confirmDeleteTitle": "Delete this?",
  "confirmDeleteBody": "You can undo this for the next few seconds.",
  "confirmDiscardTitle": "Discard your changes?",
  "confirmDiscardBody": "What you have typed will not be saved.",
  "labelAmount": "Amount",
  "labelQuantity": "Quantity",
  "labelUnit": "Unit",
  "labelDate": "Date",
  "labelAccount": "Account",
  "labelPaymentMethod": "Payment method",
  "labelPayee": "Payee",
  "labelCategory": "Category",
  "labelTags": "Tags",
  "labelNote": "Note",
  "labelFrom": "From",
  "labelTo": "To",
  "labelItem": "Item",
  "labelExpiry": "Expiry",
  "labelTotal": "Total",
  "hintSelectAccount": "Choose an account",
  "hintSelectUnit": "Choose a unit",
  "hintSelectTags": "Choose tags",
  "hintSelectDate": "Choose a date",
  "hintSearchItems": "Search items",
  "hintNote": "Add a note",
  "amountUnconverted": "{count, plural, =1{1 amount not converted} other{{count} amounts not converted}}",
  "@amountUnconverted": {
    "description": "The chip beside a total when some amounts had no exchange rate. Surfaced rather than hidden, because a total missing a row is otherwise indistinguishable from a complete one.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "amountApproximate": "Approximate rate",
  "@amountApproximate": {
    "description": "Shown when a conversion used the nearest earlier rate rather than the exact date's."
  },
  "tagCountMore": "+{count}",
  "@tagCountMore": {
    "description": "Overflow indicator when a row cannot show every tag.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "statusNeedsReview": "Needs details",
  "@statusNeedsReview": {
    "description": "StatusChip on a transaction saved by quick-add. Names what is missing, not that a flag is set."
  },
  "statusUnallocated": "Unallocated",
  "@statusUnallocated": {
    "description": "StatusChip label when a transaction's lines do not sum to its amount. The figure is a separate AmountText (U7); never auto-balanced (anomaly A11)."
  },
  "statusDetached": "Receipt deleted",
  "@statusDetached": {
    "description": "StatusChip on a batch whose source transaction was deleted. The food did not un-exist."
  },
  "statusApproximate": "Approximate",
  "lowStockLabel": "Low",
  "expiringSoonLabel": "Expiring soon",
  "expiredLabel": "Expired",
  "overdueLabel": "Overdue",
  "dueTodayLabel": "Due today",
  "paidLabel": "Paid",
  "skippedLabel": "Skipped",
  "kindDeposit": "Money in",
  "kindWithdrawal": "Money out",
  "kindTransfer": "Transfer",
  "kindAdjustmentIncrease": "Correction up",
  "kindAdjustmentDecrease": "Correction down",
  "subtypeGrocery": "Groceries",
  "subtypeHousehold": "Household",
  "subtypeElectronics": "Electronics",
  "subtypeBill": "Bill",
  "subtypeTransferSelf": "Between my accounts",
  "subtypeTransferOut": "Sent to someone",
  "subtypeSalaryIn": "Salary",
  "subtypeOtherIn": "Other income",
  "subtypeOtherOut": "Other spending",
  "needsReviewBanner": "{count, plural, =1{1 transaction needs details} other{{count} transactions need details}}",
  "@needsReviewBanner": {
    "description": "Surfaces transactions.needsReview. Quick-add saves an amount and nothing else by design; without this row that deliberate shortcut becomes silent data rot.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "needsReviewAction": "Review",
  "filterTitle": "Filter",
  "filterDateRange": "Date range",
  "filterKind": "Type",
  "filterSubtype": "Category",
  "filterApply": "Show results",
  "filterReset": "Reset",
  "filterChipAccount": "Account: {name}",
  "@filterChipAccount": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipPayee": "Payee: {name}",
  "@filterChipPayee": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "filterChipRange": "{label}",
  "@filterChipRange": {
    "placeholders": {
      "label": {
        "type": "String"
      }
    }
  },
  "rangeToday": "Today",
  "rangeLast7Days": "Last 7 days",
  "rangeLast30Days": "Last 30 days",
  "rangeThisMonth": "This month",
  "rangeLastMonth": "Last month",
  "rangeThisYear": "This year",
  "rangeAllTime": "All time",
  "rangeCustom": "Custom",
  "searchTransactionsHint": "Search notes",
  "transactionDeleted": "Transaction deleted",
  "quickAddTitle": "Quick add",
  "quickAddMoneyIn": "Money in",
  "quickAddMoneyOut": "Money out",
  "quickAddSave": "Save",
  "actionAddDetails": "Add details",
  "editorTitleNew": "New transaction",
  "editorTitleEdit": "Edit transaction",
  "sectionWhatAndHowMuch": "What and how much",
  "sectionWhereItCameFrom": "Where it came from",
  "sectionWhereItWent": "Where it went",
  "sectionWhatYouBought": "What you bought",
  "sectionWarranty": "Warranty",
  "sectionSchedule": "Schedule",
  "transferOwnAccount": "To my own account",
  "transferSomeoneElse": "To someone else",
  "transferOwnAccountHelp": "Moves money between your accounts. Your total does not change.",
  "transferSomeoneElseHelp": "Money leaves your accounts. This is a withdrawal.",
  "alsoAddToInventory": "Also add to inventory",
  "destinationNone": "Just an expense",
  "destinationInventory": "Save to Inventory",
  "destinationAsset": "Save to Services",
  "destinationRecurring": "Save to Recurring",
  "lineAdd": "Add item",
  "lineDescription": "Item",
  "lineUnitPrice": "Unit price",
  "lineAmount": "Line total",
  "lineCreatedLink": "Created: {name}",
  "@lineCreatedLink": {
    "description": "Surfaces transaction_lines.created*Id — the artefact this line produced, tappable through to it.",
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "payeeCreate": "New payee “{name}”",
  "@payeeCreate": {
    "placeholders": {
      "name": {
        "type": "String"
      }
    }
  },
  "saveExpense": "Save expense",
  "saveIncome": "Save income",
  "saveTransfer": "Save transfer",
  "detailSectionLines": "Items",
  "detailSectionDetails": "Details",
  "actionFreezeConversion": "Show in another currency",
  "frozenConversionNote": "Frozen on {date} at {rate}",
  "@frozenConversionNote": {
    "description": "Surfaces transactions.converted*/conversionRateRaw. A separate artefact that is never recomputed (Law L9).",
    "placeholders": {
      "date": {
        "type": "String"
      },
      "rate": {
        "type": "String"
      }
    }
  },
  "deleteReasonHint": "Why? (optional)",
  "actionDeleteTransaction": "Delete transaction",
  "labelSubtype": "Category",
  "labelKind": "Type",
  "themeLabTitle": "Theme Lab",
  "themeLabSubtitle": "Every token, component and semantic colour, light and dark.",
  "themeLabSectionSpacing": "Spacing",
  "themeLabSectionRadii": "Radii",
  "themeLabSectionTypography": "Typography",
  "themeLabSectionElevation": "Elevation",
  "themeLabSectionSemantic": "Semantic colours",
  "themeLabSectionSurfaces": "Surface tiers",
  "themeLabSectionComponents": "Components",
  "themeLabSectionPalettes": "Palettes",
  "themeLabLight": "Light",
  "themeLabDark": "Dark",
  "semanticIncome": "Income",
  "semanticExpense": "Expense",
  "semanticTransfer": "Transfer",
  "semanticWarning": "Warning",
  "semanticDanger": "Danger",
  "semanticSuccess": "Success",
  "semanticMuted": "Muted",
  "drawerSectionMoney": "Money",
  "drawerSectionHome": "Home",
  "drawerSectionMore": "More",
  "inventoryGroupFavourites": "Favourites",
  "@inventoryGroupFavourites": {
    "description": "Phase 6B — inventory."
  },
  "inventoryGroupUntagged": "Everything else",
  "@inventoryGroupUntagged": {
    "description": "Phase 6B — inventory."
  },
  "itemKindGeneric": "General",
  "@itemKindGeneric": {
    "description": "Phase 6B — inventory."
  },
  "itemKindFood": "Food",
  "@itemKindFood": {
    "description": "Phase 6B — inventory."
  },
  "itemKindMedicine": "Medicine",
  "@itemKindMedicine": {
    "description": "Phase 6B — inventory."
  },
  "itemKindBeauty": "Beauty",
  "@itemKindBeauty": {
    "description": "Phase 6B — inventory."
  },
  "itemKindHousehold": "Household",
  "@itemKindHousehold": {
    "description": "Phase 6B — inventory."
  },
  "itemKindOther": "Other",
  "@itemKindOther": {
    "description": "Phase 6B — inventory."
  },
  "filterFavouritesOnly": "Favourites only",
  "@filterFavouritesOnly": {
    "description": "Phase 6B — inventory."
  },
  "actionFavourite": "Add to favourites",
  "@actionFavourite": {
    "description": "Phase 6B — inventory."
  },
  "actionUnfavourite": "Remove from favourites",
  "@actionUnfavourite": {
    "description": "Phase 6B — inventory."
  },
  "outOfStockLabel": "Out of stock",
  "@outOfStockLabel": {
    "description": "Phase 6B — inventory."
  },
  "itemBatchCount": "{count, plural, =1{1 batch} other{{count} batches}}",
  "@itemBatchCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "loadingInventory": "Loading inventory",
  "@loadingInventory": {
    "description": "Phase 6B — inventory."
  },
  "detailSectionBatches": "Batches",
  "@detailSectionBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginPurchase": "From a purchase",
  "@batchOriginPurchase": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginManual": "Added by hand",
  "@batchOriginManual": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginImported": "Imported",
  "@batchOriginImported": {
    "description": "Phase 6B — inventory."
  },
  "batchOriginAdjustment": "From an adjustment",
  "@batchOriginAdjustment": {
    "description": "Phase 6B — inventory."
  },
  "labelPurchased": "Purchased",
  "@labelPurchased": {
    "description": "Phase 6B — inventory."
  },
  "labelStorageLocation": "Stored in",
  "@labelStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "labelUnitCost": "Unit cost",
  "@labelUnitCost": {
    "description": "Phase 6B — inventory."
  },
  "labelInitial": "Bought",
  "@labelInitial": {
    "description": "Phase 6B — inventory."
  },
  "labelNearestExpiry": "Nearest expiry",
  "@labelNearestExpiry": {
    "description": "Phase 6B — inventory."
  },
  "labelDisplayUnit": "Shown in",
  "@labelDisplayUnit": {
    "description": "Phase 6B — inventory."
  },
  "labelItemKind": "Kind",
  "@labelItemKind": {
    "description": "Phase 6B — inventory."
  },
  "labelLowStockThreshold": "Low-stock level",
  "@labelLowStockThreshold": {
    "description": "Phase 6B — inventory."
  },
  "labelExpiryNotifyDays": "Warn before expiry",
  "@labelExpiryNotifyDays": {
    "description": "Phase 6B — inventory."
  },
  "actionConsume": "Use some",
  "@actionConsume": {
    "description": "Phase 6B — inventory."
  },
  "actionAddBatch": "Add a batch",
  "@actionAddBatch": {
    "description": "Phase 6B — inventory."
  },
  "actionViewHistory": "Movement history",
  "@actionViewHistory": {
    "description": "Phase 6B — inventory."
  },
  "actionDeleteItem": "Delete item",
  "@actionDeleteItem": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemTitle": "Delete this item?",
  "@confirmDeleteItemTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteItemBody": "Its {count, plural, =1{1 batch} other{{count} batches}} go with it. The movement history stays, so what you already used is still recorded.",
  "@confirmDeleteItemBody": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "itemDeleted": "Item deleted",
  "@itemDeleted": {
    "description": "Phase 6B — inventory."
  },
  "expiresInDays": "{days, plural, =0{Expires today} =1{Expires tomorrow} other{Expires in {days} days}}",
  "@expiresInDays": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "expiredDaysAgo": "{days, plural, =1{Expired yesterday} other{Expired {days} days ago}}",
  "@expiredDaysAgo": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "sectionWhatItIs": "What it is",
  "@sectionWhatItIs": {
    "description": "Phase 6B — inventory."
  },
  "sectionStockRules": "Stock rules",
  "@sectionStockRules": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryWeight": "Weight",
  "@unitCategoryWeight": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryVolume": "Volume",
  "@unitCategoryVolume": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryCount": "Count",
  "@unitCategoryCount": {
    "description": "Phase 6B — inventory."
  },
  "unitCategoryLocked": "Measured in {category}",
  "@unitCategoryLocked": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "category": {}
    }
  },
  "unitCategoryLockedHelp": "This cannot change. Every batch and movement already recorded is stored in this measure, and there is no conversion between weight, volume and count.",
  "@unitCategoryLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "expiryNotifyDaysHelp": "Days of warning before a batch expires.",
  "@expiryNotifyDaysHelp": {
    "description": "Phase 6B — inventory."
  },
  "labelFavourite": "Favourite",
  "@labelFavourite": {
    "description": "Phase 6B — inventory."
  },
  "saveItem": "Save item",
  "@saveItem": {
    "description": "Phase 6B — inventory."
  },
  "sectionHowMuch": "How much",
  "@sectionHowMuch": {
    "description": "Phase 6B — inventory."
  },
  "sectionBatchDetails": "Batch details",
  "@sectionBatchDetails": {
    "description": "Phase 6B — inventory."
  },
  "saveBatch": "Save batch",
  "@saveBatch": {
    "description": "Phase 6B — inventory."
  },
  "batchSaved": "Batch saved",
  "@batchSaved": {
    "description": "Phase 6B — inventory."
  },
  "hintStorageLocation": "Freezer, pantry, bathroom shelf…",
  "@hintStorageLocation": {
    "description": "Phase 6B — inventory."
  },
  "consumeTitle": "Use stock",
  "@consumeTitle": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindConsume": "Used",
  "@consumeKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindWaste": "Thrown away",
  "@consumeKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeKindExpired": "Expired",
  "@consumeKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "consumeRecorded": "Recorded",
  "@consumeRecorded": {
    "description": "Phase 6B — inventory."
  },
  "consumeFromLabel": "Taking from",
  "@consumeFromLabel": {
    "description": "Phase 6B — inventory."
  },
  "consumeFefoNote": "Oldest expiry first.",
  "@consumeFefoNote": {
    "description": "Phase 6B — inventory."
  },
  "consumeSpansBatches": "{count, plural, =1{Takes all of 1 batch} other{Spans {count} batches, writing {count} movements}}",
  "@consumeSpansBatches": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "consumeOverAvailable": "More than you have on hand",
  "@consumeOverAvailable": {
    "description": "Phase 6B — inventory."
  },
  "historyTitle": "Movement history",
  "@historyTitle": {
    "description": "Phase 6B — inventory."
  },
  "movementKindOpeningIn": "Opening stock",
  "@movementKindOpeningIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindPurchaseIn": "Bought",
  "@movementKindPurchaseIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindManualIn": "Added by hand",
  "@movementKindManualIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindConsume": "Used",
  "@movementKindConsume": {
    "description": "Phase 6B — inventory."
  },
  "movementKindWaste": "Thrown away",
  "@movementKindWaste": {
    "description": "Phase 6B — inventory."
  },
  "movementKindExpired": "Expired",
  "@movementKindExpired": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustIn": "Adjusted up",
  "@movementKindAdjustIn": {
    "description": "Phase 6B — inventory."
  },
  "movementKindAdjustOut": "Adjusted down",
  "@movementKindAdjustOut": {
    "description": "Phase 6B — inventory."
  },
  "movementReversed": "Reversed",
  "@movementReversed": {
    "description": "Phase 6B — inventory."
  },
  "movementIsReversal": "Reverses an earlier movement",
  "@movementIsReversal": {
    "description": "Phase 6B — inventory."
  },
  "actionReverse": "Reverse",
  "@actionReverse": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseTitle": "Reverse this movement?",
  "@confirmReverseTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmReverseBody": "An opposite movement is appended. Nothing is erased — both entries stay in the history.",
  "@confirmReverseBody": {
    "description": "Phase 6B — inventory."
  },
  "movementReversedSnack": "Movement reversed",
  "@movementReversedSnack": {
    "description": "Phase 6B — inventory."
  },
  "emptyTitleNoMovements": "Nothing recorded yet",
  "@emptyTitleNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoMovements": "Using, wasting or adjusting this batch will show up here.",
  "@emptyBodyNoMovements": {
    "description": "Phase 6B — inventory."
  },
  "emptyBodyNoBatches": "Add a batch and it will appear here with its expiry.",
  "@emptyBodyNoBatches": {
    "description": "Phase 6B — inventory."
  },
  "batchQuantityLockedHelp": "How much is left is worked out from the movement history. Use, waste or adjust the batch to change it.",
  "@batchQuantityLockedHelp": {
    "description": "Phase 6B — inventory."
  },
  "daysCount": "{days, plural, =1{1 day} other{{days} days}}",
  "@daysCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "days": {}
    }
  },
  "groupByFavourites": "Group favourites first",
  "@groupByFavourites": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitUsed": "Record as used",
  "@consumeCommitUsed": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitWaste": "Record as thrown away",
  "@consumeCommitWaste": {
    "description": "Phase 6B — inventory."
  },
  "consumeCommitExpired": "Record as expired",
  "@consumeCommitExpired": {
    "description": "Phase 6B — inventory."
  },
  "lowStockWithCount": "Low · {count}",
  "@lowStockWithCount": {
    "description": "Phase 6B — inventory.",
    "placeholders": {
      "count": {}
    }
  },
  "actionDeleteBatch": "Delete batch",
  "@actionDeleteBatch": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchTitle": "Delete this batch?",
  "@confirmDeleteBatchTitle": {
    "description": "Phase 6B — inventory."
  },
  "confirmDeleteBatchBody": "The stock it still holds disappears from your on-hand total. What you already used stays in the movement history.",
  "@confirmDeleteBatchBody": {
    "description": "Phase 6B — inventory."
  },
  "batchDeleted": "Batch deleted",
  "@batchDeleted": {
    "description": "Phase 6B — inventory."
  },
  "itemCreate": "New item",
  "@itemCreate": {
    "description": "Creates a catalogued item inline while itemising a receipt."
  },
  "itemCreateHint": "No items yet — create one so this line becomes stock.",
  "@itemCreateHint": {
    "description": "Shown in the line editor when the item catalogue is empty."
  },
  "itemCreateCategoryPrompt": "How is it measured? This cannot change later.",
  "@itemCreateCategoryPrompt": {
    "description": "Prompt for unitCategory on inline creation; immutable after create (Law L8)."
  },
  "itemDuplicateBody": "You already have this item, measured the same way. Open the one you have instead of adding a second.",
  "@itemDuplicateBody": {
    "description": "Shown when an item with the same normalized name and unit category exists."
  },
  "itemUnitsMissingBody": "No units are set up for this measure yet. Pick a different measure, or add units in Settings first.",
  "@itemUnitsMissingBody": {
    "description": "Shown when the chosen UnitCategory has no rows in units."
  },
  "itemSimilarNote": "You also have this name under a different measure. That is fine — weight, volume and count never convert into each other.",
  "@itemSimilarNote": {
    "description": "Informational note, never a block: Law L8 makes same-name/different-category distinct items."
  },
  "actionOpenExisting": "Open the one I have",
  "@actionOpenExisting": {
    "description": "Opens the existing item a duplicate collides with."
  },
  "shoppingEstimate": "Estimated",
  "@shoppingEstimate": {
    "description": "Running total of estimated prices on a shopping list."
  },
  "shoppingSwitchList": "Switch list",
  "@shoppingSwitchList": {
    "description": "Opens the list manager from the app bar."
  },
  "shoppingCheckedCount": "{checked} of {total} ticked",
  "@shoppingCheckedCount": {
    "description": "Progress line above a shopping list.",
    "placeholders": {
      "checked": {},
      "total": {}
    }
  },
  "emptyTitleNoEntries": "Nothing on this list yet",
  "@emptyTitleNoEntries": {
    "description": "Shopping list empty state."
  },
  "emptyBodyNoEntries": "Add what you need, or pull in suggestions from what is running low.",
  "@emptyBodyNoEntries": {
    "description": "Shopping list empty state body."
  },
  "addEntry": "Add",
  "@addEntry": {
    "description": "Adds one entry to a shopping list."
  },
  "shoppingGroupUntagged": "Everything else",
  "@shoppingGroupUntagged": {
    "description": "Header for entries with no tag."
  },
  "actionUncheckAll": "Untick everything",
  "@actionUncheckAll": {
    "description": "Clears every tick on a shopping list."
  },
  "entryEditorTitle": "What do you need?",
  "@entryEditorTitle": {
    "description": "Entry editor sheet title."
  },
  "entryFreeTextLabel": "Name it",
  "@entryFreeTextLabel": {
    "description": "Free-text label for a shopping entry."
  },
  "entryFreeTextHint": "Television, birthday card, light bulbs…",
  "@entryFreeTextHint": {
    "description": "Hint showing that an entry need not be an inventory item."
  },
  "entryLinkItem": "Link to an item",
  "@entryLinkItem": {
    "description": "Optional link from a shopping entry to a catalogued item."
  },
  "entryNoItem": "Not in my inventory",
  "@entryNoItem": {
    "description": "Dropdown option leaving itemId null."
  },
  "labelEstimatedPrice": "Estimated price",
  "@labelEstimatedPrice": {
    "description": "Optional per-entry price estimate."
  },
  "entryNeedsSomething": "Give it a name, or link it to an item",
  "@entryNeedsSomething": {
    "description": "Rejection when neither freeText nor itemId is set."
  },
  "originAutoLowStock": "Suggested",
  "@originAutoLowStock": {
    "description": "Chip marking an auto-generated low-stock entry."
  },
  "originPromoted": "Yours now",
  "@originPromoted": {
    "description": "Chip shown once an auto entry has been edited into a manual one."
  },
  "actionSnooze": "Snooze a week",
  "@actionSnooze": {
    "description": "Hides an auto suggestion until a later date."
  },
  "actionDismiss": "Not now",
  "@actionDismiss": {
    "description": "Dismisses an auto suggestion until stock recovers and drops again."
  },
  "snoozedUntilLabel": "Snoozed until",
  "@snoozedUntilLabel": {
    "description": "Precedes a DateText on a snoozed entry."
  },
  "generateTitle": "Running low",
  "@generateTitle": {
    "description": "Low-stock suggestion sheet title."
  },
  "generateBody": "These are below the level you set. Add the ones you want.",
  "@generateBody": {
    "description": "Low-stock suggestion sheet body."
  },
  "generateShortBy": "Short by",
  "@generateShortBy": {
    "description": "Precedes a QtyText giving threshold minus stock on hand."
  },
  "generateRefresh": "Check again",
  "@generateRefresh": {
    "description": "Re-runs low-stock generation."
  },
  "generateEmptyTitle": "Nothing is running low",
  "@generateEmptyTitle": {
    "description": "Generate sheet empty state."
  },
  "generateEmptyBody": "Set a low-stock level on an item and it will show up here when it drops.",
  "@generateEmptyBody": {
    "description": "Generate sheet empty state body."
  },
  "generateAdded": "{count, plural, =1{1 suggestion added} other{{count} suggestions added}}",
  "@generateAdded": {
    "description": "Result snack after regeneration.",
    "placeholders": {
      "count": {}
    }
  },
  "convertTitle": "Turn into a purchase",
  "@convertTitle": {
    "description": "Convert-to-purchase screen title."
  },
  "convertBody": "Each ticked entry becomes one line, marked for inventory. You confirm the amount and account next.",
  "@convertBody": {
    "description": "Explains the handoff to the expense editor."
  },
  "convertConfirm": "Open the expense",
  "@convertConfirm": {
    "description": "Primary action; hands off to the 6A editor."
  },
  "convertNothingTitle": "Nothing is ticked",
  "@convertNothingTitle": {
    "description": "Convert screen empty state."
  },
  "convertNothingBody": "Tick what you actually bought, then come back.",
  "@convertNothingBody": {
    "description": "Convert screen empty state body."
  },
  "convertLineCount": "{count, plural, =1{1 line} other{{count} lines}}",
  "@convertLineCount": {
    "description": "How many lines the draft will carry.",
    "placeholders": {
      "count": {}
    }
  },
  "listManagerTitle": "Your lists",
  "@listManagerTitle": {
    "description": "List manager sheet title."
  },
  "listNameLabel": "List name",
  "@listNameLabel": {
    "description": "Field label when creating or renaming a list."
  },
  "listCreate": "New list",
  "@listCreate": {
    "description": "Creates a shopping list."
  },
  "listRename": "Rename",
  "@listRename": {
    "description": "Renames a shopping list."
  },
  "listSetDefault": "Make default",
  "@listSetDefault": {
    "description": "Marks a list as the one that opens by default."
  },
  "listDefaultBadge": "Default",
  "@listDefaultBadge": {
    "description": "Chip on the default list."
  },
  "listArchive": "Archive",
  "@listArchive": {
    "description": "Archives a shopping list."
  },
  "listUnarchive": "Restore",
  "@listUnarchive": {
    "description": "Un-archives a shopping list."
  },
  "listArchivedBadge": "Archived",
  "@listArchivedBadge": {
    "description": "Chip on an archived list."
  },
  "listArchivedSection": "Archived",
  "@listArchivedSection": {
    "description": "Section header for archived lists."
  },
  "emptyTitleNoLists": "No lists yet",
  "@emptyTitleNoLists": {
    "description": "List manager empty state."
  },
  "emptyBodyNoLists": "Create one and it becomes your default.",
  "@emptyBodyNoLists": {
    "description": "List manager empty state body."
  },
  "loadingShopping": "Loading your list",
  "@loadingShopping": {
    "description": "Skeleton label for shopping surfaces."
  },
  "actionAddToList": "Add to my list",
  "@actionAddToList": {
    "description": "Accepts a low-stock suggestion, promoting it to origin=manual so regeneration leaves it alone."
  },
  "suggestionDismissed": "Turned down",
  "@suggestionDismissed": {
    "description": "Chip on a dismissed suggestion; it stays listed so it can be accepted later."
  },
  "lineItemsTitle": "What you bought",
  "@lineItemsTitle": {
    "description": "Title of the dedicated line-items page."
  },
  "lineItemsManage": "Add or edit items",
  "@lineItemsManage": {
    "description": "Opens the line-items page from the transaction editor."
  },
  "lineItemsAdd": "Add an item",
  "@lineItemsAdd": {
    "description": "Adds one line from the line-items page."
  },
  "lineItemsSaveAndAnother": "Save & add another",
  "@lineItemsSaveAndAnother": {
    "description": "Commits the line and reopens the editor blank, so a receipt is entered without leaving the sheet."
  },
  "lineItemsCount": "{count, plural, =0{No items yet} =1{1 item} other{{count} items}}",
  "@lineItemsCount": {
    "description": "Running count on the line-items page.",
    "placeholders": {
      "count": {}
    }
  },
  "emptyTitleNoLineItems": "Nothing itemised yet",
  "@emptyTitleNoLineItems": {
    "description": "Line-items page empty state."
  },
  "emptyBodyNoLineItems": "Add what was on the receipt. Anything you leave out still counts toward the total.",
  "@emptyBodyNoLineItems": {
    "description": "Line-items page empty state body."
  },
  "actionRemove": "Remove",
  "@actionRemove": {
    "description": "Removes one line from a transaction."
  },
  "lineRemoved": "Item removed",
  "@lineRemoved": {
    "description": "Snack after removing a line."
  },
  "lineItemsAllocated": "Itemised",
  "@lineItemsAllocated": {
    "description": "Precedes the summed line total on the line-items page."
  },
  "recurringOutflow": "Going out",
  "@recurringOutflow": {
    "description": "Group header for outflow templates."
  },
  "recurringInflow": "Coming in",
  "@recurringInflow": {
    "description": "Group header for inflow templates — salary reads as income, not a negative bill."
  },
  "recurringNextDue": "Next",
  "@recurringNextDue": {
    "description": "Precedes a DateText giving the next due date."
  },
  "recurringOverdue": "Overdue",
  "@recurringOverdue": {
    "description": "Chip on an occurrence past its due date. Derived from the clock, never stored."
  },
  "recurringPaused": "Paused",
  "@recurringPaused": {
    "description": "Chip on a paused template."
  },
  "recurringDueToday": "Due today",
  "@recurringDueToday": {
    "description": "Chip when the next occurrence falls today."
  },
  "emptyTitleNoTemplates": "Nothing recurring yet",
  "@emptyTitleNoTemplates": {
    "description": "Template list empty state."
  },
  "emptyBodyNoTemplates": "Add a bill, a subscription or a salary and it will appear here when it is next due.",
  "@emptyBodyNoTemplates": {
    "description": "Template list empty state body."
  },
  "addTemplate": "Add",
  "@addTemplate": {
    "description": "Adds a recurring template."
  },
  "actionPause": "Pause",
  "@actionPause": {
    "description": "Pauses a template."
  },
  "actionResume": "Resume",
  "@actionResume": {
    "description": "Resumes a paused template."
  },
  "loadingRecurring": "Loading your schedule",
  "@loadingRecurring": {
    "description": "Skeleton label for recurring surfaces."
  },
  "builderSectionWhat": "What it is",
  "@builderSectionWhat": {
    "description": "First section of the template builder."
  },
  "builderSectionWhen": "How often",
  "@builderSectionWhen": {
    "description": "Frequency section of the template builder."
  },
  "builderSectionDefaults": "Defaults",
  "@builderSectionDefaults": {
    "description": "Amount and account section of the template builder."
  },
  "labelTemplateName": "Name",
  "@labelTemplateName": {
    "description": "Template name field."
  },
  "labelRecurringKind": "Kind",
  "@labelRecurringKind": {
    "description": "Bill, subscription, rent or salary."
  },
  "labelDirection": "Direction",
  "@labelDirection": {
    "description": "Whether money goes out or comes in."
  },
  "directionOutflow": "Money out",
  "@directionOutflow": {
    "description": "RecurringDirection.outflow."
  },
  "directionInflow": "Money in",
  "@directionInflow": {
    "description": "RecurringDirection.inflow."
  },
  "kindBill": "Bill",
  "@kindBill": {
    "description": "RecurringKind.bill."
  },
  "kindSubscription": "Subscription",
  "@kindSubscription": {
    "description": "RecurringKind.subscription."
  },
  "kindRent": "Rent",
  "@kindRent": {
    "description": "RecurringKind.rent."
  },
  "kindSalary": "Salary",
  "@kindSalary": {
    "description": "RecurringKind.salary."
  },
  "labelEvery": "Every",
  "@labelEvery": {
    "description": "Precedes the interval count and unit."
  },
  "unitDay": "{count, plural, =1{day} other{days}}",
  "@unitDay": {
    "description": "RecurringIntervalUnit.day.",
    "placeholders": {
      "count": {}
    }
  },
  "unitWeek": "{count, plural, =1{week} other{weeks}}",
  "@unitWeek": {
    "description": "RecurringIntervalUnit.week.",
    "placeholders": {
      "count": {}
    }
  },
  "unitMonth": "{count, plural, =1{month} other{months}}",
  "@unitMonth": {
    "description": "RecurringIntervalUnit.month.",
    "placeholders": {
      "count": {}
    }
  },
  "unitYear": "{count, plural, =1{year} other{years}}",
  "@unitYear": {
    "description": "RecurringIntervalUnit.year.",
    "placeholders": {
      "count": {}
    }
  },
  "labelAnchorDay": "On day of the month",
  "@labelAnchorDay": {
    "description": "anchorDayOfMonth. Stored once, clamped at render (anomaly A13)."
  },
  "anchorDayHelp": "Kept as you set it. Anchored on the 31st, a short month falls on its last day and the next long month returns to the 31st.",
  "@anchorDayHelp": {
    "description": "Explains that the anchor never walks backwards."
  },
  "labelStartDate": "Starts",
  "@labelStartDate": {
    "description": "startDateKey."
  },
  "labelEndDate": "Ends",
  "@labelEndDate": {
    "description": "endDateKey, optional."
  },
  "labelDefaultAmount": "Usual amount",
  "@labelDefaultAmount": {
    "description": "defaultAmount — a default, not a fixed figure."
  },
  "labelRemindBefore": "Remind me",
  "@labelRemindBefore": {
    "description": "remindDaysBefore."
  },
  "saveTemplate": "Save",
  "@saveTemplate": {
    "description": "Commits the template."
  },
  "previewTitle": "Next three",
  "@previewTitle": {
    "description": "Header of the frequency preview."
  },
  "previewEmpty": "Set a start date to see when this lands.",
  "@previewEmpty": {
    "description": "Frequency preview with nothing to show."
  },
  "previewClamped": "Shortened to fit the month",
  "@previewClamped": {
    "description": "Marks a previewed date the anchor could not reach."
  },
  "payTitle": "Record this payment",
  "@payTitle": {
    "description": "Pay sheet title."
  },
  "payTitleInflow": "Record this receipt",
  "@payTitleInflow": {
    "description": "Pay sheet title for an inflow."
  },
  "labelActualAmount": "Amount actually paid",
  "@labelActualAmount": {
    "description": "The real figure, which may differ from the default."
  },
  "labelActualAmountInflow": "Amount actually received",
  "@labelActualAmountInflow": {
    "description": "Inflow wording for the same field."
  },
  "payUsualWas": "Usually",
  "@payUsualWas": {
    "description": "Precedes the default amount when the actual differs from it."
  },
  "labelPaidOn": "Paid on",
  "@labelPaidOn": {
    "description": "paidDateKey."
  },
  "payCommit": "Record it",
  "@payCommit": {
    "description": "Commits the payment and creates the transaction."
  },
  "payRecorded": "Recorded",
  "@payRecorded": {
    "description": "Result snack after paying."
  },
  "payNeedsAccount": "Choose which account it came from",
  "@payNeedsAccount": {
    "description": "Rejection when no account is selected."
  },
  "payUndoTitle": "Undo this payment?",
  "@payUndoTitle": {
    "description": "Confirmation before undoing."
  },
  "payUndoBody": "The obligation goes back to due and the transaction it created is deleted. Anything that transaction produced — stock, an asset — goes with it.",
  "@payUndoBody": {
    "description": "Says exactly what undo reverses, in the order it happens (ARCH_5 §5.4)."
  },
  "payUndone": "Payment undone",
  "@payUndone": {
    "description": "Result snack after undoing."
  },
  "actionSkip": "Skip this one",
  "@actionSkip": {
    "description": "Marks an occurrence deliberately skipped."
  },
  "occurrenceSkipped": "Skipped",
  "@occurrenceSkipped": {
    "description": "Chip on a skipped occurrence, and the snack after skipping."
  },
  "historyRecurringTitle": "Payment history",
  "@historyRecurringTitle": {
    "description": "Occurrence history screen title."
  },
  "historyDefaultVsActual": "Differed from the usual amount",
  "@historyDefaultVsActual": {
    "description": "Badge when paidAmount != defaultAmount."
  },
  "emptyTitleNoOccurrences": "Nothing due yet",
  "@emptyTitleNoOccurrences": {
    "description": "Occurrence history empty state."
  },
  "emptyBodyNoOccurrences": "Occurrences appear as their due dates arrive. Nothing is ever paid for you.",
  "@emptyBodyNoOccurrences": {
    "description": "Empty state body, stating anomaly A14 plainly."
  },
  "statusDue": "Due",
  "@statusDue": {
    "description": "RecurringOccurrenceStatus.due."
  },
  "statusPaid": "Paid",
  "@statusPaid": {
    "description": "RecurringOccurrenceStatus.paid."
  },
  "statusDismissed": "Dismissed",
  "@statusDismissed": {
    "description": "RecurringOccurrenceStatus.dismissed."
  },
  "kindServiceFee": "Service fee",
  "@kindServiceFee": {
    "description": "RecurringKind.serviceFee — a recurring charge tied to an asset."
  },
  "kindOther": "Something else",
  "@kindOther": {
    "description": "RecurringKind.other — anything the named kinds do not cover."
  },
  "billDueSection": "Due now",
  "@billDueSection": {
    "description": "Header above the recurring bills a payment can settle."
  },
  "billSetUpAction": "Set up a recurring bill",
  "@billSetUpAction": {
    "description": "Opens the template builder from the bill form."
  },
  "billNothingDue": "Nothing is due right now.",
  "@billNothingDue": {
    "description": "Shown in the bill form when no occurrence is outstanding."
  },
  "recurringScheduleNext": "Saved. Now set how often it repeats.",
  "@recurringScheduleNext": {
    "description": "Snack after a line asked to become recurring."
  },
  "recurringNotYetDue": "Not due yet",
  "@recurringNotYetDue": {
    "description": "Chip when the next occurrence has not materialised."
  },
  "billSettlesLabel": "Settling",
  "@billSettlesLabel": {
    "description": "Precedes the recurring bill this payment will settle."
  },
  "billSettleNone": "Not a recurring bill",
  "@billSettleNone": {
    "description": "Option that leaves the payment unlinked to any template."
  },
  "billSettleHelp": "Pick one and the amount below becomes what you actually paid. Saving records it once.",
  "@billSettleHelp": {
    "description": "Explains that the editor is the single write path for a bill payment."
  },
  "billAmountBecomesPaid": "This amount is what gets recorded",
  "@billAmountBecomesPaid": {
    "description": "Helper under the amount when a bill is selected."
  },
  "billAccountAuto": "Paid from",
  "@billAccountAuto": {
    "description": "Precedes the account resolved automatically for a bill payment."
  },
  "billAccountAskOnce": "Which account does this come from? Alaya remembers it on the bill.",
  "@billAccountAskOnce": {
    "description": "Shown only when no template default, no app default and more than one account exist."
  },
  "assetGroupAppliance": "Appliances",
  "@assetGroupAppliance": {
    "description": "AssetType.appliance group header."
  },
  "assetGroupElectronics": "Electronics",
  "@assetGroupElectronics": {
    "description": "AssetType.electronics."
  },
  "assetGroupVehicle": "Vehicles",
  "@assetGroupVehicle": {
    "description": "AssetType.vehicle."
  },
  "assetGroupFurniture": "Furniture",
  "@assetGroupFurniture": {
    "description": "AssetType.furniture."
  },
  "assetGroupProperty": "Property",
  "@assetGroupProperty": {
    "description": "AssetType.property."
  },
  "assetGroupServiceProvider": "People",
  "@assetGroupServiceProvider": {
    "description": "AssetType.serviceProvider — a maid or gardener lives here, not in a second system."
  },
  "assetGroupSubscription": "Subscriptions",
  "@assetGroupSubscription": {
    "description": "AssetType.subscription."
  },
  "assetGroupOther": "Other",
  "@assetGroupOther": {
    "description": "AssetType.other."
  },
  "assetUnderWarranty": "In warranty",
  "@assetUnderWarranty": {
    "description": "Chip when warrantyEndDateKey is still ahead."
  },
  "assetWarrantyEnding": "Warranty ending",
  "@assetWarrantyEnding": {
    "description": "Chip when the warranty ends soon."
  },
  "assetWarrantyExpired": "Out of warranty",
  "@assetWarrantyExpired": {
    "description": "Chip when the warranty has passed."
  },
  "assetServiceDue": "Service due",
  "@assetServiceDue": {
    "description": "Chip when nextServiceDueDateKey has passed."
  },
  "assetServiceSoon": "Service soon",
  "@assetServiceSoon": {
    "description": "Chip when a service is close."
  },
  "assetDisposedChip": "Disposed",
  "@assetDisposedChip": {
    "description": "Chip on a disposed asset."
  },
  "assetUnderRepair": "Being repaired",
  "@assetUnderRepair": {
    "description": "AssetStatus.underRepair."
  },
  "filterShowDisposed": "Include disposed",
  "@filterShowDisposed": {
    "description": "Filter that brings disposed assets back into the list."
  },
  "emptyTitleNoAssets": "Nothing tracked yet",
  "@emptyTitleNoAssets": {
    "description": "Asset list empty state."
  },
  "emptyBodyNoAssets": "Add an appliance, a vehicle, or the person who helps around the house — they all live here.",
  "@emptyBodyNoAssets": {
    "description": "Asset list empty state body, stating the serviceProvider case plainly."
  },
  "addAsset": "Add",
  "@addAsset": {
    "description": "Adds an asset."
  },
  "loadingAssets": "Loading your things",
  "@loadingAssets": {
    "description": "Skeleton label for service surfaces."
  },
  "assetSectionIdentity": "Details",
  "@assetSectionIdentity": {
    "description": "Identity section on the detail screen."
  },
  "assetSectionWarranty": "Warranty",
  "@assetSectionWarranty": {
    "description": "Warranty section."
  },
  "assetSectionContact": "Contact",
  "@assetSectionContact": {
    "description": "Contact block."
  },
  "assetSectionService": "Service history",
  "@assetSectionService": {
    "description": "Service records section."
  },
  "assetSectionSalary": "Salary history",
  "@assetSectionSalary": {
    "description": "Service records section for a serviceProvider."
  },
  "assetLifetimeCost": "Spent on service so far",
  "@assetLifetimeCost": {
    "description": "Sum of every service record cost."
  },
  "assetLifetimeSalary": "Paid so far",
  "@assetLifetimeSalary": {
    "description": "The same figure for a serviceProvider."
  },
  "labelBrand": "Brand",
  "@labelBrand": {
    "description": "assets.brand."
  },
  "labelModelNo": "Model",
  "@labelModelNo": {
    "description": "assets.modelNo."
  },
  "labelSerialNo": "Serial",
  "@labelSerialNo": {
    "description": "assets.serialNo."
  },
  "labelPurchasePrice": "Bought for",
  "@labelPurchasePrice": {
    "description": "assets.purchasePrice."
  },
  "labelWarrantyStart": "Warranty from",
  "@labelWarrantyStart": {
    "description": "assets.warrantyStartDateKey."
  },
  "labelWarrantyEnd": "Warranty until",
  "@labelWarrantyEnd": {
    "description": "assets.warrantyEndDateKey."
  },
  "labelWarrantyProvider": "Covered by",
  "@labelWarrantyProvider": {
    "description": "assets.warrantyProvider."
  },
  "labelServiceInterval": "Service every",
  "@labelServiceInterval": {
    "description": "assets.serviceIntervalDays."
  },
  "labelNextService": "Next service",
  "@labelNextService": {
    "description": "assets.nextServiceDueDateKey."
  },
  "labelContactName": "Name",
  "@labelContactName": {
    "description": "assets.primaryContactName."
  },
  "labelContactPhone": "Phone",
  "@labelContactPhone": {
    "description": "assets.primaryContactPhone."
  },
  "labelLocation": "Kept in",
  "@labelLocation": {
    "description": "assets.location."
  },
  "actionCall": "Call",
  "@actionCall": {
    "description": "Dials primaryContactPhone."
  },
  "callFailed": "No app on this phone can place that call.",
  "@callFailed": {
    "description": "Shown when the tel: intent finds no handler."
  },
  "actionAddService": "Record a service",
  "@actionAddService": {
    "description": "Adds a service record."
  },
  "actionAddSalary": "Record a payment",
  "@actionAddSalary": {
    "description": "The same action for a serviceProvider."
  },
  "actionDispose": "Dispose of it",
  "@actionDispose": {
    "description": "Opens the dispose sheet."
  },
  "actionUndispose": "Bring it back",
  "@actionUndispose": {
    "description": "Reverses a disposal."
  },
  "assetLinkedRecurring": "Paid on a schedule",
  "@assetLinkedRecurring": {
    "description": "Chip when linkedRecurringTemplateId is set."
  },
  "emptyBodyNoServices": "Nothing recorded against this yet.",
  "@emptyBodyNoServices": {
    "description": "Empty service history."
  },
  "labelAssetName": "What is it?",
  "@labelAssetName": {
    "description": "assets.name."
  },
  "labelAssetType": "Kind",
  "@labelAssetType": {
    "description": "assets.type."
  },
  "assetTypeHelpPerson": "A person you pay regularly belongs here too — their payments become service records.",
  "@assetTypeHelpPerson": {
    "description": "Explains AssetType.serviceProvider when it is chosen."
  },
  "saveAsset": "Save",
  "@saveAsset": {
    "description": "Commits an asset."
  },
  "serviceIntervalHelp": "Days between services. The next due date moves on each time you record one.",
  "@serviceIntervalHelp": {
    "description": "Explains serviceIntervalDays."
  },
  "labelServiceType": "What happened",
  "@labelServiceType": {
    "description": "service_records.type."
  },
  "serviceTypeService": "Serviced",
  "@serviceTypeService": {
    "description": "ServiceRecordType.service."
  },
  "serviceTypeRepair": "Repaired",
  "@serviceTypeRepair": {
    "description": "ServiceRecordType.repair."
  },
  "serviceTypeMaintenance": "Maintenance",
  "@serviceTypeMaintenance": {
    "description": "ServiceRecordType.maintenance."
  },
  "serviceTypeInspection": "Inspection",
  "@serviceTypeInspection": {
    "description": "ServiceRecordType.inspection."
  },
  "serviceTypeSalaryPaid": "Salary paid",
  "@serviceTypeSalaryPaid": {
    "description": "ServiceRecordType.salaryPaid — the maid case."
  },
  "serviceTypeOther": "Something else",
  "@serviceTypeOther": {
    "description": "ServiceRecordType.other."
  },
  "labelProviderName": "Who did it",
  "@labelProviderName": {
    "description": "service_records.providerName."
  },
  "labelProviderPhone": "Their number",
  "@labelProviderPhone": {
    "description": "service_records.providerPhone."
  },
  "labelServiceDate": "When",
  "@labelServiceDate": {
    "description": "service_records.serviceDateKey."
  },
  "labelServiceCost": "Cost",
  "@labelServiceCost": {
    "description": "service_records.cost."
  },
  "labelNextDue": "Next one due",
  "@labelNextDue": {
    "description": "service_records.nextDueDateKey."
  },
  "alsoRecordAsExpense": "Also record it as an expense",
  "@alsoRecordAsExpense": {
    "description": "The alsoRecordAsExpense toggle."
  },
  "alsoRecordHelp": "Writes a withdrawal for the cost as well, so it shows in your ledger.",
  "@alsoRecordHelp": {
    "description": "Explains what the toggle writes."
  },
  "alsoRecordNeedsAccount": "Choose which account it comes from",
  "@alsoRecordNeedsAccount": {
    "description": "Rejection when the toggle is on with no account."
  },
  "alsoRecordNeedsCost": "Add a cost first",
  "@alsoRecordNeedsCost": {
    "description": "Rejection when the toggle is on with no cost."
  },
  "saveService": "Save",
  "@saveService": {
    "description": "Commits a service record."
  },
  "disposeTitle": "What happened to it?",
  "@disposeTitle": {
    "description": "Dispose sheet title."
  },
  "disposeBody": "It stays in your records either way — what you spent on it still counts. This just stops it appearing as something you own.",
  "@disposeBody": {
    "description": "States anomaly A30 plainly: an asset is never deleted."
  },
  "disposeReasonSold": "Sold it",
  "@disposeReasonSold": {
    "description": "AssetDisposalReason.sold."
  },
  "disposeReasonExpired": "Wore out",
  "@disposeReasonExpired": {
    "description": "AssetDisposalReason.expired."
  },
  "disposeReasonDamaged": "Broke",
  "@disposeReasonDamaged": {
    "description": "AssetDisposalReason.damaged."
  },
  "disposeReasonGifted": "Gave it away",
  "@disposeReasonGifted": {
    "description": "AssetDisposalReason.gifted."
  },
  "disposeReasonLost": "Lost it",
  "@disposeReasonLost": {
    "description": "AssetDisposalReason.lost."
  },
  "disposeReasonReplaced": "Replaced it",
  "@disposeReasonReplaced": {
    "description": "AssetDisposalReason.replaced."
  },
  "disposeReasonOther": "Something else",
  "@disposeReasonOther": {
    "description": "AssetDisposalReason.other."
  },
  "labelDisposalAmount": "Got back",
  "@labelDisposalAmount": {
    "description": "assets.disposalAmount — what the disposal recovered."
  },
  "labelDisposalDate": "When",
  "@labelDisposalDate": {
    "description": "assets.disposedAtDateKey."
  },
  "disposeCommit": "Record it",
  "@disposeCommit": {
    "description": "Commits the disposal."
  },
  "disposeDone": "Recorded",
  "@disposeDone": {
    "description": "Snack after disposing."
  },
  "undisposeDone": "Back in your list",
  "@undisposeDone": {
    "description": "Snack after un-disposing."
  },
  "disposeNeedsReason": "Pick what happened",
  "@disposeNeedsReason": {
    "description": "Rejection when no reason is chosen."
  },
  "hintSearchAssets": "Search your things and people",
  "@hintSearchAssets": {
    "description": "Search hint on the asset list."
  },
  "errorWarrantyBackwards": "The warranty cannot end before it starts",
  "@errorWarrantyBackwards": {
    "description": "Field error when warrantyEndDateKey precedes warrantyStartDateKey."
  },
  "sectionMoney": "Money",
  "@sectionMoney": {
    "description": "Header above the cost and expense controls on the service editor."
  },
  "assetCreatedFromPurchase": "Saved. Now say what it is and how long it is covered.",
  "@assetCreatedFromPurchase": {
    "description": "Snack after a purchase line created an asset."
  },
  "destinationHelpNone": "Recorded as spending and nothing else.",
  "@destinationHelpNone": {
    "description": "Explains destination none."
  },
  "destinationHelpInventory": "Groceries, refills, anything measured and consumed. Needs an item and a quantity, and creates stock you can run down.",
  "@destinationHelpInventory": {
    "description": "Explains destination inventory."
  },
  "destinationHelpAsset": "A phone, a fridge, a chair. Creates something you own, with its own warranty and service history.",
  "@destinationHelpAsset": {
    "description": "Explains destination asset."
  },
  "destinationHelpRecurring": "Sets up a schedule so this comes back every month.",
  "@destinationHelpRecurring": {
    "description": "Explains destination recurring."
  },
  "assetSameNameNote": "You already have one called this. That is fine — this will be a separate one, with its own warranty and service history.",
  "@assetSameNameNote": {
    "description": "Informational note when an asset name repeats. Never a block: five iPhones are five assets."
  },
  "@destinationNone": {
    "description": "No artefact. Recorded as spending and nothing else."
  },
  "@destinationInventory": {
    "description": "Creates stock. Names the Inventory module, matching navInventory."
  },
  "@destinationAsset": {
    "description": "Creates an asset. Names the Services module, matching navServices."
  },
  "@destinationRecurring": {
    "description": "Hands off to the template builder. Matches navRecurring."
  },
  "actionSetWarranty": "Set the warranty",
  "@actionSetWarranty": {
    "description": "Snack action opening the asset a purchase line created."
  },
  "labelPaymentMethodOptional": "How you paid (optional)",
  "@labelPaymentMethodOptional": {
    "description": "Optional payment method on the service editor. Travels to the expense, never onto the record."
  },
  "dashboardTitle": "Home",
  "@dashboardTitle": {
    "description": "Dashboard screen title."
  },
  "fundsAvailable": "Total available funds",
  "@fundsAvailable": {
    "description": "Label above the one headline figure on the dashboard."
  },
  "fundsUnconverted": "{count, plural, =1{1 balance not converted} other{{count} balances not converted}}",
  "@fundsUnconverted": {
    "description": "Chip when BalanceService could not convert some accounts. Excluded from the headline, never summed (anomaly A34).",
    "placeholders": {
      "count": {}
    }
  },
  "fundsApproximate": "Rate is older than today",
  "@fundsApproximate": {
    "description": "Chip when the conversion used the most recent rate on or before today."
  },
  "fundsWhyExcluded": "Balances Alaya has no rate for are left out rather than guessed at.",
  "@fundsWhyExcluded": {
    "description": "Explains why the headline may be lower than the sum of every account."
  },
  "rangeLast30": "Last 30 days",
  "@rangeLast30": {
    "description": "Range label. Always stated, never implied (anomaly A33)."
  },
  "rangeMoneyIn": "In",
  "@rangeMoneyIn": {
    "description": "Deposits over the labelled range."
  },
  "rangeMoneyOut": "Out",
  "@rangeMoneyOut": {
    "description": "Withdrawals over the labelled range."
  },
  "rangeNothingYet": "Nothing yet",
  "@rangeNothingYet": {
    "description": "Shown in place of a figure when a range holds no transactions."
  },
  "rangeExcluded": "{count, plural, =1{1 left out} other{{count} left out}}",
  "@rangeExcluded": {
    "description": "Chip when transactions in a foreign currency could not be converted into the range total.",
    "placeholders": {
      "count": {}
    }
  },
  "insightUpcoming": "Coming up",
  "@insightUpcoming": {
    "description": "The calendar side of the switchable insight card."
  },
  "insightSpending": "Where it went",
  "@insightSpending": {
    "description": "The analytics side of the switchable insight card."
  },
  "insightSwitchLabel": "Show",
  "@insightSwitchLabel": {
    "description": "Semantics label for the insight card switch."
  },
  "insightNothingUpcoming": "Nothing needs attention in the next fortnight.",
  "@insightNothingUpcoming": {
    "description": "Empty state for the upcoming side."
  },
  "insightBillDue": "Bill due",
  "@insightBillDue": {
    "description": "Upcoming row for a recurring occurrence."
  },
  "insightServiceDue": "Service due",
  "@insightServiceDue": {
    "description": "Upcoming row for an asset needing service."
  },
  "insightWarrantyEnding": "Warranty ending",
  "@insightWarrantyEnding": {
    "description": "Upcoming row for an expiring warranty."
  },
  "insightBatchExpiring": "Expiring",
  "@insightBatchExpiring": {
    "description": "Upcoming row for a batch past or near its expiry."
  },
  "moduleGridTitle": "Where to next",
  "@moduleGridTitle": {
    "description": "Header above the navigation tiles."
  },
  "moduleExpenses": "{count, plural, =0{none this month} =1{1 this month} other{{count} this month}}",
  "@moduleExpenses": {
    "description": "Live number on the Expenses tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleInventory": "{count, plural, =0{nothing tracked} =1{1 running low} other{{count} running low}}",
  "@moduleInventory": {
    "description": "Live number on the Inventory tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleShopping": "{count, plural, =0{list is clear} =1{1 to buy} other{{count} to buy}}",
  "@moduleShopping": {
    "description": "Live number on the Shopping tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleRecurring": "{count, plural, =0{all settled} =1{1 due} other{{count} due}}",
  "@moduleRecurring": {
    "description": "Live number on the Recurring tile.",
    "placeholders": {
      "count": {}
    }
  },
  "moduleServices": "{count, plural, =0{nothing needs doing} =1{1 needs attention} other{{count} need attention}}",
  "@moduleServices": {
    "description": "Live number on the Services tile.",
    "placeholders": {
      "count": {}
    }
  },
  "fabAddIncome": "Money in",
  "@fabAddIncome": {
    "description": "FAB action opening the editor as a deposit."
  },
  "fabAddItem": "New item",
  "@fabAddItem": {
    "description": "FAB action opening the item editor."
  },
  "loadingDashboard": "Adding it up",
  "@loadingDashboard": {
    "description": "Skeleton label for the dashboard."
  },
  "fabOpenLabel": "Add something",
  "@fabOpenLabel": {
    "description": "Semantics label for the closed expandable FAB."
  },
  "fabCloseLabel": "Close",
  "@fabCloseLabel": {
    "description": "Semantics label for the open expandable FAB."
  },
  "eventTypeTransaction": "Transaction",
  "eventTypeRecurringDue": "Recurring bill",
  "eventTypeBatchExpiry": "Expiring",
  "eventTypeWarrantyEnd": "Warranty ending",
  "eventTypeServiceDue": "Service due",
  "eventTypeShoppingTarget": "Shopping target",
  "calendarSeverityWarning": "Needs attention",
  "calendarSeverityDanger": "Past its date",
  "calendarLoadingDay": "Loading this day…",
  "calendarDayErrorTitle": "Could not load this day",
  "calendarDayEmptyTitle": "Nothing on this day",
  "calendarDayEmptyBody": "No transactions, bills, expiries or services fall here.",
  "calendarRetry": "Try again",
  "calendarLoadingMonth": "Loading this month…",
  "calendarErrorTitle": "Could not load the calendar",
  "calendarPreviousMonth": "Previous month",
  "calendarNextMonth": "Next month",
  "calendarOnDay": "On this day",
  "calendarRangeOn": "Select a range",
  "calendarRangeOff": "Stop selecting a range",
  "calendarRangePickEnd": "From {start} — tap another day to finish.",
  "calendarInRange": "{count, plural, =1{1 day} other{{count} days}}",
  "calendarRangeEmptyTitle": "Nothing in these days",
  "calendarRangeEmptyBody": "No transactions, bills, expiries or services fall inside the range.",
  "@calendarRangePickEnd": {
    "description": "Prompt after the range start is chosen.",
    "placeholders": {
      "start": {
        "type": "String"
      }
    }
  },
  "@calendarInRange": {
    "description": "How many days the chosen range spans.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "calendarBackToToday": "Back to this month",
  "calendarTotalOut": "Spent",
  "calendarTotalIn": "Received",
  "dashboardOpenCalendar": "Open calendar",
  "dashboardCalendarSemantics": "{month} at a glance. Opens the calendar.",
  "@dashboardCalendarSemantics": {
    "description": "Screen-reader label for the dashboard month card where days are too narrow to tap.",
    "placeholders": {
      "month": {
        "type": "String"
      }
    }
  },
  "navBackToDashboard": "Back to dashboard",
  "chartLoading": "Working it out…",
  "@chartLoading": {
    "description": "Shown in a ChartCard while its figure computes. A line rather than a spinner: a card about to hold a chart reads as slow behind one (ARCH_5 §5.2)."
  },
  "chartApproximate": "{count, plural, =1{1 figure is indicative} other{{count} figures are indicative}}",
  "@chartApproximate": {
    "description": "How many of a series' data points converted against a rate from a different day (ARCH_3 §1.3). Says what it means rather than naming the rate quality.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "chartUnconverted": "{count, plural, =1{1 amount left out} other{{count} amounts left out}}",
  "@chartUnconverted": {
    "description": "How many amounts had no usable rate and are excluded from the figure, never counted as zero (anomaly A15).",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTotalSpent": "Spent",
  "@analyticsTotalSpent": {
    "description": "Label above the analytics screen's one displayAmount."
  },
  "analyticsRangeLabel": "Reporting window",
  "@analyticsRangeLabel": {
    "description": "Semantics label for the range chip row."
  },
  "analyticsComparisonUp": "{percent} more than the window before",
  "@analyticsComparisonUp": {
    "description": "Period-over-period comparison, rising. The window compared against is the same length, not a calendar month.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsComparisonDown": "{percent} less than the window before",
  "@analyticsComparisonDown": {
    "description": "Period-over-period comparison, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsUnconvertedTotal": "{count, plural, =1{1 amount needs a rate} other{{count} amounts need a rate}}",
  "@analyticsUnconvertedTotal": {
    "description": "The app-wide unconverted count, distinct from one figure's own exclusions. A transaction outside the window can still be unconvertible.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsInflationTitle": "Your own inflation",
  "@analyticsInflationTitle": {
    "description": "Title of the personal-inflation card, queries 12 and 24."
  },
  "analyticsInflationSubtitle": "What one thing costs you, purchase by purchase",
  "@analyticsInflationSubtitle": {
    "description": "Explains that the trend is per base unit, so 2 kg and 500 g are comparable."
  },
  "analyticsInflationUp": "{percent} more than the first time in this window",
  "@analyticsInflationUp": {
    "description": "The personal-inflation sentence, rising. The date is rendered separately through DateText (Law U7).",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationDown": "{percent} less than the first time in this window",
  "@analyticsInflationDown": {
    "description": "The personal-inflation sentence, falling.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsInflationSince": "First bought",
  "@analyticsInflationSince": {
    "description": "Precedes a DateText giving the earliest purchase in the window."
  },
  "analyticsInflationEmpty": "Buy something twice and its price trend appears here. Widen the window if you have.",
  "@analyticsInflationEmpty": {
    "description": "Empty state: fewer than two priced purchases means there is no trend to draw. Names both ways out."
  },
  "analyticsSectionSpend": "Where it went",
  "@analyticsSectionSpend": {
    "description": "Section header over the spend breakdowns."
  },
  "analyticsSectionTime": "Over time",
  "@analyticsSectionTime": {
    "description": "Section header over the trends."
  },
  "analyticsSectionWhat": "Who and what",
  "@analyticsSectionWhat": {
    "description": "Section header over payees and items."
  },
  "analyticsSectionHome": "Your home",
  "@analyticsSectionHome": {
    "description": "Section header over stock, waste and expiry."
  },
  "analyticsSectionCommitments": "Already committed",
  "@analyticsSectionCommitments": {
    "description": "Section header over recurring commitments and assets."
  },
  "analyticsBySubtype": "By kind",
  "@analyticsBySubtype": {
    "description": "Query 1. \"Kind\" rather than \"subtype\": the schema's word is not the user's."
  },
  "analyticsByTag": "By tag",
  "@analyticsByTag": {
    "description": "Query 2."
  },
  "analyticsByTagNote": "A purchase with two tags counts in both, so these add up to more than the total",
  "@analyticsByTagNote": {
    "description": "The caveat belongs on the card: a reader comparing tag figures against the headline deserves to know why they differ."
  },
  "analyticsByMethod": "By payment method",
  "@analyticsByMethod": {
    "description": "Query 3."
  },
  "analyticsConcentration": "How concentrated",
  "@analyticsConcentration": {
    "description": "Query 22, with query 8's grocery share beneath it."
  },
  "analyticsTopShare": "{percent} of your spending sits in three kinds",
  "@analyticsTopShare": {
    "description": "Query 22's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsGroceryShare": "Groceries are {percent} of it",
  "@analyticsGroceryShare": {
    "description": "Query 8, stated beneath the concentration figure.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsTagChildren": "{count, plural, =1{1 tag inside} other{{count} tags inside}}",
  "@analyticsTagChildren": {
    "description": "Marks a parent tag that can be opened. One level only, which is all the schema permits.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsTagDirect": "{tag} on its own",
  "@analyticsTagDirect": {
    "description": "The parent tag's own spending, as a sibling of its children rather than folded into them.",
    "placeholders": {
      "tag": {}
    }
  },
  "analyticsTagBack": "Back to all tags",
  "@analyticsTagBack": {
    "description": "Tooltip on the in-place drill's back button."
  },
  "analyticsNothingSpent": "Nothing spent in this window",
  "@analyticsNothingSpent": {
    "description": "Empty state for a spend breakdown."
  },
  "analyticsNoTaggedSpend": "Tag a purchase and it will appear here",
  "@analyticsNoTaggedSpend": {
    "description": "Empty state for the tag breakdown: names the action, not the absence."
  },
  "analyticsNoMethodSpend": "Record how you paid and it will appear here",
  "@analyticsNoMethodSpend": {
    "description": "Empty state for the payment-method breakdown."
  },
  "analyticsIncomeVsExpense": "In and out",
  "@analyticsIncomeVsExpense": {
    "description": "Query 5."
  },
  "analyticsNeedTwoMonths": "Two months of records and the trend appears here",
  "@analyticsNeedTwoMonths": {
    "description": "Empty state: one month is a pair of figures, not a trend."
  },
  "analyticsNetFlow": "What you kept",
  "@analyticsNetFlow": {
    "description": "Query 6. Named for what the figure means rather than for the ledger it comes from."
  },
  "analyticsNetFlowNote": "Moving money between your own accounts does not count",
  "@analyticsNetFlowNote": {
    "description": "Explains why a transfer is absent: the ledger nets it to zero across its two legs."
  },
  "analyticsNoFlow": "Nothing moved in this window",
  "@analyticsNoFlow": {
    "description": "Empty state for net flow."
  },
  "analyticsBalanceTrend": "Balance over time",
  "@analyticsBalanceTrend": {
    "description": "Query 7."
  },
  "analyticsBalanceIn": "{account}, in {currency}",
  "@analyticsBalanceIn": {
    "description": "Names the account and its currency: this is the one figure on the screen not in the home currency, because converting each point would make the line move when rates moved.",
    "placeholders": {
      "account": {},
      "currency": {}
    }
  },
  "analyticsAccount": "Account",
  "@analyticsAccount": {
    "description": "Label on the balance-trend account picker."
  },
  "analyticsNoBalanceMovement": "No movement on this account in this window",
  "@analyticsNoBalanceMovement": {
    "description": "Empty state for the balance trend."
  },
  "analyticsHeatmap": "When you spend",
  "@analyticsHeatmap": {
    "description": "Query 21."
  },
  "analyticsByWeekday": "By day of week",
  "@analyticsByWeekday": {
    "description": "Heatmap segment."
  },
  "analyticsByDayOfMonth": "By date",
  "@analyticsByDayOfMonth": {
    "description": "Heatmap segment."
  },
  "analyticsTopPayees": "Who you paid most",
  "@analyticsTopPayees": {
    "description": "Query 4."
  },
  "analyticsNoPayees": "Name who you paid and they will appear here",
  "@analyticsNoPayees": {
    "description": "Empty state for top payees."
  },
  "analyticsTopItems": "What cost you most",
  "@analyticsTopItems": {
    "description": "Query 9."
  },
  "analyticsNoItemisedSpend": "Itemise a purchase and it will appear here",
  "@analyticsNoItemisedSpend": {
    "description": "Empty state for top items by spend."
  },
  "analyticsTopByQuantity": "What you buy most of",
  "@analyticsTopByQuantity": {
    "description": "Query 10."
  },
  "analyticsTopByQuantityNote": "Grouped by measure, because weight and count cannot be compared",
  "@analyticsTopByQuantityNote": {
    "description": "Explains the grouping: Law L8 makes cross-category comparison meaningless."
  },
  "analyticsNoQuantities": "Record how much you bought and it will appear here",
  "@analyticsNoQuantities": {
    "description": "Empty state for top items by quantity."
  },
  "analyticsPurchaseCount": "{count, plural, =1{1 purchase} other{{count} purchases}}",
  "@analyticsPurchaseCount": {
    "description": "How many times an item was bought in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsDearest": "The most you have paid",
  "@analyticsDearest": {
    "description": "Query 11."
  },
  "analyticsDearestItem": "Item",
  "@analyticsDearestItem": {
    "description": "Key on the dearest-purchase card."
  },
  "analyticsDearestPrice": "Unit price",
  "@analyticsDearestPrice": {
    "description": "Key on the dearest-purchase card. The figure is in the currency it was bought in, unconverted."
  },
  "analyticsDearestWhen": "When",
  "@analyticsDearestWhen": {
    "description": "Key on the dearest-purchase card, paired with a DateText."
  },
  "analyticsNoUnitPrices": "Record a unit price and this appears here",
  "@analyticsNoUnitPrices": {
    "description": "Empty state for the dearest purchase."
  },
  "analyticsAverageBasket": "Your average shop",
  "@analyticsAverageBasket": {
    "description": "Query 23."
  },
  "analyticsBasketValue": "Average value",
  "@analyticsBasketValue": {
    "description": "Key on the basket card."
  },
  "analyticsBasketLines": "Average items",
  "@analyticsBasketLines": {
    "description": "Key on the basket card."
  },
  "analyticsBasketCount": "Shops counted",
  "@analyticsBasketCount": {
    "description": "Key on the basket card. Counts the baskets that converted, which is what the average divides by."
  },
  "analyticsNoBaskets": "Record a grocery shop and it will appear here",
  "@analyticsNoBaskets": {
    "description": "Empty state for the basket card."
  },
  "analyticsInventoryValue": "What is on your shelves",
  "@analyticsInventoryValue": {
    "description": "Query 13."
  },
  "analyticsInventoryValueNote": "Right now, whatever window you have chosen",
  "@analyticsInventoryValueNote": {
    "description": "Explains why the range chip does not change this figure."
  },
  "analyticsBatchesValued": "{count, plural, =1{1 batch valued} other{{count} batches valued}}",
  "@analyticsBatchesValued": {
    "description": "How many batches had both a cost and a resolvable purchase unit.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsBatchesNoCost": "{count, plural, =1{1 batch has no cost} other{{count} batches have no cost}}",
  "@analyticsBatchesNoCost": {
    "description": "Uncosted stock, reported rather than omitted: a valuation that skipped it would look complete while understating the shelf.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoStockValue": "Record what a batch cost and its value appears here",
  "@analyticsNoStockValue": {
    "description": "Empty state for the inventory valuation."
  },
  "analyticsWaste": "What you threw away",
  "@analyticsWaste": {
    "description": "Query 14, one of the app's differentiating insights."
  },
  "analyticsNoWaste": "Nothing wasted in this window",
  "@analyticsNoWaste": {
    "description": "Empty state, and it is good news: worded as a fact rather than as missing data."
  },
  "analyticsExpiring": "Expiring within {days} days",
  "@analyticsExpiring": {
    "description": "Query 15.",
    "placeholders": {
      "days": {
        "type": "int"
      }
    }
  },
  "analyticsNothingExpiring": "Nothing expires soon",
  "@analyticsNothingExpiring": {
    "description": "Empty state for the expiry card."
  },
  "analyticsDaysLeft": "{days, plural, =1{1 day left} other{{days} days left}}",
  "@analyticsDaysLeft": {
    "description": "How long a batch has. Paired with a tone, because colour is never the only signal (Law U17).",
    "placeholders": {
      "days": {
        "type": "num"
      }
    }
  },
  "analyticsExpiredAlready": "Past its date",
  "@analyticsExpiredAlready": {
    "description": "Chip on a batch whose expiry has passed and still holds stock."
  },
  "analyticsLowStock": "Running low",
  "@analyticsLowStock": {
    "description": "Query 16."
  },
  "analyticsLowStockNote": "A count for today, not a history: stock levels are not kept over time",
  "@analyticsLowStockNote": {
    "description": "Explains why this is one figure rather than a trend."
  },
  "analyticsLowStockCount": "{count, plural, =1{1 item below its threshold} other{{count} items below their threshold}}",
  "@analyticsLowStockCount": {
    "description": "Query 16's figure.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsAsOf": "As of",
  "@analyticsAsOf": {
    "description": "Precedes a DateText on the low-stock count."
  },
  "analyticsNothingLow": "Nothing is running low",
  "@analyticsNothingLow": {
    "description": "Empty state for the low-stock card."
  },
  "analyticsCommitment": "Every month, before anything else",
  "@analyticsCommitment": {
    "description": "Query 17."
  },
  "analyticsCommitmentNote": "Bills and subscriptions only. Income is not netted off",
  "@analyticsCommitmentNote": {
    "description": "Explains the outflow-only filter: netting salary against rent would report a household as having no fixed costs."
  },
  "analyticsCommitmentCount": "{count, plural, =1{from 1 commitment} other{from {count} commitments}}",
  "@analyticsCommitmentCount": {
    "description": "How many active templates the monthly figure covers.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoCommitments": "Add a bill or subscription and it will appear here",
  "@analyticsNoCommitments": {
    "description": "Empty state for the commitment total."
  },
  "analyticsRecurringSplit": "Fixed against chosen",
  "@analyticsRecurringSplit": {
    "description": "Query 18."
  },
  "analyticsRecurring": "Fixed",
  "@analyticsRecurring": {
    "description": "Query 18's recurring side. The user's word, not the schema's."
  },
  "analyticsDiscretionary": "Chosen",
  "@analyticsDiscretionary": {
    "description": "Query 18's discretionary side."
  },
  "analyticsRecurringShare": "{percent} of your spending was already committed",
  "@analyticsRecurringShare": {
    "description": "Query 18's headline.",
    "placeholders": {
      "percent": {}
    }
  },
  "analyticsServiceCost": "What your things cost to keep",
  "@analyticsServiceCost": {
    "description": "Query 19. Includes disposed assets, which is the point of a status change rather than a delete."
  },
  "analyticsServiceCount": "{count, plural, =1{1 visit} other{{count} visits}}",
  "@analyticsServiceCount": {
    "description": "How many service records an asset has in the window.",
    "placeholders": {
      "count": {
        "type": "num"
      }
    }
  },
  "analyticsNoServiceCost": "Record a service or repair and it will appear here",
  "@analyticsNoServiceCost": {
    "description": "Empty state for the service-cost card."
  },
  "analyticsWarranty": "Warranties",
  "@analyticsWarranty": {
    "description": "Query 20."
  },
  "analyticsCovered": "Covered",
  "@analyticsCovered": {
    "description": "Chip on an asset still inside its warranty window."
  },
  "analyticsCoverageEnded": "Cover ended",
  "@analyticsCoverageEnded": {
    "description": "Chip on an asset whose warranty has run out."
  },
  "analyticsNoWarranties": "Add a warranty date and it will appear here",
  "@analyticsNoWarranties": {
    "description": "Empty state for the warranty card."
  },
  "analyticsEmptyTitle": "Nothing to show for this window",
  "@analyticsEmptyTitle": {
    "description": "Screen-level empty state. The house section stays visible beneath it, because stock is a \"right now\" figure."
  },
  "analyticsEmptyBody": "Widen the window above, or record something and it will appear here.",
  "@analyticsEmptyBody": {
    "description": "Names both ways out: on a fresh install the second is the answer, on a quiet month the first is."
  },
  "analyticsCacheClear": "Recalculate everything",
  "@analyticsCacheClear": {
    "description": "The clear-cache action, named for what the reader gets rather than for the table it empties."
  },
  "analyticsCacheClearing": "Recalculating…",
  "@analyticsCacheClearing": {
    "description": "The action's in-progress label."
  },
  "analyticsCacheExplain": "Some figures are kept between visits so this screen opens quickly. Clear them if a number looks stale.",
  "@analyticsCacheExplain": {
    "description": "Explains what the action does. The only place analytics_cache is ever visible (ARCH_5 §7.3)."
  },
  "analyticsCacheCleared": "Recalculated",
  "@analyticsCacheCleared": {
    "description": "Precedes a DateText giving when the cache was last cleared."
  },
  "analyticsCacheClearedSnack": "Figures recalculated",
  "@analyticsCacheClearedSnack": {
    "description": "Success snack. Same word as the button, per ARCH_5 §2.8."
  },
  "analyticsCacheFailed": "Could not clear the saved figures",
  "@analyticsCacheFailed": {
    "description": "Failure snack. Names what failed rather than apologising."
  },
  "analyticsDrillTitle": "Behind this figure",
  "@analyticsDrillTitle": {
    "description": "Fallback title for the drill-down while its label resolves."
  },
  "analyticsDrillTotal": "These come to",
  "@analyticsDrillTotal": {
    "description": "Precedes the drill-down's per-currency subtotals."
  },
  "analyticsDrillLoading": "Loading these transactions…",
  "@analyticsDrillLoading": {
    "description": "Semantics label on the drill-down's skeleton."
  },
  "analyticsDrillEmptyTitle": "Nothing here in this window",
  "@analyticsDrillEmptyTitle": {
    "description": "Drill-down empty state."
  },
  "analyticsDrillEmptyBody": "The window is set on the insights screen. Widen it and these may appear.",
  "@analyticsDrillEmptyBody": {
    "description": "Names the likely cause: the filter is what the reader just chose, the window is what they may have forgotten."
  },
  "analyticsDrillUnknownTitle": "This link does not point anywhere",
  "@analyticsDrillUnknownTitle": {
    "description": "Shown when the route's parameters name no filter this version knows."
  },
  "analyticsDrillUnknownBody": "Open insights and choose a figure to look behind.",
  "analyticsOtherSlices": "Everything else",
  "@analyticsOtherSlices": {
    "description": "The grouped remainder wedge of a donut, past the sixth slice. A ring of twelve slivers is not readable, so the tail becomes one wedge that says what it is."
  },
  "analyticsTopThree": "in three kinds",
  "@analyticsTopThree": {
    "description": "The quiet line under the percentage in the concentration donut's centre, saying what that percentage is of."
  },
  "@analyticsDrillUnknownBody": {
    "description": "Offers the way on rather than throwing: the route is reachable from outside the app."
  },
  "aboutHowItWorksHeader": "How it works",
  "aboutLicences": "Open source licences",
  "aboutLicencesHelp": "The libraries Alaya is built on.",
  "aboutOfflineBody": "Everything is stored on this device. Alaya only reaches the internet to fetch exchange rates, once a day.",
  "aboutStorageBody": "Your data is not encrypted, and no copy of it exists anywhere else unless you make a backup yourself.",
  "@aboutStorageBody": {
    "description": "The same threat model the lock screen states, in the place somebody comes looking for it. Two locations is not duplication: one is a decision point, the other is where a question gets answered."
  },
  "aboutTagline": "A finance and home manager that works entirely on your phone.",
  "accountCurrencyHeader": "Currency",
  "accountCurrencyLockedHelp": "Fixed, because changing it would reinterpret every amount already recorded here.",
  "@accountCurrencyLockedHelp": {
    "description": "Law L9 at its sharpest: the home currency is a display choice, but an account’s own currency is what its money is."
  },
  "accountCurrencyNewHelp": "What this account holds. It cannot be changed once you start recording against it.",
  "accountEditorEditTitle": "Edit account",
  "accountEditorSave": "Save account",
  "@accountEditorSave": {
    "description": "Names the thing, per archetype B — never a bare \"Save\"."
  },
  "accountEditorTitle": "New account",
  "accountIncludeInNetWorth": "Count in net worth",
  "accountIncludeInNetWorthHelp": "Off means the balance still shows here, but is left out of your total. Useful for an account you hold for someone else.",
  "@accountIncludeInNetWorthHelp": {
    "description": "ARCH_5 §7.2 requires the toggle be explained: without this line the reader cannot tell whether off means hidden or merely uncounted."
  },
  "accountKindBank": "Bank",
  "accountKindCard": "Card",
  "accountKindCash": "Cash",
  "accountKindHeader": "What kind?",
  "accountKindOther": "Other",
  "accountKindWallet": "Wallet",
  "accountNameLabel": "Name",
  "accountOpeningBalanceLabel": "Opening balance",
  "accountOpeningDateLabel": "True on",
  "@accountOpeningDateLabel": {
    "description": "Not \"date\": the question is which day the balance was correct, and \"date\" invites today by default."
  },
  "accountsAdd": "Add an account",
  "accountsArchive": "Archive this account",
  "accountsArchiveConfirmBody": "It will stop appearing when you record anything. Its history stays, and you can restore it here at any time.",
  "accountsArchiveConfirmTitle": "Archive this account?",
  "accountsArchiveHelp": "An archived account keeps all its history. It just stops appearing when you record something.",
  "@accountsArchiveHelp": {
    "description": "Says what survives, because \"archive\" does not tell the reader whether their transactions go with it."
  },
  "accountsArchived": "Account archived",
  "accountsArchivedChip": "Archived",
  "accountsArchivedHeader": "Archived",
  "accountsEmptyBody": "Add one so Alaya knows where your money is.",
  "accountsEmptyTitle": "No accounts yet",
  "accountsExcludedChip": "Not in net worth",
  "accountsLoading": "Loading your accounts…",
  "accountsMissingBody": "It may have been removed. Go back and pick another.",
  "@accountsMissingBody": {
    "description": "A stale deep link, or a row removed in another window. Stated rather than rendering a blank form that would silently create a second account on save."
  },
  "accountsMissingTitle": "That account is not here",
  "accountsRestore": "Restore this account",
  "accountsRestoreConfirmBody": "It will appear again everywhere you choose an account.",
  "@accountsRestoreConfirmBody": {
    "description": "Confirmed in both directions: restoring puts an account back into every picker, which is worth stating before it happens."
  },
  "accountsRestoreConfirmTitle": "Restore this account?",
  "accountsRestored": "Account restored",
  "accountsSaved": "Account saved",
  "actionBack": "Back",
  "actionContinue": "Continue",
  "appearanceModeDark": "Always dark",
  "appearanceModeHeader": "Light or dark",
  "appearanceModeLight": "Always light",
  "appearanceModeSystem": "Match my phone",
  "appearanceModeSystemHelp": "Follows your phone’s light and dark setting.",
  "appearancePaletteHeader": "Colours",
  "appearanceThemeLabHelp": "See every colour, spacing and text style the app uses.",
  "backupNotEncryptedWarning": "This backup is not encrypted. Anyone who opens this file can read every transaction, balance and account name. Only share it somewhere you trust.",
  "@backupNotEncryptedWarning": {
    "description": "ARCH_3 §3.4 verbatim, on every export confirmation — not in settings, not a tooltip. Corrected in 8B: the 8A wording was a paraphrase that dropped the third sentence."
  },
  "currenciesHomeLocked": "Cannot be turned off — your totals are added up in this.",
  "@currenciesHomeLocked": {
    "description": "Law L9: disabling it would leave the dashboard with no currency to aggregate into. Disabled rather than hidden, so it reads as an explanation and not a rendering fault."
  },
  "currenciesLoading": "Loading currencies…",
  "currenciesToggleFailed": "That could not be changed",
  "dataBackupHeader": "Backup",
  "dataExportBody": "Sends a copy of your data to WhatsApp, Drive, or anywhere else you choose.",
  "dataExportConfirmAction": "Share it",
  "dataExportConfirmTitle": "Share a backup?",
  "dataExportFailed": "The backup could not be made",
  "dataExportTitle": "Share a backup",
  "dataRestoreHeader": "Restore",
  "dataRestorePending": "Coming in the next update.",
  "@dataRestorePending": {
    "description": "Stated as not-yet-here rather than offered and broken: restore needs the Storage Access Framework picker and a merge strategy, both of which are 8B’s."
  },
  "dataRestoreTitle": "Restore from a backup",
  "lockBackspace": "Delete last digit",
  "lockBiometricFailed": "Not recognised. Enter your PIN instead.",
  "lockBiometricReason": "Unlock Alaya",
  "@lockBiometricReason": {
    "description": "Shown by the system prompt, so it must be localised before it reaches the plugin (Law U5)."
  },
  "lockEraseFailed": "The data could not be deleted. Your PIN is unchanged.",
  "@lockEraseFailed": {
    "description": "Says what did not change, so a failed erase does not leave the user unsure whether they are locked out of a half-wiped app."
  },
  "lockErasing": "Deleting everything on this device…",
  "@lockErasing": {
    "description": "The ten-failure auto-erase is running. It takes the whole screen, because there is nothing left to enter a PIN against."
  },
  "lockForgotPin": "I have forgotten my PIN",
  "lockHonestBody": "This PIN stops someone who picks up your unlocked phone from opening Alaya. It does not encrypt your data — anyone with access to the phone's files can still read them. Your phone's own lock screen is what protects the file itself.",
  "@lockHonestBody": {
    "description": "ARCH_3 §2.5, and the most important string in the app. No \"bank-grade\", no \"military-grade\", and no padlock glyph beside it: the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be dishonest and a Play listing risk."
  },
  "lockThrottledWhy": "The wait gets longer after each wrong attempt.",
  "@lockThrottledWhy": {
    "description": "Says why the delay exists, so a throttle reads as deliberate rather than as the app having frozen."
  },
  "lockTitle": "Enter your PIN",
  "lockUseBiometric": "Use fingerprint",
  "@lockUseBiometric": {
    "description": "The keypad key is an icon, so this is its Semantics label (ARCH_5 §2.7)."
  },
  "lockWrongPin": "That PIN is not right.",
  "onboardingAccountsBody": "Where do you keep your money? Add the ones you use.",
  "onboardingAccountsTitle": "Your accounts",
  "onboardingAddAccount": "Add an account",
  "onboardingCurrencyBody": "Which currency should Alaya add your totals up in?",
  "onboardingCurrencyNote": "This changes how totals are shown. It does not change any amount you have already recorded, and each account keeps its own currency.",
  "@onboardingCurrencyNote": {
    "description": "Law L9 in plain words. Somebody who thinks they are converting their history would be very surprised later."
  },
  "onboardingCurrencyTitle": "Your currency",
  "onboardingFinish": "Finish",
  "onboardingLoading": "Getting things ready…",
  "onboardingLockOnBody": "Alaya will ask for your PIN when you open it. You can change or remove it in Settings › Security.",
  "onboardingLockOnHeader": "Lock is on",
  "onboardingNext": "Next",
  "onboardingNoAccountsBody": "Add at least one so Alaya knows where your money is.",
  "onboardingNoAccountsTitle": "No accounts yet",
  "onboardingOpeningNote": "The opening balance is what was there on the date you give. Alaya needs both: a balance with no date cannot be placed in your ledger, and anything you record before that date would not be counted.",
  "@onboardingOpeningNote": {
    "description": "Anomaly A03. This is the paragraph that stops an opening balance being captured without its date."
  },
  "onboardingRemoveAccount": "Remove this account",
  "onboardingSaveAccounts": "Save accounts",
  "onboardingSecurityBody": "You can put a PIN on Alaya. This is optional and you can add one later.",
  "onboardingSecurityTitle": "Lock the app?",
  "onboardingSkip": "Skip",
  "onboardingSkipBody": "You can change all of this later in Settings.",
  "onboardingSkipTitle": "Skip setting up?",
  "onboardingTitle": "Welcome to Alaya",
  "payeeKindEmployer": "Employer",
  "payeeKindMerchant": "Shop",
  "payeeKindOther": "Other",
  "payeeKindPerson": "Person",
  "payeeKindUtility": "Utility",
  "payeeNameLabel": "Name",
  "payeePhoneOptionalLabel": "Phone (optional)",
  "@payeePhoneOptionalLabel": {
    "description": "Marked optional, because an unmarked second field reads as required and is the commonest reason a two-field sheet feels like a form."
  },
  "payeesAdd": "Add a payee",
  "payeesDelete": "Delete",
  "payeesDeleteConfirmBody": "Transactions that named them keep their record. They just stop being suggested.",
  "payeesDeleteConfirmTitle": "Delete this payee?",
  "payeesDeleteFailed": "That could not be deleted",
  "payeesDeleted": "Payee deleted",
  "payeesEditTitle": "Edit payee",
  "payeesEmptyBody": "These build up as you record who you paid.",
  "payeesEmptyTitle": "No payees yet",
  "payeesLoading": "Loading payees…",
  "payeesNoMatchBody": "Try part of the name.",
  "payeesNoMatchTitle": "No payees match that",
  "payeesSave": "Save payee",
  "payeesSaveFailed": "That could not be saved",
  "payeesSaved": "Payee saved",
  "payeesSearchHint": "Search payees",
  "paymentKindBankTransfer": "Bank transfer",
  "paymentKindCard": "Card",
  "paymentKindCash": "Cash",
  "paymentKindCheque": "Cheque",
  "paymentKindOther": "Other",
  "paymentKindUpi": "UPI",
  "paymentKindWallet": "Wallet",
  "paymentMethodNameLabel": "Name",
  "paymentMethodsAdd": "Add a payment method",
  "paymentMethodsDelete": "Delete",
  "paymentMethodsDeleteConfirmBody": "Transactions that used it keep their record of having done so. It just stops being offered.",
  "paymentMethodsDeleteConfirmTitle": "Delete this payment method?",
  "paymentMethodsDeleteFailed": "That could not be deleted",
  "paymentMethodsDeleted": "Payment method deleted",
  "paymentMethodsEditTitle": "Edit payment method",
  "paymentMethodsEmptyBody": "Add how you usually pay — cash, UPI, a card.",
  "paymentMethodsEmptyTitle": "No payment methods",
  "paymentMethodsLoading": "Loading payment methods…",
  "paymentMethodsSave": "Save payment method",
  "paymentMethodsSaveFailed": "That could not be saved",
  "paymentMethodsSaved": "Payment method saved",
  "paymentMethodsSystemChip": "Built in",
  "@paymentMethodsSystemChip": {
    "description": "Renameable but not removable, and the chip says so before the user hunts for a delete that is not there."
  },
  "pinSetupBackupBody": "You have just put a lock on this app. A backup means a forgotten PIN never costs you your records.",
  "pinSetupBackupHeader": "Make a backup?",
  "pinSetupBackupLater": "Not now",
  "pinSetupBackupNow": "Back up now",
  "pinSetupConfirmPrompt": "Enter it again",
  "pinSetupDone": "Your PIN is set",
  "pinSetupDoneBody": "Alaya will ask for it when you open the app, and again after a minute in the background.",
  "pinSetupEnterPrompt": "Choose a PIN",
  "pinSetupMismatch": "Those did not match. Start again.",
  "@pinSetupMismatch": {
    "description": "Both entries are cleared, because somebody who mistyped does not know which of the two was wrong."
  },
  "pinSetupRecoveryAck": "I have saved this code somewhere safe",
  "@pinSetupRecoveryAck": {
    "description": "The one confirmation, and it gates the button rather than warning after the fact."
  },
  "pinSetupRecoveryBody": "This is the only way back in if you forget your PIN. It is shown once and cannot be shown again.",
  "@pinSetupRecoveryBody": {
    "description": "True rather than cautious: PinService stores only a hash, so the app genuinely cannot redisplay it."
  },
  "pinSetupRecoveryCopied": "Recovery code copied",
  "pinSetupRecoveryCopy": "Copy code",
  "pinSetupRecoveryHeader": "Your recovery code",
  "pinSetupRecoveryWhereToKeep": "A password manager is a good place for it. A photo in your gallery is not.",
  "pinSetupTitle": "Set a PIN",
  "recoveryCodeLabel": "Recovery code",
  "recoveryCodePrompt": "Enter the recovery code you saved when you set your PIN.",
  "recoveryDone": "Your PIN has been changed",
  "recoveryEraseEverything": "Erase everything",
  "recoveryExportFirst": "Export a copy first",
  "recoveryExported": "A copy has been shared. Check it arrived before you erase.",
  "@recoveryExported": {
    "description": "Asks the user to verify: a backup nobody confirmed is not a backup."
  },
  "recoveryForgotBoth": "I do not have the recovery code either",
  "recoveryForgotBothBody": "Without your PIN or your recovery code there is no way back into this data. You can export a copy first, then erase everything and start again.",
  "@recoveryForgotBothBody": {
    "description": "The export is possible only because the database is plaintext — with encryption the copy would be unreadable without the key the user has lost. ARCH_4 records that as the improvement dropping encryption bought."
  },
  "recoveryForgotBothTitle": "Starting over",
  "recoveryNewPinPrompt": "Choose a new PIN",
  "recoveryTitle": "Forgotten PIN",
  "securityAutoEraseConfirmAction": "Turn it on",
  "securityAutoEraseConfirmTitle": "Turn on erase after repeated failures?",
  "securityAutoEraseFailed": "That could not be changed",
  "securityAutoEraseHeader": "If the PIN is entered wrongly",
  "securityAutoEraseOff": "Erase after repeated failures is off",
  "securityAutoEraseOn": "Erase after repeated failures is on",
  "securityAutoEraseTitle": "Erase everything after repeated failures",
  "securityAutoLockHeader": "Auto-lock",
  "securityAutoLockTitle": "Lock when I leave the app",
  "securityChangePin": "Change PIN",
  "securityChecking": "Checking…",
  "@securityChecking": {
    "description": "Neither branch is guessed: a row saying \"no PIN set\" for one frame to somebody who has one would be alarming for the wrong reason."
  },
  "securityPinHeader": "PIN",
  "securityRemovePin": "Remove PIN",
  "securityRemovePinConfirmBody": "Anyone who picks up your unlocked phone will be able to open Alaya. You will be asked for your current PIN next.",
  "securityRemovePinConfirmTitle": "Remove the PIN?",
  "securityRemovePinHelp": "You will need your current PIN to do this.",
  "securitySetPin": "Set a PIN",
  "securitySetPinHelp": "Alaya will ask for it when you open the app.",
  "settingsAbout": "About",
  "settingsAccounts": "Accounts",
  "settingsAppearance": "Appearance",
  "settingsCurrencies": "Currencies",
  "settingsData": "Data",
  "settingsGroupApp": "The app",
  "settingsGroupMoney": "Your money",
  "settingsGroupThings": "Your things",
  "settingsNoMatchBody": "Try a different word — \"dark\", \"PIN\" and \"backup\" all find something.",
  "@settingsNoMatchBody": {
    "description": "Names the search rather than the tree: \"no settings\" in front of a list the user can see is a lie. The examples are the keywords the rows actually match on."
  },
  "settingsNoMatchTitle": "Nothing matches that",
  "settingsPayees": "Payees",
  "settingsPaymentMethods": "Payment methods",
  "settingsSearchHint": "Search settings",
  "settingsSecurity": "Security",
  "settingsTags": "Tags",
  "settingsUnits": "Units",
  "tagColourHeader": "Colour",
  "tagColourHelp": "Optional. Kept as chosen, so it stays the same if you change the app’s palette later.",
  "@tagColourHelp": {
    "description": "Honest about the freeze: colorArgb is a stored int, so a tag coloured under one preset keeps that colour when the palette changes."
  },
  "tagColourNone": "No colour",
  "tagColourSwatch": "Use this colour",
  "@tagColourSwatch": {
    "description": "The swatches are colour-only, so each needs a Semantics label (Law U17)."
  },
  "tagEditorEditTitle": "Edit tag",
  "tagEditorSave": "Save tag",
  "tagEditorTitle": "New tag",
  "tagNameLabel": "Name",
  "tagParentHeader": "Group under",
  "tagParentHelp": "Optional. Grouping keeps long tag lists readable. Only one level deep.",
  "tagParentNone": "No group",
  "tagScopeDeposit": "Money in",
  "tagScopeDepositHelp": "Offered when you record money coming in.",
  "tagScopeInventory": "Items",
  "tagScopeInventoryHelp": "Offered on things you keep at home.",
  "tagScopeRecurring": "Recurring",
  "tagScopeRecurringHelp": "Offered on bills and subscriptions.",
  "tagScopeService": "Services",
  "tagScopeServiceHelp": "Offered on appliances and their service records.",
  "tagScopeShopping": "Shopping lists",
  "tagScopeShoppingHelp": "Used to group a shopping list under headings.",
  "tagScopeWithdrawal": "Money out",
  "tagScopeWithdrawalHelp": "Offered when you record spending.",
  "tagScopesHeader": "Where it appears",
  "tagScopesHelp": "A tag is only offered where you turn it on. This is what keeps \"Kitchen\" out of the list when you record your salary.",
  "@tagScopesHelp": {
    "description": "ARCH_5 §7.2’s allowedIn* row, said in the terms the requirement itself uses."
  },
  "tagsAdd": "Add a tag",
  "tagsDelete": "Delete this tag",
  "tagsDeleteConfirmBody": "Transactions and items already carrying it keep it in their history. It stops appearing when you tag something new.",
  "@tagsDeleteConfirmBody": {
    "description": "Says what survives, because a soft delete is not what \"delete\" usually promises (ARCH_3 §4)."
  },
  "tagsDeleteConfirmTitle": "Delete this tag?",
  "tagsDeleteHelp": "Anything already tagged keeps its history. The tag just stops being offered.",
  "tagsDeleted": "Tag deleted",
  "tagsEmptyBody": "Tags let you group things across accounts — \"Kitchen\", \"Car\", \"Diwali\".",
  "tagsEmptyTitle": "No tags yet",
  "tagsLoading": "Loading tags…",
  "tagsMissingBody": "It may have been deleted. Go back and pick another.",
  "tagsMissingTitle": "That tag is not here",
  "tagsNoScopesWarning": "This tag is not offered anywhere. Turn on at least one place below, or it will never appear.",
  "@tagsNoScopesWarning": {
    "description": "A tag with no scopes cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly the dead row somebody would hunt for in the pickers first."
  },
  "tagsSaved": "Tag saved",
  "tagsSystemChip": "Built in",
  "unitBaseGrams": "grams",
  "unitBaseMillilitres": "millilitres",
  "unitBasePieces": "pieces",
  "unitCategoryHeader": "What does it measure?",
  "unitCategoryNewHelp": "Choose carefully: this cannot be changed later.",
  "unitCodeHelp": "What you will see beside a quantity — kg, ml, pc.",
  "unitCodeLabel": "Short code",
  "unitCodeLockedHelp": "Fixed once the unit exists, because other records point at it.",
  "unitEditorEditTitle": "Edit unit",
  "unitEditorSave": "Save unit",
  "unitEditorTitle": "New unit",
  "unitFactorHeader": "How big is it?",
  "unitFactorMustBePositive": "That has to be more than zero.",
  "@unitFactorMustBePositive": {
    "description": "Guarded rather than trusted: a zero factor would convert every quantity in the unit to nothing and divide the inventory valuation by zero."
  },
  "unitFactorThisUnit": "this unit",
  "@unitFactorThisUnit": {
    "description": "Stands in for the name while the field is still empty, so the question reads as a sentence either way."
  },
  "unitFactorVaries": "It varies — I cannot give one number",
  "unitNameLabel": "Name",
  "unitVariesBack": "Actually, I can give a number",
  "@unitVariesBack": {
    "description": "A way back, for somebody who realises on reading this that they can state an amount."
  },
  "unitVariesCreateItem": "Create an item instead",
  "unitVariesInsteadBody": "Add \"Biscuit packet\" as its own item, counted in pieces. Then two packets is two of that item, and Alaya can price and track them properly.",
  "unitVariesInsteadTitle": "Make it an item instead",
  "unitVariesTitle": "Then it is not a unit",
  "unitVariesWhy": "A unit has to be the same amount every time. One packet of biscuits and one packet of rice are different weights, so Alaya could not add two packets together or work out what one cost.",
  "@unitVariesWhy": {
    "description": "ARCH_1 §5.3 explained by consequence rather than by quoting the rule. This is what makes the alternative obviously better instead of merely mandated."
  },
  "unitsAdd": "Add a unit",
  "unitsCategoriesFixedNote": "Weight, volume and count are the only three kinds there are. Alaya never converts between them, so a kilo can never become a litre by accident.",
  "@unitsCategoriesFixedNote": {
    "description": "ARCH_1 §5.3 and Law L8, stated where somebody about to add a unit reads it before trying rather than as a refusal afterwards."
  },
  "unitsDelete": "Delete this unit",
  "unitsDeleteConfirmBody": "Anything already bought in this unit keeps its quantity, but that quantity would no longer be readable. Only delete a unit you have not used.",
  "@unitsDeleteConfirmBody": {
    "description": "The R18 failure from the other direction: a quantity whose unit has gone cannot be converted or valued."
  },
  "unitsDeleteConfirmTitle": "Delete this unit?",
  "unitsDeleteHelp": "Only possible while nothing is measured in it.",
  "unitsDeleted": "Unit deleted",
  "unitsEmptyBody": "Alaya ships with the common ones. Add one if you measure something differently.",
  "unitsEmptyTitle": "No units",
  "unitsLoading": "Loading units…",
  "unitsMissingBody": "It may have been deleted. Go back and pick another.",
  "unitsMissingTitle": "That unit is not here",
  "unitsSaved": "Unit saved",
  "unitsSystemChip": "Built in",
  "currenciesRowSubtitle": "{symbol} · {digits, plural, =0{no decimal places} =1{1 decimal place} other{{digits} decimal places}}",
  "@currenciesRowSubtitle": {
    "description": "The precision matters to the reader: JPY has none, so an amount typed as 1200 is ¥1,200 and not ¥12.00.",
    "placeholders": {
      "symbol": {
        "type": "String"
      },
      "digits": {
        "type": "int"
      }
    }
  },
  "currenciesRowTitle": "{code} · {name}",
  "@currenciesRowTitle": {
    "description": "A currency row: the code first, because it is what the pickers show.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "name": {
        "type": "String"
      }
    }
  },
  "dataExportDone": "Backup saved as {fileName}",
  "@dataExportDone": {
    "description": "Names the file, because a backup the user cannot identify later is one they will not trust when they need it (ARCH_3 §3.4).",
    "placeholders": {
      "fileName": {
        "type": "String"
      }
    }
  },
  "lockThrottled": "Too many attempts. Try again in {time}",
  "@lockThrottled": {
    "description": "The countdown ticks. Formatted in Dart as m:ss, because a plural on \"second\" cannot express 1:05.",
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "onboardingCurrencyChip": "{code} {symbol}",
  "@onboardingCurrencyChip": {
    "placeholders": {
      "code": {
        "type": "String"
      },
      "symbol": {
        "type": "String"
      }
    }
  },
  "onboardingStepOf": "Step {step} of {total}",
  "@onboardingStepOf": {
    "description": "Words and a count rather than dots: the one question people abandon a setup flow over is how long it will take.",
    "placeholders": {
      "step": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "pinSetupLength": "{length} digits",
  "@pinSetupLength": {
    "placeholders": {
      "length": {
        "type": "int"
      }
    }
  },
  "recoveryTypeToConfirm": "Type {word} to confirm",
  "@recoveryTypeToConfirm": {
    "description": "The word is passed in from DataTransferPort.eraseConfirmationWord and is deliberately not translated, so a support article can tell anyone what to type.",
    "placeholders": {
      "word": {
        "type": "String"
      }
    }
  },
  "securityAutoEraseBody": "When on, {count} wrong PIN attempts in a row will delete everything on this device.",
  "@securityAutoEraseBody": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoEraseConfirmBody": "After {count} failed attempts, every account, transaction and item on this device is deleted. There is no undo, and no copy unless you have made a backup.",
  "@securityAutoEraseConfirmBody": {
    "description": "The scary confirm names the number. A generic \"are you sure?\" would not earn consent to a setting that destroys a household’s records.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "securityAutoLockBody": "Locks again after {seconds} seconds in the background.",
  "@securityAutoLockBody": {
    "description": "Stated rather than configurable in 8A: autoLockDelay is a constant, and a picker writing a setting nothing reads would be a dead control.",
    "placeholders": {
      "seconds": {
        "type": "int"
      }
    }
  },
  "settingsAccountCount": "{count, plural, =0{No accounts} =1{1 account} other{{count} accounts}}",
  "@settingsAccountCount": {
    "description": "Archived accounts included, because this row is the only way to reach one and restore it.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsCurrencyCount": "{enabled} of {total} enabled",
  "@settingsCurrencyCount": {
    "placeholders": {
      "enabled": {
        "type": "int"
      },
      "total": {
        "type": "int"
      }
    }
  },
  "settingsPayeeCount": "{count, plural, =0{No payees} =1{1 payee} other{{count} payees}}",
  "@settingsPayeeCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsPaymentMethodCount": "{count, plural, =0{No payment methods} =1{1 payment method} other{{count} payment methods}}",
  "@settingsPaymentMethodCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsTagCount": "{count, plural, =0{No tags} =1{1 tag} other{{count} tags}}",
  "@settingsTagCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "settingsUnitCount": "{count, plural, =0{No units} =1{1 unit} other{{count} units}}",
  "@settingsUnitCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "unitFactorHelp": "One of this unit has to be the same number of {base} every time.",
  "@unitFactorHelp": {
    "description": "The condition for being a unit at all. Somebody who reads this and cannot meet it has found the \"make it an item\" path.",
    "placeholders": {
      "base": {
        "type": "String"
      }
    }
  },
  "unitFactorQuestion": "How many {base} is one {unit}?",
  "@unitFactorQuestion": {
    "description": "Asked in base units, never in the stored thousandths — reproducing that arithmetic is what ARCH_4 R18 got wrong three times.",
    "placeholders": {
      "base": {
        "type": "String"
      },
      "unit": {
        "type": "String"
      }
    }
  },
  "unitsEquals": "1 {code} = {amount} {base}",
  "@unitsEquals": {
    "description": "What the unit is, assembled from the stored thousandths so the reader never meets them.",
    "placeholders": {
      "code": {
        "type": "String"
      },
      "amount": {
        "type": "String"
      },
      "base": {
        "type": "String"
      }
    }
  },
  "unitsRowTitle": "{name} ({code})",
  "@unitsRowTitle": {
    "placeholders": {
      "name": {
        "type": "String"
      },
      "code": {
        "type": "String"
      }
    }
  },
  "attachmentsAdd": "Add an attachment",
  "attachmentsAddFailed": "That could not be attached",
  "attachmentsAdded": "Attached",
  "attachmentsChoosePhoto": "Choose a photo",
  "@attachmentsChoosePhoto": {
    "description": "Not \"take a photo\": capture needs image_picker, which ARCH_1 §7 does not pin."
  },
  "attachmentsDelete": "Remove",
  "attachmentsDeleteConfirmBody": "The file is deleted from this phone. Backups you have already made still contain it.",
  "attachmentsDeleteConfirmTitle": "Remove this attachment?",
  "attachmentsDeleteFailed": "That could not be removed",
  "attachmentsDeleted": "Attachment removed",
  "attachmentsMissing": "That file is missing from this phone.",
  "attachmentsNone": "Nothing attached",
  "attachmentsOpen": "Open attachment",
  "attachmentsStoredLocally": "Kept on this phone only, and included in your backups.",
  "backupConfirmAction": "Make the backup",
  "backupConfirmTitle": "Make a backup?",
  "backupDone": "Backup saved",
  "backupFailed": "The backup could not be made",
  "backupForget": "Forget",
  "backupForgetConfirmBody": "This removes it from the list only. The backup file itself stays wherever you put it — Alaya cannot reach into your Drive or your chats.",
  "@backupForgetConfirmBody": {
    "description": "Says what does *not* happen: \"remove\" over a backup reads as deleting the file."
  },
  "backupForgetConfirmTitle": "Forget this entry?",
  "backupForgetFailed": "That entry could not be removed",
  "backupForgotten": "Entry removed",
  "backupHistoryEmptyBody": "Make one now, and keep it somewhere that is not this phone.",
  "@backupHistoryEmptyBody": {
    "description": "Says where, because a backup sitting on the device it protects is not a backup."
  },
  "backupHistoryEmptyTitle": "No backups yet",
  "backupHistoryHeader": "Backups you have made",
  "backupHistoryLoading": "Loading your backups…",
  "backupMakeHeader": "Make a backup",
  "backupRestoreBody": "Merge a backup into what you have, or replace everything with it.",
  "backupRestoreHeader": "Restore",
  "backupRestoreTitle": "Restore from a backup",
  "backupSaveBody": "Choose where to put it. Alaya needs no storage permission — you pick the folder.",
  "backupSaveTitle": "Save a copy",
  "backupShareBody": "Send it to WhatsApp, Drive, or anywhere else.",
  "backupShareTitle": "Share a copy",
  "backupTitle": "Backup",
  "reminderKindExpiry": "Things going off",
  "reminderKindExpiryHelp": "Food and medicine reaching their use-by date.",
  "reminderKindLowStock": "Running low",
  "reminderKindLowStockHelp": "Not offered as a reminder: being low on something has no date, so it would arrive every morning until you shopped.",
  "@reminderKindLowStockHelp": {
    "description": "The row exists because the enum does; the help says why it is not in the digest."
  },
  "reminderKindRecurring": "Bills and subscriptions",
  "reminderKindRecurringHelp": "When a recurring payment falls due.",
  "reminderKindService": "Appliance servicing",
  "reminderKindServiceHelp": "When something is due for its next service.",
  "reminderKindWarranty": "Warranties ending",
  "reminderKindWarrantyHelp": "Before a warranty runs out, while you can still use it.",
  "remindersBlocked": "Notifications are turned off for Alaya. Turn them on in your phone’s Settings › Apps › Alaya › Notifications.",
  "@remindersBlocked": {
    "description": "Names the place. \"Notifications are blocked\" without saying where is a dead end."
  },
  "remindersDenied": "Alaya needs permission to send notifications.",
  "remindersDigestExplainer": "Alaya sends one message a day about what is coming up — not a notification for every item.",
  "@remindersDigestExplainer": {
    "description": "ARCH_3 §7’s \"fewer, better notifications\", stated before the toggles so somebody knows what turning one on means."
  },
  "remindersDigestRow": "Daily summary",
  "remindersKindsHeader": "What to remind me about",
  "remindersLoading": "Loading your reminders…",
  "remindersNoneScheduledBody": "Turn on a reminder above and Alaya will show what it has planned here.",
  "@remindersNoneScheduledBody": {
    "description": "Explains rather than apologises: empty is the normal state with everything off."
  },
  "remindersNoneScheduledTitle": "Nothing scheduled",
  "remindersScheduledHeader": "Currently scheduled",
  "remindersTimeHeader": "When",
  "remindersTimeSaved": "Reminder time changed",
  "remindersTimeTitle": "Daily summary time",
  "remindersTitle": "Reminders",
  "remindersToggleFailed": "That could not be changed",
  "restoreApplyMerge": "Merge the backup",
  "restoreApplyReplace": "Replace everything",
  "restoreChooseAnother": "Choose another file",
  "restoreChooseFile": "Choose a file",
  "restoreChosenHeader": "Chosen file",
  "restoreContinueReplace": "Continue to replace",
  "restoreDone": "Restored",
  "restoreLockNotRestored": "Your PIN is never restored. It is kept outside the backup, so opening someone else’s backup can never change who can open this app.",
  "@restoreLockNotRestored": {
    "description": "ARCH_3 §3.2’s last line, on the one screen where somebody might expect otherwise. Shown at all three stages."
  },
  "restoreMergeBody": "Adds what the backup has and updates what is newer. Nothing you have now is lost.",
  "@restoreMergeBody": {
    "description": "The default, and the description says why: merge keeps rows the backup does not have."
  },
  "restoreMergeTitle": "Merge",
  "restoreModeHeader": "How should it be applied?",
  "restoreNotADatabase": "That file is not an Alaya backup.",
  "restorePickBody": "Choose a backup file. Alaya will check it before anything changes.",
  "restoreReplaceBody": "Throws away what is on this phone and uses the backup instead.",
  "restoreReplaceTitle": "Replace everything",
  "restoreReplaceWarning": "Everything currently on this phone will be thrown away and replaced by the backup. Anything recorded since that backup was made will be gone.",
  "restoreRollbackAvailable": "Restored the wrong file? You can put your previous data back.",
  "restoreRollbackPromise": "Alaya takes a snapshot of your current data first, so you can undo this straight afterwards.",
  "@restoreRollbackPromise": {
    "description": "Said before the typed confirmation, because somebody who knows there is a way back reads the warning as information rather than a threat."
  },
  "restoreTitle": "Restore",
  "restoreUndo": "Undo the replace",
  "supportConsentUnavailable": "Adverts need a choice about personalisation that could not be loaded right now. Nothing has been requested.",
  "@supportConsentUnavailable": {
    "description": "Says what happened rather than showing a button that cannot work: without consent settled, no ad is requested at all."
  },
  "supportIntro": "Alaya is free, works offline, and has no accounts to sign up for. If it is useful to you, there are two ways to help.",
  "supportLoading": "Loading…",
  "supportNoAd": "No advert available right now",
  "supportNoPaidFeatures": "Nothing here unlocks anything. There are no paid features — the whole app is already yours.",
  "@supportNoPaidFeatures": {
    "description": "Keeps this a tip rather than a paywall wearing a friendly label, and says so where somebody decides."
  },
  "supportThanks": "Thank you. That genuinely helps.",
  "supportTipBody": "A one-time thank-you through the Play Store. It is not a subscription.",
  "supportTipHeader": "Leave a tip",
  "supportTipUnavailable": "Tips are not available on this device right now.",
  "supportTitle": "Support Alaya",
  "supportWatchAction": "Watch an advert",
  "supportWatchBody": "One advert, when you choose to. Alaya never shows one anywhere else in the app.",
  "@supportWatchBody": {
    "description": "True by construction: one file imports the SDK and only this screen starts it."
  },
  "supportWatchHeader": "Watch a short advert",
  "trashDeletedOn": "Deleted",
  "trashEmptyBody": "Things you delete are kept here for 30 days before they go for good.",
  "trashEmptyNow": "Empty now",
  "trashEmptyNowConfirmBody": "Everything in the trash is deleted permanently. This is not the trash — there is nowhere left for it to go.",
  "@trashEmptyNowConfirmBody": {
    "description": "The only hard delete a user can reach, so the body says it plainly."
  },
  "trashEmptyNowConfirmTitle": "Empty the trash?",
  "trashEmptyTitle": "The trash is empty",
  "trashGoesOn": "· kept for 30 days",
  "@trashGoesOn": {
    "description": "Every row says when it goes: a trash that silently empties is one people stop trusting."
  },
  "trashKindAsset": "Appliances",
  "trashKindItem": "Items",
  "trashKindPayee": "Payees",
  "trashKindRecurring": "Recurring",
  "trashKindShoppingList": "Shopping lists",
  "trashKindTag": "Tags",
  "trashKindTransaction": "Transactions",
  "trashLoading": "Loading the trash…",
  "trashNoMatchBody": "Remove a filter to see the rest.",
  "trashNoMatchTitle": "Nothing matches that filter",
  "trashPurgeConfirmBody": "It will not go back to the trash. There is no undo.",
  "trashPurgeConfirmTitle": "Delete this for good?",
  "trashPurgeFailed": "That could not be deleted",
  "trashPurgeOne": "Delete for good",
  "trashPurgedOne": "Deleted for good",
  "trashRestore": "Restore",
  "trashRestoreFailed": "That could not be restored",
  "trashRestored": "Restored",
  "trashTitle": "Trash",
  "backupDoneNamed": "Backup saved as {fileName}",
  "@backupDoneNamed": {
    "description": "Names the file, because a backup you cannot identify later is one you will not trust when you need it.",
    "placeholders": {
      "fileName": {
        "type": "String"
      }
    }
  },
  "backupHistorySize": "· {size}",
  "@backupHistorySize": {
    "description": "The unit changes with the magnitude, so the number is formatted in Dart — a translator cannot choose between KB and MB inside a placeholder.",
    "placeholders": {
      "size": {
        "type": "String"
      }
    }
  },
  "remindersTimeBody": "Sent at {time} each day",
  "@remindersTimeBody": {
    "placeholders": {
      "time": {
        "type": "String"
      }
    }
  },
  "restoreDoneDetail": "{tables, plural, =1{1 table restored} other{{tables} tables restored}}",
  "@restoreDoneDetail": {
    "placeholders": {
      "tables": {
        "type": "int"
      }
    }
  },
  "restoreNewerSchema": "That backup is from a newer version of Alaya (version {backup}) than this app understands (version {app}). Update Alaya and try again.",
  "@restoreNewerSchema": {
    "description": "ARCH_3 §3.2’s gate, stated with both numbers. A refusal without them is one nobody can act on.",
    "placeholders": {
      "backup": {
        "type": "int"
      },
      "app": {
        "type": "int"
      }
    }
  },
  "restoreTypeToConfirm": "Type {word} to confirm",
  "@restoreTypeToConfirm": {
    "description": "The word is not translated, so a support article can tell anyone what to type.",
    "placeholders": {
      "word": {
        "type": "String"
      }
    }
  },
  "supportTipAction": "Leave a tip · {price}",
  "@supportTipAction": {
    "description": "The store’s own formatted price, never reformatted: Play localises it for the user’s account, which need not match this app’s home currency.",
    "placeholders": {
      "price": {
        "type": "String"
      }
    }
  },
  "trashPurged": "{count, plural, =0{Nothing to delete} =1{1 item deleted for good} other{{count} items deleted for good}}",
  "@trashPurged": {
    "description": "\"For good\" rather than \"deleted\", because this is the one hard delete in the app.",
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "dataBackupRowBody": "Save a copy, share it, or restore from one.",
  "dataTrashRowBody": "Things you delete are kept here for 30 days.",
  "settingsRemindersHelp": "One daily summary of what is coming up.",
  "settingsSupportHelp": "Optional, and nothing here unlocks anything.",
  "@settingsSupportHelp": {
    "description": "Says on the row itself that this is not a paywall, so the entry cannot read as one."
  },
  "settingsTrashCount": "{count, plural, =0{Nothing in the trash} =1{1 item} other{{count} items}}",
  "@settingsTrashCount": {
    "placeholders": {
      "count": {
        "type": "int"
      }
    }
  },
  "supportWatchTooltip": "Watch an advert to support Alaya",
  "@supportWatchTooltip": {
    "description": "The app bar action. Says what the tap does, because a joined-hands icon alone does not — and no advert is fetched until it is pressed."
  },
  "ledgerRowSemantics": "{title}, {amount}",
  "@ledgerRowSemantics": {
    "description": "A ledger row spoken as one thing (ARCH_5 §6). The comma is the pause a screen reader takes, which is why it is punctuation rather than a word.",
    "placeholders": {
      "title": {
        "type": "String"
      },
      "amount": {
        "type": "String"
      }
    }
  },
  "ledgerRowSemanticsDetailed": "{title}, {amount}, {detail}",
  "@ledgerRowSemanticsDetailed": {
    "description": "The same, with the row’s metadata line — an account, a payment method or a review flag.",
    "placeholders": {
      "title": {
        "type": "String"
      },
      "amount": {
        "type": "String"
      },
      "detail": {
        "type": "String"
      }
    }
  }
}
```

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

         PHASE 9 GATE: verify this in the BUILT artefact, not here. A manifest merger, or any library
         shipping allowBackup="true", can flip it silently, so the source is not evidence.
         The command is in PHASE_09_POLISH.md, not here: an XML comment may not contain a double hyphen,
         and every aapt2 invocation needs one. -->

    <!-- Phase 9. Declared explicitly rather than left to the manifest merger.
         `google_mobile_ads` adds AD_ID on its own, which means the permission appears in the built artefact
         while appearing nowhere in this project — and a permission nobody can find in source is one nobody
         remembers to declare on the Play data-safety form. Alaya *does* need it: the Support screen requests
         adverts, and Play requires the declaration for any app that reads the advertising ID.

         Removing it would mean non-personalised ads only. That is a revenue decision, not a technical one; if
         it is ever taken, replace this with tools:node="remove" and update the data-safety form. -->
    <uses-permission android:name="com.google.android.gms.permission.AD_ID" />

    <!-- Phase 9. Declared explicitly for the same reason as AD_ID above: `flutter_local_notifications` adds it
         through the manifest merger, which means it exists in the built artefact and nowhere in this project,
         and a permission nobody can find in source is one nobody reasons about.

         Required from Android 13 (API 33). Without it `requestNotificationsPermission()` returns false without
         ever showing a dialog, which looks exactly like a user declining. ARCH_3 §7 requests it on the first
         reminder switch-on and never on launch.

         SCHEDULE_EXACT_ALARM is deliberately NOT declared: the digest uses
         AndroidScheduleMode.inexactAllowWhileIdle, Android 14 restricts the exact permission, and Play asks
         apps to justify it. A digest arriving at 9:07 instead of 9:00 has lost nothing. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />

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

## Notifications did not work at all, and Phase 9 found it

**`FlutterLocalNotificationsPlugin.initialize()` was never called.** Not in the scheduler, not in the background
isolate, nowhere in the project. `zonedSchedule` on an uninitialised plugin **fails quietly rather than
throwing**, so the daily digest had never fired on a device while every test passed — the tests use a fake, and a
fake has nothing to initialise.

It surfaced while writing the branding guide, because initialisation is where the notification icon is declared
and the icon was not there to find.

Three gaps, not one:

| Gap | Consequence |
|---|---|
| No `initialize()` in `LocalNotificationScheduler` | Nothing scheduled, silently |
| No initialisation in `daily_job.dart`'s isolate | `FlutterLocalNotificationsPlugin` is **not** a singleton across isolates — the UI's instance does not exist in a `workmanager` callback, so even a fixed UI path would leave the daily recompute dead |
| `POST_NOTIFICATIONS` declared nowhere in source | Arrives via the manifest merger, so it works — but a permission nobody can find in the project is one nobody reasons about. Same argument as AD_ID |

**`_ensurePlugin()` is lazy and idempotent**, called from all four entry points — schedule, cancel, permission
check, permission request. Lazy because ARCH_4 §5.1's lazy-loading principle applies here too: an install where
nobody turns on a reminder should not initialise a notification channel.

**The icon is a vector, not five PNGs.** Android flattens a notification icon to a white silhouette on API 21+,
so `@mipmap/ic_launcher` renders as a solid white square. `@drawable/ic_notification` is white-on-transparent by
construction, sharp at every density from one file, and needs no regeneration when the artwork changes.

**`SCHEDULE_EXACT_ALARM` is still not declared, deliberately.** The digest uses `inexactAllowWhileIdle`, Android
14 restricts the exact permission, and Play asks apps to justify it. A digest at 9:07 has lost nothing.

### One R22 surface I could not verify

`initialize` is written in its documented form — `initialize(InitializationSettings)`, settings positional. **On
this installed version `zonedSchedule` and `cancel` are both named-only**, which is unusual and means `initialize`
may be too. If the analyzer objects, the fix is one line:

`await _plugin.initialize(settings: const InitializationSettings(...))`

I have guessed wrong at this plugin's surface twice already, so I am flagging it rather than asserting it.

### `lib/data/reminders/local_notification_scheduler.dart`

```dart
import 'package:drift/drift.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/domain/repositories/settings_repository.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';
import 'package:alaya/domain/services/reminders/reminder_port.dart';

/// The production [ReminderPort]: one daily digest, scheduled inexactly, in the device's own timezone.
///
/// **The only file in this phase that imports `flutter_local_notifications` or `timezone`.** Both need a platform
/// channel, so neither runs in a widget test — which is the whole reason `ReminderPort` exists. This is also the
/// largest surface in the phase that could not be compiled against (ARCH_4 R22): `zonedSchedule`,
/// `AndroidScheduleMode`, and `requestNotificationsPermission` have each moved between major versions of the
/// plugin. 8A's `local_auth` took two wrong guesses before compiling; expect at least one here, and expect it to
/// cost this file and nothing else.
///
/// **One notification, not a stream of pings** (ARCH_3 §7). Every enabled kind is folded into a single sentence —
/// *"3 items expire this week, 1 bill due tomorrow"* — delivered once a day at a time the user picked. The
/// contract cannot express a per-item ping, and neither can this.
///
/// **Inexact, always.** `AndroidScheduleMode.inexactAllowWhileIdle` and never `exactAllowWhileIdle`: Android 14
/// restricts `SCHEDULE_EXACT_ALARM` and Play asks why an app needs it. A digest that arrives at 9:07 instead of
/// 9:00 has lost nothing.
final class LocalNotificationScheduler implements ReminderPort {
  /// Creates the scheduler.
  LocalNotificationScheduler({
    required FlutterLocalNotificationsPlugin plugin,
    required AlayaDatabase database,
    required NotificationScheduleDao scheduleDao,
    required CalendarAggregator calendar,
    required SettingsRepository settings,
    required UidGenerator uids,
    required Clock clock,
  })  : _plugin = plugin,
        _db = database,
        _scheduleDao = scheduleDao,
        _calendar = calendar,
        _settings = settings,
        _uids = uids,
        _clock = clock;

  final FlutterLocalNotificationsPlugin _plugin;
  final AlayaDatabase _db;
  final NotificationScheduleDao _scheduleDao;
  final CalendarAggregator _calendar;
  final SettingsRepository _settings;
  final UidGenerator _uids;
  final Clock _clock;

  /// The `app_settings` key holding which reminder kinds are on.
  ///
  /// Stored as a comma-separated list of names rather than one key per kind: adding a fifth kind then needs no
  /// migration, and an unknown name in the list is ignored rather than fatal.
  static const String enabledKindsKey = 'reminders.enabledKinds';

  /// The `app_settings` key holding the digest time as `HH:mm`.
  static const String digestTimeKey = 'reminders.digestTime';

  /// The Android notification id the daily digest always uses.
  ///
  /// **Fixed, so rescheduling replaces rather than accumulates.** Every other id comes from
  /// `NotificationScheduleDao.nextAndroidNotificationId`; the digest is the one notification that is always
  /// exactly one, so it gets a constant and cancelling it needs no lookup.
  static const int digestNotificationId = 1;

  /// How far ahead the digest looks.
  ///
  /// A week, because that is the horizon a sentence can usefully summarise. A month's worth of counts reads as a
  /// backlog rather than a nudge, and a day's is too late to act on an expiry.
  static const Duration horizon = Duration(days: 7);

  /// The reference type recorded against the digest's `notification_schedule` row.
  static const String digestRefType = 'digest';

  /// The status-bar icon: white on transparency, at `android/app/src/main/res/drawable/ic_notification.xml`.
  static const String notificationIcon = '@drawable/ic_notification';

  bool _timezonesReady = false;
  bool _pluginReady = false;

  Future<void> _ensureTimezones() async {
    if (_timezonesReady) return;
    tz_data.initializeTimeZones();
    _timezonesReady = true;
  }

  /// Brings the notification plugin up, once.
  ///
  /// **This was missing entirely until Phase 9, and nothing worked without it.** `zonedSchedule` on an
  /// uninitialised plugin does not throw — it fails quietly — so the digest had never fired on a device while
  /// every test passed, because the tests use a fake and the fake has nothing to initialise.
  ///
  /// **The icon is a purpose-made drawable, not `@mipmap/ic_launcher`.** Android flattens a notification icon to
  /// a white silhouette on API 21 and above, discarding colour entirely, so pointing this at the launcher icon
  /// renders a solid white square in the status bar. `@drawable/ic_notification` is white-on-transparent by
  /// construction.
  Future<void> _ensurePlugin() async {
    if (_pluginReady) return;
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings(notificationIcon),
      ),
    );
    _pluginReady = true;
  }

  @override
  Stream<ReminderSettings> watchSettings() =>
      _db.select(_db.appSettings).watch().asyncMap((_) => _readSettings());

  Future<ReminderSettings> _readSettings() async {
    final stored = await _settings.readValue(enabledKindsKey);
    final time = await _settings.readValue(digestTimeKey);
    final enabled = <NotificationKind>{};
    for (final name in (stored ?? '').split(',')) {
      for (final kind in reminderKinds) {
        if (kind.name == name.trim()) enabled.add(kind);
      }
    }
    final parts = (time ?? '09:00').split(':');
    return ReminderSettings(
      enabled: enabled,
      digestHour: int.tryParse(parts.first) ?? 9,
      digestMinute: parts.length > 1 ? int.tryParse(parts.last) ?? 0 : 0,
    );
  }

  @override
  Future<ReminderPermission> permission() async {
    await _ensurePlugin();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return ReminderPermission.denied;
    final enabled = await android.areNotificationsEnabled();
    if (enabled ?? false) return ReminderPermission.granted;
    // **`notRequested` unless something has been asked for.** The OS cannot tell us whether we have asked, so the
    // app records it: a stored digest time means a toggle was once turned on, which means the prompt has been
    // shown. Without this the screen would nag somebody who deliberately said no.
    final asked = await _settings.readValue(digestTimeKey);
    return asked == null ? ReminderPermission.notRequested : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    await _ensurePlugin();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return ReminderPermission.denied;
    final granted = await android.requestNotificationsPermission();
    return (granted ?? false) ? ReminderPermission.granted : ReminderPermission.denied;
  }

  @override
  Future<Result<ReminderSettings, Failure>> setEnabled({
    required NotificationKind kind,
    required bool enabled,
  }) async {
    try {
      final current = await _readSettings();
      final next = {...current.enabled};
      enabled ? next.add(kind) : next.remove(kind);
      await _settings.writeValue(
        key: enabledKindsKey,
        value: next.map((kind) => kind.name).join(','),
        valueType: 'string',
      );
      final settings = current.copyWith(enabled: next);
      // Turning the last one off cancels everything rather than leaving a digest that says nothing.
      next.isEmpty ? await cancelAll() : await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('That reminder could not be changed.', cause: error),
      );
    }
  }

  @override
  Future<Result<ReminderSettings, Failure>> setDigestTime({
    required int hour,
    required int minute,
  }) async {
    try {
      final two = (int value) => value < 10 ? '0$value' : '$value';
      await _settings.writeValue(
        key: digestTimeKey,
        value: '${two(hour)}:${two(minute)}',
        valueType: 'string',
      );
      final settings = (await _readSettings()).copyWith(digestHour: hour, digestMinute: minute);
      if (settings.anyEnabled) await _scheduleDigest(settings);
      return Result.ok(settings);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('The reminder time could not be changed.', cause: error),
      );
    }
  }

  @override
  Stream<List<ScheduledReminder>> watchScheduled() =>
      _scheduleDao.watchScheduled().map((rows) => [
            for (final row in rows)
              ScheduledReminder(
                id: row.id,
                // The row's own `kind` column, converted by drift — not derived from `refType`, which I had
                // written before reading the table. Two sources for one fact is one too many.
                kind: row.kind,
                on: DateKey.fromDateTime(
                  DateTime.fromMillisecondsSinceEpoch(row.scheduledAtUtcMillis, isUtc: true),
                ),
                androidNotificationId: row.androidNotificationId,
              ),
          ]);

  @override
  Future<Result<int, Failure>> rescheduleAll() async {
    try {
      final settings = await _readSettings();
      if (!settings.anyEnabled) {
        await cancelAll();
        return const Result.ok(0);
      }
      final count = await _scheduleDigest(settings);
      return Result.ok(count);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be rescheduled.', cause: error),
      );
    }
  }

  @override
  Future<Result<void, Failure>> cancelAll() async {
    try {
      await _ensurePlugin();
      // `cancel` is named-only on the installed plugin, like `zonedSchedule` — this version takes nothing
      // positionally anywhere on its surface.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelAll(nowUtcMillis: _clock.nowUtcMillis());
      return const Result.ok(null);
    } on Object catch (error) {
      return Result.failure(
        UnexpectedFailure('Reminders could not be cancelled.', cause: error),
      );
    }
  }

  /// Counts what is coming, writes one schedule row, and books one notification.
  ///
  /// Idempotent by construction: the digest's Android id is a constant and its `notification_schedule` row is
  /// replaced by `refType`/`refId`, so the daily `workmanager` job can call this as often as it likes without
  /// stacking duplicates — which is exactly what ARCH_3 §7 means by the table guaranteeing idempotency.
  Future<int> _scheduleDigest(ReminderSettings settings) async {
    await _ensurePlugin();
    await _ensureTimezones();
    final today = _clock.today();
    final events = await _calendar
        .watchRange(from: today, to: today.addDays(horizon.inDays), today: today)
        .first;

    final counts = <NotificationKind, int>{};
    for (final event in events) {
      final kind = _kindForEvent(event.type);
      if (kind == null || !settings.enabled.contains(kind)) continue;
      counts[kind] = (counts[kind] ?? 0) + 1;
    }
    if (counts.isEmpty) {
      // **Nothing to say means nothing is sent.** A daily notification reading "0 items expire this week" is how
      // a reminder becomes something people switch off.
      await _plugin.cancel(id: digestNotificationId);
      await _scheduleDao.cancelForRef(
        refType: digestRefType,
        refId: digestRefType,
        nowUtcMillis: _clock.nowUtcMillis(),
      );
      return 0;
    }

    final when = _nextOccurrence(settings.digestHour, settings.digestMinute);
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);

    final now = _clock.nowUtcMillis();
    await _scheduleDao.replaceForRef(
      refType: digestRefType,
      refId: digestRefType,
      nowUtcMillis: now,
      replacement: NotificationScheduleCompanion.insert(
        id: _uids.generate(),
        // The digest covers whichever kind has the most entries, because the column holds one and the sentence
        // holds several. It is what `watchScheduled` shows, so the row names the thing the user will most likely
        // be reminded about rather than an arbitrary first.
        kind: _dominantKind(counts),
        refType: digestRefType,
        refId: digestRefType,
        scheduledAtUtcMillis: when.toUtc().millisecondsSinceEpoch,
        androidNotificationId: digestNotificationId,
        status: NotificationStatus.scheduled,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await _plugin.zonedSchedule(
      // **Every argument named.** The installed plugin's `zonedSchedule` takes `id`, `scheduledDate` and
      // `notificationDetails` as named parameters and accepts nothing positionally — the analyzer named all three.
      id: digestNotificationId,
      title: _digestTitle(counts),
      body: _digestBody(counts),
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alaya_digest',
          'Daily summary',
          channelDescription: 'One message a day about what is coming up.',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      // **Inexact, and this is the line that matters** (ARCH_3 §7). `exactAllowWhileIdle` would need
      // `SCHEDULE_EXACT_ALARM`, which Android 14 restricts and Play questions.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // Repeats daily at the same wall-clock time, following the device across a timezone change.
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return total;
  }

  /// The next time [hour]:[minute] comes round in the device's own zone.
  ///
  /// `tz.local` rather than UTC, because a digest is a wall-clock promise: somebody who asked for 9am wants 9am
  /// where they are, and wants it to still be 9am after they fly somewhere.
  tz.TZDateTime _nextOccurrence(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) next = next.add(const Duration(days: 1));
    return next;
  }

  String _digestTitle(Map<NotificationKind, int> counts) {
    final total = counts.values.fold<int>(0, (sum, value) => sum + value);
    return total == 1 ? '1 thing coming up' : '$total things coming up';
  }

  /// The one sentence.
  ///
  /// **Assembled here rather than from the ARB, and that is a deviation worth recording.** A notification is
  /// built by a `workmanager` isolate with no `BuildContext` and no `AlayaStrings`, so Law U5's "every string
  /// through the ARB" cannot reach it. The alternative — passing pre-localised text from the UI into a background
  /// job that may run days later, in a locale the user has since changed — would be worse than plain English.
  String _digestBody(Map<NotificationKind, int> counts) {
    final parts = <String>[];
    for (final kind in reminderKinds) {
      final count = counts[kind];
      if (count == null || count == 0) continue;
      parts.add(switch (kind) {
        NotificationKind.expiry => count == 1 ? '1 item expires' : '$count items expire',
        NotificationKind.serviceDue => count == 1 ? '1 service due' : '$count services due',
        NotificationKind.recurringDue => count == 1 ? '1 bill due' : '$count bills due',
        NotificationKind.warrantyEnd => count == 1 ? '1 warranty ends' : '$count warranties end',
        // Not in `reminderKinds`, so it never reaches here — but the switch is exhaustive so that adding a sixth
        // kind fails to compile rather than falling through to silence.
        NotificationKind.lowStock => '',
      });
    }
    return '${parts.join(', ')} this week';
  }

  NotificationKind? _kindForEvent(CalendarEventType type) => switch (type) {
        CalendarEventType.batchExpiry => NotificationKind.expiry,
        CalendarEventType.serviceDue => NotificationKind.serviceDue,
        CalendarEventType.recurringDue => NotificationKind.recurringDue,
        CalendarEventType.warrantyEnd => NotificationKind.warrantyEnd,
        // A recorded transaction and a shopping target are history and intent, not things that fall due.
        CalendarEventType.transaction || CalendarEventType.shoppingTarget => null,
      };

  /// Whichever kind contributes most to the digest.
  NotificationKind _dominantKind(Map<NotificationKind, int> counts) {
    var best = reminderKinds.first;
    var most = -1;
    for (final entry in counts.entries) {
      if (entry.value > most) {
        best = entry.key;
        most = entry.value;
      }
    }
    return best;
  }
}
```

### `lib/data/reminders/daily_job.dart`

```dart
/// The daily background job: recompute reminders, and purge what has outlived the trash.
///
/// **The two scheduled obligations nothing else honours.** ARCH_3 §7 wants a daily recompute so a digest reflects
/// what is actually coming, and §4.2's thirty-day retention is a promise the app does not keep unless something
/// enforces it. Both ports exposed the methods; until this file, nothing called them on a schedule.
///
/// **It runs in its own isolate, so it builds its own dependencies.** A `workmanager` callback has no access to
/// the UI isolate's Riverpod container — the providers there simply do not exist in this one. That is why the
/// wiring is repeated here rather than reused, and why the database is opened through
/// `openAlayaDatabase`, the single permitted open path (Law L10), rather than by reaching for a
/// connection somebody else made.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/daos/calendar_dao.dart';
import 'package:alaya/data/daos/notification_schedule_dao.dart';
import 'package:alaya/data/daos/settings_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/connection/open_database.dart';
import 'package:alaya/data/reminders/local_notification_scheduler.dart';
import 'package:alaya/data/repositories/calendar_repository_impl.dart';
import 'package:alaya/data/repositories/settings_repository_impl.dart';
import 'package:alaya/data/trash/trash_adapter.dart';
import 'package:alaya/domain/services/calendar_aggregator.dart';



/// The unique name the periodic task is registered under.
///
/// Stable, so re-registering replaces rather than stacking: `workmanager` keys by this name, and a second
/// registration under a new name would mean two jobs doing the same work on two schedules.
const String dailyTaskName = 'alaya.daily';

/// How often the job runs.
///
/// **A day, and inexact by nature.** `workmanager` cannot promise a moment and does not try; Android batches
/// these to save battery. That is compatible with ARCH_3 §7 on purpose — the digest itself is scheduled by
/// `flutter_local_notifications` at the user's chosen time, and this job only decides what it will say.
const Duration dailyInterval = Duration(days: 1);

/// Registers the daily job. Called once from `bootstrap()`.
Future<void> registerDailyJob() async {
  await Workmanager().initialize(alayaCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    dailyTaskName,
    dailyTaskName,
    frequency: dailyInterval,
    // `ExistingPeriodicWorkPolicy`, not `ExistingWorkPolicy`: `registerPeriodicTask` has its own enum, and the
    // one-shot type is not assignable to it.
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(
      // No network requirement: everything this job does is local. Asking for connectivity would delay a purge
      // indefinitely on a phone that is rarely online, which is the opposite of a retention guarantee.
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
    ),
  );
}

/// The background entry point.
///
/// `@pragma('vm:entry-point')` because the isolate is started by native code with no Dart caller — without it
/// tree-shaking removes this function from a release build and the job silently never runs.
@pragma('vm:entry-point')
void alayaCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != dailyTaskName) return true;
    AlayaDatabase? database;
    try {
      const clock = SystemClock();
      const uids = Uuid7Generator();
      // Defaults would supply both, but naming them keeps this isolate's wiring identical to the UI isolate's
      // rather than depending on two default lists staying in step.
      database = openAlayaDatabase(uids: uids, clock: clock);

      final trash = TrashAdapter(database: database, clock: clock);
      await trash.purgeExpired();

      // **This isolate needs its own initialised plugin.** `FlutterLocalNotificationsPlugin` is not a
      // singleton across isolates: the instance the UI created does not exist here, and an uninitialised one
      // fails quietly rather than throwing. `LocalNotificationScheduler._ensurePlugin` handles it lazily, which
      // is why this constructs the scheduler rather than calling the plugin directly.
      final reminders = LocalNotificationScheduler(
        plugin: FlutterLocalNotificationsPlugin(),
        database: database,
        scheduleDao: NotificationScheduleDao(database),
        calendar: CalendarAggregator(CalendarRepositoryImpl(CalendarDao(database))),
        settings: SettingsRepositoryImpl(SettingsDao(database), clock),
        uids: uids,
        clock: clock,
      );
      await reminders.rescheduleAll();
      return true;
    } on Object {
      // **Returns true even on failure, deliberately.** Returning false asks Android to retry with backoff, and
      // a job that fails for a structural reason — a corrupt row, a revoked permission — would then retry
      // forever and cost battery for nothing. A missed day is recovered by tomorrow's run.
      return true;
    } finally {
      await database?.close();
    }
  });
}
```

### `android/app/src/main/res/drawable/ic_notification.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    Alaya's status-bar icon.

    Android flattens a notification icon to a white silhouette on API 21 and above: colour, gradients and
    detail are all discarded and only the alpha channel survives. Pointing the notification at
    @mipmap/ic_launcher, which is the Flutter default, therefore renders a solid white square.

    A vector rather than five PNGs, so it is sharp at every density from one file and needs no regeneration
    when the artwork changes. 24dp is the standard notification size; the shape is deliberately simple
    because anything detailed becomes a smudge at that scale.

    This is a placeholder wallet mark. Replace the pathData with your own glyph, keeping two rules: white
    fill only, and one shape rather than several.
-->
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="24dp"
    android:height="24dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FFFFFFFF"
        android:fillType="evenOdd"
        android:pathData="M5,5 H19 A2,2 0 0 1 21,7 V17 A2,2 0 0 1 19,19 H5 A2,2 0 0 1 3,17 V7 A2,2 0 0 1 5,5 Z M16.5,10.75 A1.25,1.25 0 1 0 16.5,13.25 A1.25,1.25 0 1 0 16.5,10.75 Z" />
</vector>
```
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
| **`allowBackup="false"` in the BUILT manifest** | ⛔ Needs a build. Command below |
| **Release AAB size recorded and justified** | ✅ **71.1 MB, justified below** |

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

### Verifying `allowBackup` in the built artefact

The source is not evidence: a manifest merger, or any library shipping `allowBackup="true"`, can flip it
silently. Check the artefact.

```
flutter build apk --release
$ANDROID_HOME/build-tools/34.0.0/aapt2 dump xmltree \
  build/app/outputs/apk/release/app-release.apk --file AndroidManifest.xml | grep -i allowBackup
```

Expect `android:allowBackup(0x0101000c)=(type 0x12)0x0` — `0x0` is false. A `0x1` there means something in the
dependency tree overrode it, and ARCH_3 §2.4 makes that a release blocker rather than a warning.

This command lived in the manifest as a comment until it broke the build: **an XML comment may not contain a
double hyphen**, and `--file` has one. The parser error named the file rather than the line, which is why a
one-character rule cost a full Gradle run to find.

### Release AAB size — 71.1 MB, and why that is the right number

**Sixty-five per cent of the bundle is never downloaded by anyone.**

| Component | Uncompressed | Shipped to a device? |
|---|---|---|
| `BUNDLE-METADATA/…/proguard.map` | 48.5 MB | **No** — Play uses it to deobfuscate Java/Kotlin stack traces |
| `BUNDLE-METADATA/…/debugsymbols/*.sym` | 90.7 MB | **No** — Play uses it to symbolise native crashes |
| `base/lib/**` (three ABIs) | 69.0 MB | One ABI only |
| `base/dex/*` + resources | 6.6 MB | Yes |
| **Total uncompressed** | **215.6 MB** | |

What one real device receives, uncompressed:

| ABI | Native | + dex + resources | Total |
|---|---|---|---|
| `arm64-v8a` | 23.3 MB | 6.6 MB | **29.9 MB** |
| `armeabi-v7a` | 20.9 MB | 6.6 MB | **27.5 MB** |
| `x86_64` | 24.8 MB | 6.6 MB | 31.4 MB — emulator only, no Play user gets it |

Native code compresses to roughly half, so the delivered download is **near 15 MB**. That is the figure worth
quoting, and Play Console reports it exactly once the bundle is uploaded. For a certain answer before uploading:

```
bundletool get-size total --apks=<built .apks> --dimensions=ABI,SDK
```

**The debug symbols stay.** They cost nothing at download and are what makes a native crash report readable;
removing them to shrink a number nobody downloads would trade real diagnostics for a cosmetic figure. Same for
`proguard.map` — without it, every obfuscated Kotlin frame in Play Console is unreadable.

**A prediction of mine that the data disproved.** Seeing three `DWARF debugging information` warnings, I expected
`libapp.so` to be 15–20 MB per ABI with debug info surviving `--split-debug-info`, and said 71.1 MB could not be
justified. It is **9.8–10.6 MB per ABI**, which is normal for a Flutter app of this size, and the warning refers
to symbols Gradle deliberately bundles as metadata. The `.so` listing settled in one command what I had reasoned
my way to the wrong answer about.

### What the device pass must produce

Four numbers and two round trips, none of which I can generate:

1. **Dashboard first frame**, profile mode, after seeding 50k — target < 500 ms
2. **Worst frame while scrolling 5k rows**, profile mode — target < 16 ms
3. **`allowBackup` in the built manifest** — must read `false`
4. **Offline pass** — airplane mode, every screen, zero errors. The only network callers are the daily rate fetch
   and the Support screen, so a failure here means something is reaching the network that should not
5. **Backup → wipe → restore**, record counts identical before and after

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

