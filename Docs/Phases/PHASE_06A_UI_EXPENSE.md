# Phase 6A — Shared UI Kit & Expense Module

> **Regenerated 2026-08-02 from the canonical tree.** Every fix through the Phase 6C debugging
> pass is folded in; this document and the working tree are in sync, and regenerating from it
> reproduces the code that runs. Earlier revisions reintroduce defects listed in ARCH_6 §3.
>
> Files shared with other phase documents — `app_en.arb`, `routes.dart`, `app_router.dart`,
> `layout_overflow_test.dart`, and the Phase 6A editor files amended by 6B and 6C — carry
> **identical** content in every copy, so they may be applied in any order.


**Part 1 of 2 — the shared kit (ARCH_5 §4.2).** Thirteen files. Written first because 6B–6F all
consume them; built per-feature, one widget becomes three (ARCH_4 R25).

Two files beyond the nine listed: `alaya_durations.dart` gains a `debounce` value, because
`AlayaSearchField` needs a delay and U6 forbids a raw `Duration` in a widget; and `app_en.arb` gains
the three relative-date keys `DateText` needs.

Assumes `PHASE_05_FIXES.md` is applied — `AlayaBottomSheet`, `ScrollSafeCenter` and `QtyParser` must
exist before any of this compiles.

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build
dart analyze
flutter test --update-goldens test/shared/golden
flutter test
```

---

### `lib/app/theme/tokens/alaya_icon_size.dart`

```dart
/// The icon size scale (ARCH_5 §2.7) — the last literal class the token rules did not cover.
///
/// Phase 5 shipped 18, 20, 22 and 40 as raw numbers across six files (ARCH_4 A52). Four steps is
/// enough for every icon in the app, and having exactly four is what stops a fifth appearing.
abstract final class AlayaIconSize {
  /// 16 — inline with `caption` or `overline` text: a chip's dismiss, a status glyph.
  static const double sm = 16;

  /// 20 — the default. List-row leading icons, field affixes, app-bar actions.
  static const double md = 20;

  /// 24 — a primary action's icon, a FAB, a drawer destination.
  static const double lg = 24;

  /// 40 — the single illustrative icon on an empty or error state.
  static const double xl = 40;
}
```

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

  /// 300 ms — a route transition. Between [base] and [slow] on purpose: a page change needs to read
  /// as a change of place, which [base] is too brisk to convey, without making navigation feel slow.
  static const Duration page = Duration(milliseconds: 300);

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

### `lib/shared/widgets/date_text.dart`

```dart
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';

/// How a [DateText] renders its date.
enum DateTextStyle {
  /// `Saturday, 1 August 2026` — a detail screen's one date field.
  full,

  /// `1 Aug 2026` — the default. List rows, key/value rows.
  medium,

  /// `1 Aug` — a sticky day header, a dense chip, a chart axis.
  dayMonth,

  /// `Today`, `Yesterday`, `Tomorrow`, else [medium]. Only via [DateText.relative].
  relative,
}

/// Renders a [DateKey], and is the only path from one to pixels (Law U7).
///
/// **Never `DateKey.toString()`.** That prints the raw `yyyymmdd` integer, which is a debug
/// representation — `20260801` in front of a user instead of `1 Aug 2026`.
///
/// Formatting goes through `intl` against the widget's own locale, so the same date reads correctly
/// in `en_IN` and `de_DE` without a call site knowing which. The [DateKey] is converted with
/// [DateKey.toUtcMidnight], whose calendar fields are the civil ones by construction — no timezone
/// can shift the rendered day, which is the entire reason Law L4 separates civil dates from
/// instants.
class DateText extends StatelessWidget {
  /// Renders [date] in [style]. [DateTextStyle.relative] is unavailable here — use [DateText.relative].
  const DateText(
    this.date, {
    this.style = DateTextStyle.medium,
    this.textStyle,
    this.muted = false,
    this.textAlign,
    super.key,
  })  : _clock = null,
        assert(
          style != DateTextStyle.relative,
          'DateTextStyle.relative needs a Clock. Use DateText.relative().',
        );

  /// Renders [date] as `Today` / `Yesterday` / `Tomorrow`, falling back to [DateTextStyle.medium].
  ///
  /// Takes the [Clock] rather than calling `DateTime.now()`, so a date-sensitive golden or widget
  /// test is reproducible instead of depending on the day it ran.
  const DateText.relative(
    this.date, {
    required Clock clock,
    this.textStyle,
    this.muted = false,
    this.textAlign,
    super.key,
  })  : style = DateTextStyle.relative,
        _clock = clock;

  /// The civil date to render.
  final DateKey date;

  /// Which presentation to use.
  final DateTextStyle style;

  /// Overrides the default [AlayaTypography.caption].
  final TextStyle? textStyle;

  /// Renders in the muted colour, for a secondary or historical row.
  final bool muted;

  /// How to align the text.
  final TextAlign? textAlign;

  final Clock? _clock;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      _format(context),
      style: (textStyle ?? AlayaTypography.caption)
          .copyWith(color: muted ? semantic.muted : null),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final moment = date.toUtcMidnight();

    if (style == DateTextStyle.relative) {
      final clock = _clock;
      if (clock != null) {
        final strings = AlayaStrings.of(context);
        switch (date.diffDays(clock.today())) {
          case 0:
            return strings.dateToday;
          case -1:
            return strings.dateYesterday;
          case 1:
            return strings.dateTomorrow;
        }
      }
      return DateFormat.yMMMd(localeTag).format(moment);
    }

    return switch (style) {
      DateTextStyle.full => DateFormat.yMMMMEEEEd(localeTag).format(moment),
      DateTextStyle.medium => DateFormat.yMMMd(localeTag).format(moment),
      DateTextStyle.dayMonth => DateFormat.MMMd(localeTag).format(moment),
      DateTextStyle.relative => DateFormat.yMMMd(localeTag).format(moment),
    };
  }
}
```

### `lib/shared/widgets/key_value_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One label/value line on a detail screen (ARCH_5 §3 archetype E).
///
/// **Renders nothing at all when there is no value.** A detail screen that shows `—` for every
/// unset field reads as broken data rather than as a record with optional fields, and on a schema
/// where most columns are nullable that is most of the screen. Hiding the row is the difference
/// between "this asset has no warranty" and "this app failed to load the warranty".
///
/// Both sides are [Flexible], so a long value wraps instead of overflowing — which is what keeps
/// the row safe at a doubled text scale (Law U15).
class KeyValueRow extends StatelessWidget {
  /// Creates a row for [label]. Renders nothing unless [value] or [valueWidget] is supplied.
  const KeyValueRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.onTap,
    this.icon,
    super.key,
  });

  /// The field's name, already localised.
  final String label;

  /// The value as text. Ignored when [valueWidget] is supplied.
  final String? value;

  /// The value as a widget — an `AmountText`, a `QtyText`, a `DateText`, a chip row.
  ///
  /// Preferred over [value] for anything typed: Law U7 routes every `Money`, `Qty` and `DateKey`
  /// through its own widget, and formatting one into a string here would bypass that.
  final Widget? valueWidget;

  /// Makes the row tappable — a payee that opens its detail, a phone number that dials.
  final VoidCallback? onTap;

  /// A leading icon, for a row that is also an action.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rendered = valueWidget;
    if (rendered == null && value == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semantic;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.md, color: semantic.muted),
            const SizedBox(width: AlayaSpacing.sm),
          ],
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: AlayaTypography.label.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AlayaSpacing.md),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: rendered ??
                  Text(
                    value!,
                    style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
                    textAlign: TextAlign.end,
                  ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AlayaSpacing.xs),
            Icon(Icons.chevron_right, size: AlayaIconSize.md, color: semantic.muted),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
          child: content,
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/status_chip.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// What a [StatusChip] is reporting.
///
/// A tone rather than a colour: the chip is the single place any of these seven states is rendered,
/// so `needsReview`, `unallocated`, `detached`, `overdue`, `expiring`, `low` and `approximate` all
/// look the same wherever they appear, and changing what "warning" looks like is one edit.
enum StatusTone {
  /// Factual, no judgement — `detached`, `approximate`, a count.
  neutral,

  /// Worth knowing — `needsReview`, `unallocated`.
  info,

  /// Needs attention soon — `expiring`, `low`, due within the window.
  warning,

  /// Wrong or past due — `overdue`, `expired`.
  danger,

  /// Completed — `paid`, `restored`.
  success,
}

/// A small labelled status pill.
///
/// **The label is required, and that is Law U17 rather than a style choice.** Colour alone excludes
/// roughly eight percent of men, and survives neither a greyscale screenshot nor a screen reader.
/// The tone tints the chip; the word carries the meaning.
class StatusChip extends StatelessWidget {
  /// Creates a chip reading [label] in [tone].
  const StatusChip({
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// The status, already localised. Two or three words at most.
  final String label;

  /// Which semantic colour to tint with.
  final StatusTone tone;

  /// An optional leading glyph. Never a substitute for [label].
  final IconData? icon;

  /// A rendered value after the label — an `AmountText` or a `QtyText`.
  ///
  /// A chip that must show money cannot take it as a string: `Money` is minor units, and formatting
  /// it at the call site is how `2000.00` reaches the screen as `200000` (Law U7). The value is
  /// rendered by its own widget and handed in.
  final Widget? trailing;

  /// Makes the chip an action — "3 need details" opening a filtered list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final foreground = switch (tone) {
      StatusTone.neutral => semantic.muted,
      StatusTone.info => semantic.transfer,
      StatusTone.warning => semantic.warning,
      StatusTone.danger => semantic.danger,
      StatusTone.success => semantic.success,
    };

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.sm, color: foreground),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            trailing!,
          ],
        ],
      ),
    );

    // The tint is the tone at low alpha rather than a second palette entry, so a chip cannot drift
    // out of step with the colour it is reporting.
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: BorderSide(color: foreground.withValues(alpha: 0.28)),
    );
    final background = foreground.withValues(alpha: 0.12);

    if (onTap == null) {
      return Semantics(
        label: label,
        child: Material(
          color: background,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/alaya_form_scaffold.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';

/// The body of every editor screen (ARCH_5 §3 archetype B).
///
/// Three things that every form needs and that every form otherwise reimplements slightly
/// differently:
///
/// 1. **A scrolling body.** Law U2 — a screen with a text input has a scroll ancestor, or it
///    overflows the moment a keyboard opens at a raised text scale.
/// 2. **A sticky footer holding the commit.** Law U14 — an app-bar "Save" is a stretch on a 6.7"
///    phone held one-handed, and this app is used one-handed. The footer sits above the keyboard
///    because the enclosing `Scaffold` resizes; the screen must therefore **not** set
///    `resizeToAvoidBottomInset: false`.
/// 3. **An unsaved-changes guard.** Law U10 — dismissing an editor with edits in it prompts, and a
///    rejected save leaves every field populated.
///
/// The screen supplies `Scaffold(appBar: …, body: AlayaFormScaffold(…))` and owns its own state;
/// this widget owns none of it.
class AlayaFormScaffold extends StatelessWidget {
  /// Creates a form body committing through [onPrimary].
  const AlayaFormScaffold({
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    required this.discardTitle,
    required this.discardBody,
    required this.discardConfirmLabel,
    required this.discardCancelLabel,
    this.secondaryLabel,
    this.onSecondary,
    this.isDirty = false,
    this.isSubmitting = false,
    this.padding = const EdgeInsets.fromLTRB(
      AlayaSpacing.screenEdge,
      AlayaSpacing.md,
      AlayaSpacing.screenEdge,
      AlayaSpacing.xxl,
    ),
    super.key,
  });

  /// The form's fields and sections.
  final Widget child;

  /// The commit button's label, already localised. Names the action — "Save expense", not "Save".
  final String primaryLabel;

  /// The commit. Null disables the button, which is how an invalid form reports itself.
  final VoidCallback? onPrimary;

  /// Title of the discard prompt.
  final String discardTitle;

  /// Body of the discard prompt. Says what will be lost.
  final String discardBody;

  /// The discard prompt's confirm label — the destructive one.
  final String discardConfirmLabel;

  /// The discard prompt's cancel label, which returns to the form.
  final String discardCancelLabel;

  /// An optional secondary action's label.
  final String? secondaryLabel;

  /// The secondary action.
  final VoidCallback? onSecondary;

  /// Whether the form holds unsaved edits. Drives the guard.
  final bool isDirty;

  /// Whether a save is in flight. Disables both actions and shows progress on the primary.
  final bool isSubmitting;

  /// Padding around [child], inside the scroll view.
  final EdgeInsetsGeometry padding;

  Future<void> _confirmDiscard(BuildContext context) async {
    final navigator = Navigator.of(context);
    final discard = await ConfirmSheet.show(
      context,
      title: discardTitle,
      body: discardBody,
      confirmLabel: discardConfirmLabel,
      cancelLabel: discardCancelLabel,
      destructive: true,
    );
    if (discard && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = isDirty || isSubmitting;
    return PopScope<Object?>(
      canPop: !blocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isSubmitting) return;
        unawaited(_confirmDiscard(context));
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: padding,
              child: child,
            ),
          ),
          _FormFooter(
            primaryLabel: primaryLabel,
            onPrimary: isSubmitting ? null : onPrimary,
            secondaryLabel: secondaryLabel,
            onSecondary: isSubmitting ? null : onSecondary,
            isSubmitting: isSubmitting,
          ),
        ],
      ),
    );
  }
}

class _FormFooter extends StatelessWidget {
  const _FormFooter({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.isSubmitting,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = secondaryLabel;

    final primary = FilledButton(
      onPressed: onPrimary,
      child: isSubmitting
          ? SizedBox(
              width: AlayaSpacing.lg,
              height: AlayaSpacing.lg,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(primaryLabel),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: secondary == null
                ? SizedBox(width: double.infinity, child: primary)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSecondary,
                          child: Text(secondary),
                        ),
                      ),
                      const SizedBox(width: AlayaSpacing.sm),
                      Expanded(flex: 2, child: primary),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/alaya_list_skeleton.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The loading state for any list surface (ARCH_5 §5.2).
///
/// **A skeleton rather than a spinner, and deliberately without shimmer.** The shape of what is
/// arriving tells the user more than a spinner does, and a spinner centred in a screen that is about
/// to be a list reads as "slow". Shimmer is left out because it is an animation the user waits
/// through on a surface that exists only to be replaced — and because it would have to be suppressed
/// under `disableAnimations` anyway, leaving this exact widget as the fallback.
///
/// Non-scrollable: it fills whatever room it is given and clips the rest, so it can never overflow
/// the space a list was going to occupy.
class AlayaListSkeleton extends StatelessWidget {
  /// Creates a skeleton of [rows] placeholder rows, described to assistive technology as [label].
  const AlayaListSkeleton({
    required this.label,
    this.rows = 5,
    this.hasLeading = true,
    this.hasTrailing = true,
    super.key,
  });

  /// What is loading, already localised. `CircularProgressIndicator` has semantics; a box does not.
  final String label;

  /// How many placeholder rows to draw.
  final int rows;

  /// Whether rows show a leading identity block — an icon or a colour dot.
  final bool hasLeading;

  /// Whether rows show a trailing block, which in this app is almost always an amount.
  final bool hasTrailing;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        liveRegion: true,
        child: ExcludeSemantics(
          child: ListView.builder(
            // `shrinkWrap` and `NeverScrollableScrollPhysics` travel together. The physics say it
            // will not scroll; `shrinkWrap` is what lets it size to its children instead of
            // demanding a viewport. One without the other throws the moment this skeleton renders
            // inside another scrollable — which is every detail screen, on its first frame.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
            itemCount: rows,
            itemBuilder: (context, index) => _SkeletonRow(
              hasLeading: hasLeading,
              hasTrailing: hasTrailing,
              // Varied widths so the block reads as content rather than as a loading bar.
              titleFactor: index.isEven ? 0.55 : 0.4,
            ),
          ),
        ),
      );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.hasLeading,
    required this.hasTrailing,
    required this.titleFactor,
  });

  final bool hasLeading;
  final bool hasTrailing;
  final double titleFactor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.screenEdge,
          vertical: AlayaSpacing.sm,
        ),
        child: Row(
          children: [
            if (hasLeading) ...[
              const _Block(width: AlayaSpacing.xxl, height: AlayaSpacing.xxl, rounded: true),
              const SizedBox(width: AlayaSpacing.sm),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: titleFactor,
                    child: const _Block(height: AlayaSpacing.md),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  const FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.3,
                    child: _Block(height: AlayaSpacing.sm),
                  ),
                ],
              ),
            ),
            if (hasTrailing) ...[
              const SizedBox(width: AlayaSpacing.md),
              const _Block(width: AlayaSpacing.xxxl, height: AlayaSpacing.md),
            ],
          ],
        ),
      );
}

class _Block extends StatelessWidget {
  const _Block({required this.height, this.width, this.rounded = false});

  final double height;
  final double? width;
  final bool rounded;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.semantic.surfaceSunken,
          borderRadius: rounded ? AlayaRadii.borderSm : AlayaRadii.borderXs,
        ),
      );
}
```

### `lib/shared/widgets/alaya_search_field.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The search input for every catalogue screen (ARCH_5 §3 archetype D).
///
/// **A visible field rather than a magnifying glass in the app bar.** Catalogues in this app are
/// searched constantly — an item you are about to consume, an asset you are about to service — and
/// hiding the field behind a tap costs an interaction every single time.
///
/// Debounced through [AlayaDurations.debounce] so a query does not run per keystroke, and the timer
/// is cancelled on dispose so a pending callback cannot fire into a disposed widget.
class AlayaSearchField extends StatefulWidget {
  /// Creates a search field reporting through [onChanged].
  const AlayaSearchField({
    required this.onChanged,
    required this.clearLabel,
    this.hintText,
    this.initialValue,
    this.autofocus = false,
    super.key,
  });

  /// Called with the trimmed query once typing settles, and immediately on clear.
  final ValueChanged<String> onChanged;

  /// Accessibility label for the clear button, already localised.
  final String clearLabel;

  /// Placeholder text, already localised.
  final String? hintText;

  /// A starting query, for a screen restoring its state.
  final String? initialValue;

  /// Whether to focus on mount. False on a list screen — a keyboard the user did not ask for
  /// covers the content they came to read.
  final bool autofocus;

  @override
  State<AlayaSearchField> createState() => _AlayaSearchFieldState();
}

class _AlayaSearchFieldState extends State<AlayaSearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');
  Timer? _debounce;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
  }

  void _handleChanged(String raw) {
    final nowHasText = raw.isNotEmpty;
    if (nowHasText != _hasText) setState(() => _hasText = nowHasText);
    _debounce?.cancel();
    _debounce = Timer(AlayaDurations.debounce, () => widget.onChanged(raw.trim()));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    // Immediate rather than debounced: clearing is a decision, not a keystroke on the way to one.
    widget.onChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        style: AlayaTypography.body,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.search, size: AlayaIconSize.md),
          suffixIcon: _hasText
              ? IconButton(
                  icon: const Icon(Icons.close, size: AlayaIconSize.md),
                  tooltip: widget.clearLabel,
                  onPressed: _clear,
                )
              : null,
        ),
        onChanged: _handleChanged,
      );
}
```

### `lib/shared/widgets/filter_chip_bar.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One active filter, rendered as a removable chip.
class ActiveFilter {
  /// Creates a filter labelled [label] that [onRemove] clears.
  const ActiveFilter({required this.label, required this.onRemove});

  /// What is filtered, already localised and including the value — "Account: HDFC", not "Account".
  final String label;

  /// Clears just this filter.
  final VoidCallback onRemove;
}

/// The active-filter row above a ledger list (ARCH_5 §3 archetype C).
///
/// **A filter the user cannot see is a bug report waiting to happen.** A list quietly constrained by
/// a filter set on a previous visit is indistinguishable from a list that lost its data, and "my
/// transactions disappeared" is the support mail that follows. So every active filter is visible and
/// individually removable, and the bar disappears entirely when nothing is filtered.
///
/// A [Wrap] rather than a horizontal scroller: a scroller has to be given a height, and a fixed
/// height overflows the moment the text scale is raised (Law U15).
class FilterChipBar extends StatelessWidget {
  /// Creates a bar for [filters]. Renders nothing when the list is empty.
  const FilterChipBar({
    required this.filters,
    this.onClearAll,
    this.clearAllLabel,
    super.key,
  });

  /// The filters currently narrowing the list.
  final List<ActiveFilter> filters;

  /// Clears every filter at once. Offered only when more than one is active.
  final VoidCallback? onClearAll;

  /// The clear-all action's label, already localised.
  final String? clearAllLabel;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final showClearAll = onClearAll != null && clearAllLabel != null && filters.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters) _FilterChip(filter: filter),
          if (showClearAll)
            TextButton(
              onPressed: onClearAll,
              child: Text(clearAllLabel!, style: AlayaTypography.button),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter});

  final ActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: filter.label,
      child: Material(
        color: theme.colorScheme.secondary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderXs,
          side: BorderSide(color: theme.colorScheme.secondary.withValues(alpha: 0.28)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: filter.onRemove,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        filter.label,
                        style: AlayaTypography.overline
                            .copyWith(color: theme.colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AlayaSpacing.xxs),
                    Icon(
                      Icons.close,
                      size: AlayaIconSize.sm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/feedback/undo_snack.dart`

```dart
/// The single implementation of Law U9's success path.
///
/// **Every write reports its outcome.** A save that appears to do nothing is the worst result a form
/// can produce, and the second worst is five features each inventing their own snack bar.
///
/// One at a time: each call hides the current bar before showing its own. A queue would leave the
/// user reading the result of an action they took four taps ago.
library;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Reports a completed write and offers to reverse it.
///
/// Use wherever the data model can undo, which is most places — soft delete exists precisely so this
/// is possible (ARCH_3 §4). ARCH_5 §5.4 fixes what undo means per entity; in particular a stock
/// consume undoes by writing a **reversing movement**, never by deleting the original.
void showUndoSnack(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}

/// Reports a completed write that cannot be undone.
void showResultSnack(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        // **An offer, not a redirection.** A completed save must not throw the user into another form:
        // recording the expense was the task, and naming a warranty is a different one. The action puts
        // the next step one tap away without taking the decision for them (Law U9).
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Reports a failed write, optionally offering a retry.
///
/// Coloured by the danger tone rather than left to the default surface: a failure that looks
/// identical to a success is a failure the user will not notice.
void showFailureSnack(
  BuildContext context, {
  required String message,
  String? retryLabel,
  VoidCallback? onRetry,
}) {
  final semantic = context.semantic;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: semantic.onStatus)),
        backgroundColor: semantic.danger,
        duration: AlayaDurations.snack,
        action: retryLabel == null || onRetry == null
            ? null
            : SnackBarAction(
                label: retryLabel,
                textColor: semantic.onStatus,
                onPressed: onRetry,
              ),
      ),
    );
}
```



### `test/shared/golden/kit_golden_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Goldens for the three display widgets the shared kit adds, light and dark.
///
/// Unlike `widget_golden_test.dart`, this harness installs `Localizations`: `DateText.relative`
/// reads "Today" and "Yesterday" from the ARB, and a date formatter that cannot say those words in
/// the user's language is not a date formatter. `flutter gen-l10n` therefore has to have run — which
/// the documented codegen order guarantees.
void main() {
  // Fixed so "Today" and "Yesterday" are the same two days on every machine and every run.
  final clock = FixedClock(DateTime(2026, 8, 1, 9, 30));
  const today = DateKey(20260801);
  const yesterday = DateKey(20260731);
  const older = DateKey(20260114);

  Widget harness(Widget child, {required bool dark, Size size = const Size(320, 200)}) =>
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        // Inside the app: WidgetsApp re-establishes MediaQuery from the view, so a pin placed
        // above MaterialApp never reaches the widget under test.
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
          child: inner!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Padding(
                padding: const EdgeInsets.all(AlayaSpacing.md),
                child: child,
              ),
            ),
          ),
        ),
      );

  Future<void> expectGolden(
    WidgetTester tester,
    Widget child,
    String name, {
    required bool dark,
    Size size = const Size(320, 200),
  }) async {
    await tester.pumpWidget(harness(child, dark: dark, size: size));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.${dark ? "dark" : "light"}.png'),
    );
  }

  group('DateText', () {
    Widget sample() => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const DateText(older, style: DateTextStyle.full),
            const DateText(older),
            const DateText(older, style: DateTextStyle.dayMonth),
            DateText.relative(today, clock: clock),
            DateText.relative(yesterday, clock: clock),
            DateText.relative(older, clock: clock, muted: true),
          ],
        );

    testWidgets('light', (tester) => expectGolden(tester, sample(), 'date_text', dark: false));
    testWidgets('dark', (tester) => expectGolden(tester, sample(), 'date_text', dark: true));
  });

  group('KeyValueRow', () {
    Widget sample() => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const KeyValueRow(label: 'Payee', value: 'Reliance Fresh'),
            const KeyValueRow(
              label: 'Amount',
              valueWidget: AmountText(Money(-125050, 'INR')),
            ),
            const KeyValueRow(label: 'Date', valueWidget: DateText(older)),
            // Renders nothing at all — the gap below "Date" is the point of the golden.
            const KeyValueRow(label: 'Note'),
            KeyValueRow(label: 'Account', value: 'HDFC Savings', onTap: () {}),
          ],
        );

    testWidgets(
      'light',
      (tester) => expectGolden(tester, sample(), 'key_value_row',
          dark: false, size: const Size(320, 280)),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(tester, sample(), 'key_value_row',
          dark: true, size: const Size(320, 280)),
    );
  });

  group('StatusChip', () {
    Widget sample() => Center(
          child: Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              const StatusChip(label: 'Receipt deleted'),
              const StatusChip(label: 'Needs details', tone: StatusTone.info),
              const StatusChip(
                label: 'Expiring soon',
                tone: StatusTone.warning,
                icon: Icons.schedule,
              ),
              const StatusChip(label: 'Overdue', tone: StatusTone.danger),
              const StatusChip(label: 'Paid', tone: StatusTone.success),
              StatusChip(label: '3 need details', tone: StatusTone.info, onTap: () {}),
            ],
          ),
        );

    testWidgets(
      'light',
      (tester) => expectGolden(tester, sample(), 'status_chip',
          dark: false, size: const Size(320, 220)),
    );
    testWidgets(
      'dark',
      (tester) => expectGolden(tester, sample(), 'status_chip',
          dark: true, size: const Size(320, 220)),
    );
  });
}
```


### `test/features/expense/bill_form_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/bill_form.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/due_bills_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';

import '../../support/expense_harness.dart';

/// Four states, plus the rule this form exists to hold: one amount, one save, one transaction.
void main() {
  const account = Account(
    id: 'acc-1',
    name: 'Everyday',
    normalizedName: 'everyday',
    kind: AccountKind.bank,
    currencyCode: 'INR',
    openingBalance: Money(0, 'INR'),
    openingBalanceDateKey: kToday,
    isArchived: false,
    includeInNetWorth: true,
    sortOrder: 0,
  );

  RecurringTemplate template({String? defaultAccountId = 'acc-1'}) => RecurringTemplate(
        id: 'tpl-1',
        name: 'Rent',
        normalizedName: 'rent',
        kind: RecurringKind.rent,
        direction: RecurringDirection.outflow,
        defaultAmount: const Money(120000, 'INR'),
        intervalUnit: RecurringIntervalUnit.month,
        intervalCount: 1,
        startDateKey: const DateKey(20260131),
        nextDueDateKey: const DateKey(20260731),
        isPaused: false,
        autoRemind: true,
        remindDaysBefore: 3,
        anchorDayOfMonth: 31,
        defaultAccountId: defaultAccountId,
      );

  RecurringDue due({DateKey dueOn = const DateKey(20260731), String? accountId = 'acc-1'}) =>
      RecurringDue(
        template: template(defaultAccountId: accountId),
        occurrence: RecurringOccurrence(
          id: 'occ-1',
          templateId: 'tpl-1',
          dueDateKey: dueOn,
          status: RecurringOccurrenceStatus.due,
        ),
      );

  List<Override> overrides({
    List<RecurringDue>? rows,
    bool pending = false,
    bool fail = false,
    List<Account> accounts = const [account],
    String? appDefault,
  }) =>
      [
        clockProvider.overrideWithValue(kTestClock),
        builderDecimalDigitsProvider.overrideWith((ref) async => 2),
        billAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
        defaultAccountIdProvider.overrideWith((ref) async => appDefault),
        if (pending)
          dueBillsProvider.overrideWith((ref) => pendingStream<List<RecurringDue>>())
        else if (fail)
          dueBillsProvider
              .overrideWith((ref) => Stream<List<RecurringDue>>.error(StateError('boom')))
        else
          dueBillsProvider.overrideWith((ref) => Stream.value(rows ?? const [])),
      ];

  Widget host(TransactionEditorState state) => Scaffold(
        body: SingleChildScrollView(
          child: BillForm(editorId: null, state: state),
        ),
      );

  const blank = TransactionEditorState(currencyCode: 'INR', dateKey: kToday);

  testWidgets('loading says so without blocking a bill recorded by hand', (tester) async {
    await pumpExpense(tester, host(blank), overrides: overrides(pending: true));
    await tester.pump();
    // The schedule read is an enrichment. A pending one costs the shortcut, never the ability to
    // record an off-template bill, which is what this form does with none of it.
    expect(find.byType(BillForm), findsOneWidget);
    expect(find.byType(RadioGroup<String?>), findsNothing);
  });

  testWidgets('nothing due offers a way to set one up', (tester) async {
    await pumpExpense(tester, host(blank), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('Nothing is due right now.'), findsOneWidget);
    expect(find.text('Set up a recurring bill'), findsOneWidget);
  });

  testWidgets('a failed schedule read shows the reason, not a stand-in', (tester) async {
    await pumpExpense(tester, host(blank), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('a due bill is offered as a choice, not as a second way to pay',
      (tester) async {
    await pumpExpense(tester, host(blank), overrides: overrides(rows: [due()]));
    await tester.pumpAndSettle();
    // An earlier version opened the pay sheet from here, which left two write paths reachable: the
    // sheet recorded one transaction and saving the editor recorded a second for the same payment.
    expect(find.byType(RadioGroup<String?>), findsOneWidget);
    expect(find.text('Rent'), findsOneWidget);
    expect(find.text('Not a recurring bill'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Record it'), findsNothing);
  });

  testWidgets('nothing is selected until the user picks', (tester) async {
    await pumpExpense(tester, host(blank), overrides: overrides(rows: [due()]));
    await tester.pumpAndSettle();
    final group = tester.widget<RadioGroup<String?>>(find.byType(RadioGroup<String?>));
    // The default is unlinked, so an ordinary bill still records exactly as it always did.
    expect(group.groupValue, isNull);
    expect(find.text('This amount is what gets recorded'), findsNothing);
  });

  testWidgets('an overdue bill says so in the list', (tester) async {
    await pumpExpense(
      tester,
      host(blank),
      overrides: overrides(rows: [due(dueOn: const DateKey(20260715))]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Overdue'), findsOneWidget);
  });

  testWidgets('a selected bill says the amount below is what gets recorded', (tester) async {
    await pumpExpense(
      tester,
      host(
        const TransactionEditorState(
          currencyCode: 'INR',
          dateKey: kToday,
          recurringOccurrenceId: 'occ-1',
          fromAccountId: 'acc-1',
        ),
      ),
      overrides: overrides(rows: [due()]),
    );
    await tester.pumpAndSettle();
    expect(find.text('This amount is what gets recorded'), findsOneWidget);
    // Resolved silently from the template's own default, so the common path is one tap.
    expect(find.text('Paid from'), findsOneWidget);
    expect(find.text('Which account does this come from? Alaya remembers it on the bill.'),
        findsNothing);
  });

  testWidgets('it asks for an account only when nothing can answer', (tester) async {
    await pumpExpense(
      tester,
      host(
        const TransactionEditorState(
          currencyCode: 'INR',
          dateKey: kToday,
          recurringOccurrenceId: 'occ-1',
          accountMissing: true,
        ),
      ),
      overrides: overrides(rows: [due(accountId: null)], accounts: const []),
    );
    await tester.pumpAndSettle();
    expect(find.text('Which account does this come from? Alaya remembers it on the bill.'),
        findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      host(blank),
      overrides: overrides(rows: [due(dueOn: const DateKey(20260715))]),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(blank), overrides: overrides(rows: [due()]));
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  group('the account resolver', () {
    test('prefers the template default, then the app default, then a sole account', () {
      final withTemplate = ProviderContainer(
        overrides: [
          defaultAccountIdProvider.overrideWith((ref) async => 'app-1'),
          billAccountsProvider.overrideWith((ref) => Stream.value(const [account])),
        ],
      );
      addTearDown(withTemplate.dispose);
      expect(withTemplate.read(resolvedBillAccountProvider('tpl-acc')), 'tpl-acc');
    });

    test('stops at null rather than guessing between two accounts', () {
      const other = Account(
        id: 'acc-2',
        name: 'Savings',
        normalizedName: 'savings',
        kind: AccountKind.bank,
        currencyCode: 'INR',
        openingBalance: Money(0, 'INR'),
        openingBalanceDateKey: kToday,
        isArchived: false,
        includeInNetWorth: true,
        sortOrder: 1,
      );
      final container = ProviderContainer(
        overrides: [
          defaultAccountIdProvider.overrideWith((ref) async => null),
          billAccountsProvider
              .overrideWith((ref) => Stream.value(const [account, other])),
        ],
      );
      addTearDown(container.dispose);
      container.listen(billAccountsProvider, (_, __) {});
      // A withdrawal filed against the wrong account is worse than one that asked, because nothing on
      // screen would ever reveal it.
      expect(container.read(resolvedBillAccountProvider(null)), isNull);
    });
  });
}
```


### `test/features/expense/delete_transaction_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

import '../../support/expense_harness.dart';

/// **This sheet has no loading or error state, and that is not an omission.** It reads no provider and
/// awaits nothing — its only input is a text field — so an `AsyncValue` branch would be unreachable
/// code asserted by an unreachable test. §9.1's four states apply to a screen with an asynchronous
/// source; here the empty state *is* the populated one, and both are covered below.
void main() {
  Widget host() => const Scaffold(
        body: AlayaBottomSheet(child: DeleteTransactionSheet()),
      );

  testWidgets('opens empty, with the reason optional', (tester) async {
    await pumpExpense(tester, host());
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, isEmpty);
  });

  testWidgets('it ends in a delete, never a confirmation', (tester) async {
    await pumpExpense(tester, host());
    await tester.pumpAndSettle();
    // Deleting a transaction is reversible, so this sheet captures a reason and hands back — the Undo
    // comes from the caller's snack. A confirm/cancel pair here would be friction with no safety value
    // and would train people through the confirmations that do matter (§5.5).
    expect(find.widgetWithText(FilledButton, 'Delete transaction'), findsOneWidget);
  });

  testWidgets('typing a reason fills the field it will hand back', (tester) async {
    await pumpExpense(tester, host());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'duplicate');
    await tester.pump();
    expect(find.text('duplicate'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```


### `test/features/expense/freeze_conversion_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, and the rule the sheet exists to serve: the transaction's own currency is never a
/// target, because converting a figure into itself is not a snapshot.
void main() {
  const inr = Currency(
    code: 'INR',
    name: 'Indian rupee',
    symbol: '₹',
    decimalDigits: 2,
    isEnabled: true,
    sortOrder: 0,
  );
  const usd = Currency(
    code: 'USD',
    name: 'US dollar',
    symbol: r'$',
    decimalDigits: 2,
    isEnabled: true,
    sortOrder: 1,
  );

  List<Override> overrides({
    List<Currency>? currencies,
    bool pending = false,
    bool fail = false,
  }) =>
      [
        if (pending)
          enabledCurrenciesProvider.overrideWith((ref) => pendingStream<List<Currency>>())
        else if (fail)
          enabledCurrenciesProvider
              .overrideWith((ref) => Stream<List<Currency>>.error(StateError('boom')))
        else
          enabledCurrenciesProvider
              .overrideWith((ref) => Stream.value(currencies ?? const [inr, usd])),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(child: FreezeConversionSheet(excludeCode: 'INR')),
      );

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(pending: true));
    await tester.pump();
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('nothing else enabled reads as nothing to convert into', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(currencies: const [inr]));
    await tester.pumpAndSettle();
    // Only the transaction's own currency is enabled, and that is excluded — so there is genuinely
    // nowhere to freeze into, which is an empty state rather than an error.
    expect(find.byType(EmptyState), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(fail: true));
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated offers every currency except the transaction own', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.text('US dollar'), findsOneWidget);
    // Law L9: the original amount and its currency are immutable, and a snapshot into the same
    // currency would be a rewrite dressed as a conversion.
    expect(find.text('Indian rupee'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```


### `test/features/expense/line_item_editor_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

import '../../support/expense_harness.dart';

/// The most load-bearing sheet in the module: it decides whether a receipt reaches the inventory.
void main() {
  const kilogram = Unit(
    code: 'kg',
    category: UnitCategory.weight,
    factorToBaseMilli: 1000000,
    displayName: 'kilogram',
    isSystem: true,
    sortOrder: 1,
  );
  const onion = Item(
    id: 'item-1',
    name: 'Onion',
    normalizedName: 'onion',
    unitCategory: UnitCategory.weight,
    defaultDisplayUnitCode: 'kg',
    itemKind: ItemKind.food,
    isFavorite: false,
  );

  List<Override> overrides({List<Item> items = const [onion]}) => [
        lineEditorItemsProvider.overrideWith((ref) => Stream.value(items)),
        lineEditorUnitsProvider(UnitCategory.weight)
            .overrideWith((ref) => Stream.value(const <Unit>[kilogram])),
        lineEditorUnitsProvider(null).overrideWith((ref) => Stream.value(const <Unit>[])),
      ];

  Widget host() => const Scaffold(
        body: AlayaBottomSheet(
          child: LineItemEditor(
            currencyCode: 'INR',
            decimalDigits: 2,
            defaultDestination: TransactionLineDestination.none,
          ),
        ),
      );

  testWidgets('opens on the form, which is its empty state', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(find.byType(LineItemEditor), findsOneWidget);
    expect(find.byType(QtyField), findsNothing);
  });

  testWidgets('an empty catalogue still offers inline item creation', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(items: const []));
    await tester.pumpAndSettle();
    // Without this a user on a fresh install itemises a receipt, saves, and nothing reaches the
    // inventory — `_planBatch` refuses a line with no `itemId`.
    expect(find.text('New item'), findsOneWidget);
    expect(find.text('No items yet — create one so this line becomes stock.'), findsOneWidget);
  });

  testWidgets('a quantity is offered only once an item is linked', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // A `Qty` is an integer plus a `UnitCategory`, and the category comes from the item (Law L8), so a
    // quantity on a free-text line would be a number whose meaning nothing records.
    expect(find.byType(QtyField), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsWidgets);
  });

  testWidgets('it offers two commits: one line, or one and another', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    // Itemising a fifteen-line receipt should not mean fifteen open-close cycles.
    expect(find.text('Save & add another'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(), textScale: 2);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('loading the catalogue still lets a description be typed', (tester) async {
    await pumpExpense(
      tester,
      host(),
      overrides: [
        lineEditorItemsProvider.overrideWith((ref) => pendingStream<List<Item>>()),
        lineEditorUnitsProvider(null).overrideWith((ref) => Stream.value(const <Unit>[])),
      ],
    );
    await tester.pump();
    // A capture sheet takes its first keystroke on its first frame (§5.2): the item list is still
    // arriving and the description field is already there.
    expect(find.byType(TextFormField), findsWidgets);
  });

  testWidgets('a failed catalogue read costs the link, not the line', (tester) async {
    await pumpExpense(
      tester,
      host(),
      overrides: [
        lineEditorItemsProvider
            .overrideWith((ref) => Stream<List<Item>>.error(StateError('boom'))),
        lineEditorUnitsProvider(null).overrideWith((ref) => Stream.value(const <Unit>[])),
      ],
    );
    await tester.pumpAndSettle();
    // A free-text line needs no item at all, so a broken catalogue must not stop one being recorded.
    expect(find.byType(LineItemEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
```


---

## COVERAGE — Part 1

No ARCH_5 §7 data rows close in Part 1; it builds the kit those rows are surfaced *with*. What it
does close is ARCH_5 §4.2, in full:

| ARCH_5 §4.2 file | Status |
|---|---|
| `alaya_icon_size.dart` | delivered — closes ARCH_4 A52, the last unguarded literal class |
| `date_text.dart` | delivered — Law U7's third path, `full` / `medium` / `dayMonth` / `relative` |
| `key_value_row.dart` | delivered — renders nothing when the value is null |
| `status_chip.dart` | delivered — one home for all seven statuses, label always required (U17) |
| `alaya_form_scaffold.dart` | delivered — scroll body, sticky footer (U14), unsaved guard (U10) |
| `alaya_list_skeleton.dart` | delivered — the list loading state (§5.2) |
| `alaya_search_field.dart` | delivered — debounced through the new `AlayaDurations.debounce` |
| `filter_chip_bar.dart` | delivered — hidden when empty, `Wrap` so it survives U15 |
| `undo_snack.dart` | delivered — the single implementation of U9's three outcomes |

Two files beyond the nine, both forced by a law rather than chosen: `alaya_durations.dart` gains
`debounce` because U6 admits no raw `Duration` in a widget, and `app_en.arb` gains `dateToday`,
`dateYesterday`, `dateTomorrow` plus the status and discard strings Part 2 needs.

`test/shared/layout_overflow_test.dart` grew by four cases — three for `AlayaFormScaffold` and one
for `AlayaListSkeleton` — plus three text-scale cases for the new rows, as U2 requires of the phase
that creates them.


---

# Part 2a — the ledger surface (ARCH_5 archetype C)

Seven files. The list, its row, the filter, the nudge, and the complete ARB for the **whole** of 6A
so Parts 2b and 2c never touch it again.

**Two deviations recorded rather than improvised** — see the notes after the coverage table.

### `lib/features/expense/state/transaction_filter.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/services/date_range_service.dart';

/// What is currently narrowing the transaction list.
///
/// Immutable, and every field is one the user can see as a chip. A filter the user cannot see is a
/// bug report waiting to happen: a list quietly constrained by a filter set on a previous visit is
/// indistinguishable from a list that lost its data (ARCH_5 §3 archetype C).
///
/// **There is deliberately no tag field.** No 3A contract exposes a tag-to-transactions reverse
/// lookup, so filtering by tag would mean one query per visible row. Recorded as an ARCH_5 §7.3 gap
/// owned by 7B, which builds the analytics read model that needs the same join.
class TransactionFilter {
  /// Creates a filter. The default is the last thirty days, unfiltered otherwise.
  const TransactionFilter({
    this.preset = DateRangePreset.last30Days,
    this.customRange,
    this.kinds = const <TransactionKind>{},
    this.subtypes = const <TransactionSubtype>{},
    this.accountId,
    this.payeeId,
    this.needsReviewOnly = false,
  });

  /// The reporting window, resolved against the clock by `DateRangeService`.
  final DateRangePreset preset;

  /// The window the user picked by hand. Only meaningful when [preset] is custom.
  final DateRange? customRange;

  /// Which kinds to show. Empty means all of them.
  final Set<TransactionKind> kinds;

  /// Which subtypes to show. Empty means all of them.
  final Set<TransactionSubtype> subtypes;

  /// Restrict to transactions touching this account on either side.
  final String? accountId;

  /// Restrict to one counterparty.
  final String? payeeId;

  /// Show only transactions still flagged as needing details.
  ///
  /// What the needs-review nudge switches on. Without it the banner would have nowhere real to
  /// send the user: widening the date window shows the flagged rows *somewhere* in the list rather
  /// than showing the user the work they were just told they had.
  final bool needsReviewOnly;

  /// Whether anything is narrowing the list beyond the default window.
  bool get isNarrowed =>
      preset != DateRangePreset.last30Days ||
      kinds.isNotEmpty ||
      subtypes.isNotEmpty ||
      accountId != null ||
      payeeId != null ||
      needsReviewOnly;

  /// True when [transaction] survives the non-date parts of this filter.
  ///
  /// The date window is applied by the query rather than here — `watchByDateRange` is indexed and
  /// re-filtering its output by date in Dart would be doing the work twice.
  bool admits({
    required TransactionKind kind,
    required TransactionSubtype subtype,
    required String? fromAccountId,
    required String? toAccountId,
    required String? transactionPayeeId,
    required bool needsReview,
  }) {
    if (needsReviewOnly && !needsReview) return false;
    if (kinds.isNotEmpty && !kinds.contains(kind)) return false;
    if (subtypes.isNotEmpty && !subtypes.contains(subtype)) return false;
    if (accountId != null && fromAccountId != accountId && toAccountId != accountId) return false;
    if (payeeId != null && transactionPayeeId != payeeId) return false;
    return true;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// The nullable fields take an explicit `clear` flag rather than relying on a null argument, which
  /// would be indistinguishable from "leave it alone" and is the standard way a copyWith quietly
  /// refuses to let a user clear a filter.
  TransactionFilter copyWith({
    DateRangePreset? preset,
    DateRange? customRange,
    bool clearCustomRange = false,
    Set<TransactionKind>? kinds,
    Set<TransactionSubtype>? subtypes,
    String? accountId,
    bool clearAccount = false,
    String? payeeId,
    bool clearPayee = false,
    bool? needsReviewOnly,
  }) =>
      TransactionFilter(
        preset: preset ?? this.preset,
        customRange: clearCustomRange ? null : (customRange ?? this.customRange),
        kinds: kinds ?? this.kinds,
        subtypes: subtypes ?? this.subtypes,
        accountId: clearAccount ? null : (accountId ?? this.accountId),
        payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
        needsReviewOnly: needsReviewOnly ?? this.needsReviewOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.preset == preset &&
      other.customRange == customRange &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds) &&
      other.subtypes.length == subtypes.length &&
      other.subtypes.containsAll(subtypes) &&
      other.accountId == accountId &&
      other.payeeId == payeeId &&
      other.needsReviewOnly == needsReviewOnly;

  @override
  int get hashCode => Object.hash(
        preset,
        customRange,
        Object.hashAllUnordered(kinds),
        Object.hashAllUnordered(subtypes),
        accountId,
        payeeId,
        needsReviewOnly,
      );
}
```

### `lib/features/expense/providers/transaction_list_providers.dart`

```dart
/// View-model providers for the transaction list (ARCH_5 U19).
///
/// **Not one repository or engine provider here.** Every dependency is watched from
/// `app/providers/`, which is what stops one repository acquiring three providers and
/// `ItemCategoryResolver` — which caches — being constructed once per feature.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/expense/state/transaction_filter.dart';

/// The list's active filter.
///
/// A plain `Notifier` rather than a family: there is one transaction list, and giving it a family
/// argument it never varies over would create a second instance the first time a caller passed a
/// different key.
final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

/// Mutates the transaction list's filter.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  /// Sets the reporting window to a named preset, dropping any hand-picked range.
  void setPreset(DateRangePreset preset) =>
      state = state.copyWith(preset: preset, clearCustomRange: true);

  /// Sets a hand-picked window.
  void setCustomRange(DateRange range) =>
      state = state.copyWith(preset: DateRangePreset.custom, customRange: range);

  /// Adds or removes a kind from the filter.
  void toggleKind(TransactionKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Adds or removes a subtype from the filter.
  void toggleSubtype(TransactionSubtype subtype) {
    final next = {...state.subtypes};
    if (next.contains(subtype)) {
      next.remove(subtype);
    } else {
      next.add(subtype);
    }
    state = state.copyWith(subtypes: next);
  }

  /// Restricts to one account, or clears the restriction when [accountId] is null.
  void setAccount(String? accountId) => state = accountId == null
      ? state.copyWith(clearAccount: true)
      : state.copyWith(accountId: accountId);

  /// Restricts to one payee, or clears the restriction when [payeeId] is null.
  void setPayee(String? payeeId) => state = payeeId == null
      ? state.copyWith(clearPayee: true)
      : state.copyWith(payeeId: payeeId);

  /// Shows only the transactions the needs-review nudge is counting.
  ///
  /// Widens the window to all time at the same time: a flagged transaction from six weeks ago is
  /// exactly the one the nudge exists to surface, and leaving the default thirty-day window on
  /// would hide it behind the very count that pointed at it.
  void showNeedsReviewOnly() => state = state.copyWith(
        needsReviewOnly: true,
        preset: DateRangePreset.allTime,
        clearCustomRange: true,
      );

  /// Stops restricting to flagged transactions.
  void clearNeedsReviewOnly() => state = state.copyWith(needsReviewOnly: false);

  /// Returns to the default window with nothing else narrowed.
  void clear() => state = const TransactionFilter();
}

/// The date window the current filter resolves to.
///
/// Resolved through `DateRangeService` against the injected clock, never `DateTime.now()`, so a
/// date-sensitive widget test is reproducible.
final transactionRangeProvider = Provider<DateRange>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final service = ref.watch(dateRangeServiceProvider);
  final today = ref.watch(clockProvider).today();
  if (filter.preset == DateRangePreset.custom) {
    return filter.customRange ?? (from: DateRangeService.earliest, to: today);
  }
  return service.resolve(filter.preset, today) ??
      (from: DateRangeService.earliest, to: today);
});

/// The filtered transactions, newest first.
///
/// The date window is applied by the indexed query; the rest is applied in Dart, because those
/// predicates are over a page of rows rather than the whole table.
final filteredTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final range = ref.watch(transactionRangeProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .map(
        (rows) => rows
            .where(
              (t) => filter.admits(
                kind: t.kind,
                subtype: t.subtype,
                fromAccountId: t.fromAccountId,
                toAccountId: t.toAccountId,
                transactionPayeeId: t.payeeId,
                needsReview: t.needsReview,
              ),
            )
            .toList(),
      );
});

/// One day's transactions, for a sticky header.
class TransactionDayGroup {
  /// Creates a day group.
  const TransactionDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The filtered transactions grouped into days, newest day first.
final transactionDaysProvider = Provider<AsyncValue<List<TransactionDayGroup>>>(
  (ref) => ref.watch(filteredTransactionsProvider).whenData(_groupByDay),
);

List<TransactionDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      TransactionDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// How many transactions still need details, for the nudge.
final needsReviewCountProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchNeedsReviewCount(),
);

/// Accounts by id, so a row can name one without a query per row.
final accountsByIdProvider = StreamProvider<Map<String, Account>>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// Selectable accounts in sort order, for a picker or a chip row.
final selectableAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Payees by id, so a row can name one without a query per row.
final payeesByIdProvider = StreamProvider<Map<String, Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// The home currency's code, defaulting to INR before onboarding has run.
final homeCurrencyCodeProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ?? 'INR',
);

/// The home currency's decimal digits, so no amount hardcodes 2 (ARCH_1 §4.1).
///
/// JPY is 0 and the rest are 2, which is exactly why the figure is read from the `currencies` row
/// rather than assumed at each call site.
final homeDecimalDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(homeCurrencyCodeProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});
```

### `lib/features/expense/presentation/widgets/transaction_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
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

    return Material(
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
}
```

### `lib/features/expense/presentation/widgets/needs_review_banner.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The nudge that surfaces `transactions.needsReview` (ARCH_5 �7.2).
///
/// Quick-add captures an amount and nothing else, which is the whole point of an optional-first
/// capture path (Law U11) ? but a column that records "this is incomplete" and is never shown turns
/// a deliberate shortcut into silent data rot. This is the row that closes that loop.
///
/// Renders nothing at zero. A banner reading "0 transactions need details" is noise on every screen
/// where the user is already up to date.
class NeedsReviewBanner extends StatelessWidget {
  /// Creates the nudge for [count] transactions, opening the filtered list through [onTap].
  const NeedsReviewBanner({
    required this.count,
    required this.onTap,
    super.key,
  });

  /// How many transactions still need details.
  final int count;

  /// Shows them.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final strings = AlayaStrings.of(context);
    // Above roughly 1.5x, the message and the action cannot share a line at 320dp. The action is
    // non-flexible, so it takes its full natural width and leaves the message a column barely wider
    // than a character ? which wrapped "2 transactions need details" to twenty-nine lines and made
    // this banner 1,084px tall, starving the ledger beneath it of every pixel (Law U15).
    //
    // Stacking is the fix rather than truncating: ellipsising the count is the one thing this nudge
    // cannot do, because the count *is* the message.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    final message = Text(
      strings.needsReviewBanner(count),
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
    );
    final action = Text(
      strings.needsReviewAction,
      style: AlayaTypography.button.copyWith(color: semantic.transfer),
    );
    final leading = Icon(
      Icons.edit_note,
      size: AlayaIconSize.md,
      color: semantic.transfer,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xxs,
      ),
      child: Material(
        color: semantic.transfer.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderSm,
          side: BorderSide(color: semantic.transfer.withValues(alpha: 0.28)),
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
                vertical: AlayaSpacing.xs,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            leading,
                            const SizedBox(width: AlayaSpacing.xs),
                            Expanded(child: message),
                          ],
                        ),
                        const SizedBox(height: AlayaSpacing.xs),
                        action,
                      ],
                    )
                  : Row(
                      children: [
                        leading,
                        const SizedBox(width: AlayaSpacing.xs),
                        Expanded(child: message),
                        const SizedBox(width: AlayaSpacing.xs),
                        action,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
```

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
  "insightAnalyticsPending": "Spending breakdowns arrive with the analytics module.",
  "@insightAnalyticsPending": {
    "description": "Honest empty state: AnalyticsService has no data adapter until Phase 7B (ARCH_4 §5.1 item 15)."
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
  "navBackToDashboard": "Back to dashboard"
}
```


### `lib/features/expense/providers/transaction_search_providers.dart`

```dart
/// Full-text search over transaction notes, kept separate from the filter providers.
///
/// A different concern with a different shape: the filter narrows a live stream, search resolves a
/// one-shot query against FTS5. Folding them into one provider would mean a stream that sometimes
/// is not one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The current search query, empty when the user is not searching.
final transactionSearchQueryProvider =
    NotifierProvider<TransactionSearchQueryNotifier, String>(
  TransactionSearchQueryNotifier.new,
);

/// Holds the search box's settled query.
class TransactionSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Replaces the query. Already debounced by `AlayaSearchField`.
  void set(String query) => state = query;

  /// Clears the query, returning the list to its filtered view.
  void clear() => state = '';
}

/// Whether the list is showing search results rather than the filtered window.
final isSearchingProvider =
    Provider<bool>((ref) => ref.watch(transactionSearchQueryProvider).isNotEmpty);

/// Search results for the current query, best match first.
///
/// Capped rather than unbounded: FTS over ten thousand notes can match most of them, and a list the
/// user has to scroll for a minute is not a search result.
final transactionSearchResultsProvider = FutureProvider<List<Transaction>>((ref) async {
  final query = ref.watch(transactionSearchQueryProvider);
  if (query.isEmpty) return const <Transaction>[];
  return ref.watch(transactionRepositoryProvider).search(query, limit: 100);
});
```

### `lib/features/expense/presentation/widgets/transaction_filter_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Narrows the transaction list (ARCH_5 §3 archetype A).
///
/// Chips rather than dropdowns throughout. A filter sheet is read at a glance and closed — a column
/// of dropdowns hides the current state behind six taps, which is the opposite of what a sheet whose
/// whole job is "show me what is on" should do.
///
/// **There is no tag filter.** No 3A contract exposes a tag-to-transactions reverse lookup, so it
/// would cost one query per visible row. Recorded as an ARCH_5 §7.3 gap owned by 7B, which builds
/// the analytics read model that needs the same join.
class TransactionFilterSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const TransactionFilterSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => const TransactionFilterSheet(),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>{};

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.filterTitle,
                style: AlayaTypography.cardTitle
                    .copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
            if (filter.isNarrowed)
              TextButton(
                onPressed: notifier.clear,
                child: Text(strings.filterReset),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterDateRange,
          padding: const EdgeInsets.only(top: AlayaSpacing.md, bottom: AlayaSpacing.xs),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final preset in DateRangePreset.values)
              if (preset != DateRangePreset.custom)
                _Choice(
                  label: rangeLabel(strings, preset),
                  selected: filter.preset == preset,
                  onTap: () => notifier.setPreset(preset),
                ),
          ],
        ),
        SectionHeader(
          label: strings.filterKind,
          padding: const EdgeInsets.only(top: AlayaSpacing.md, bottom: AlayaSpacing.xs),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in TransactionKind.values)
              _Choice(
                label: TransactionRow.kindLabel(strings, kind),
                selected: filter.kinds.contains(kind),
                onTap: () => notifier.toggleKind(kind),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterSubtype,
          padding: const EdgeInsets.only(top: AlayaSpacing.md, bottom: AlayaSpacing.xs),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final subtype in TransactionSubtype.values)
              _Choice(
                label: TransactionRow.subtypeLabel(strings, subtype),
                selected: filter.subtypes.contains(subtype),
                onTap: () => notifier.toggleSubtype(subtype),
              ),
          ],
        ),
        SectionHeader(
          label: strings.labelAccount,
          padding: const EdgeInsets.only(top: AlayaSpacing.md, bottom: AlayaSpacing.xs),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final account in accounts.values)
              _Choice(
                label: account.name,
                selected: filter.accountId == account.id,
                onTap: () => notifier.setAccount(
                  filter.accountId == account.id ? null : account.id,
                ),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.filterApply),
        ),
      ],
    );
  }

  /// The localised name of a range preset. Static so the chip bar reads the same mapping.
  static String rangeLabel(AlayaStrings strings, DateRangePreset preset) => switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}
```


### `lib/app/router/routes.dart`

```dart
/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern = '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern = '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern = '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern = '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) => id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The nine drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
```

### `lib/features/expense/presentation/screens/transaction_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/providers/transaction_search_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The transaction ledger (ARCH_5 §3 archetype C).
///
/// **Search and filter live in the body, not the app bar.** The drawer shell owns the `Scaffold` and
/// its `AppBar` for every top-level destination, so a destination cannot contribute app-bar actions —
/// and a nested `Scaffold` carrying a second app bar would be worse than none. Putting them in the
/// body also makes this screen and the catalogue archetype consistent, where ARCH_5 §3 archetype D
/// already says the search field is pinned rather than hidden behind a magnifying glass.
///
/// **No pull-to-refresh.** The data is local and streamed, so a refresh gesture cannot do anything;
/// offering one teaches the user the app is slow.
class TransactionListScreen extends ConsumerWidget {
  /// Creates the ledger.
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final searching = ref.watch(isSearchingProvider);

    return Scaffold(
      // A nested Scaffold with no app bar: the shell above supplies the bar and the drawer, this one
      // supplies the FAB slot and a snack-bar host for the delete-and-undo flow.
      body: Column(
        children: [
          const _Toolbar(),
          if (!searching) ...[
            const _NeedsReviewRow(),
            const _ActiveFilters(),
          ],
          Expanded(child: searching ? const _SearchResults() : const _GroupedList()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.transactionNew),
        tooltip: strings.addExpense,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final narrowed = ref.watch(transactionFilterProvider).isNarrowed;
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.xs,
        AlayaSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: AlayaSearchField(
              hintText: strings.searchTransactionsHint,
              clearLabel: strings.actionClearSearch,
              onChanged: ref.read(transactionSearchQueryProvider.notifier).set,
            ),
          ),
          IconButton(
            onPressed: () => TransactionFilterSheet.show(context),
            tooltip: strings.filterTitle,
            icon: Icon(
              narrowed ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: AlayaIconSize.lg,
              color: narrowed ? semantic.transfer : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsReviewRow extends ConsumerWidget {
  const _NeedsReviewRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);
    // Hidden once the user has acted on it: a nudge that stays put while you are looking at exactly
    // what it pointed at reads as an instruction you have failed to follow.
    if (filter.needsReviewOnly) return const SizedBox.shrink();
    final count = ref.watch(needsReviewCountProvider).valueOrNull ?? 0;
    return NeedsReviewBanner(
      count: count,
      onTap: ref.read(transactionFilterProvider.notifier).showNeedsReviewOnly,
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>{};
    final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};

    return FilterChipBar(
      clearAllLabel: strings.actionClearAll,
      onClearAll: notifier.clear,
      filters: [
        if (filter.needsReviewOnly)
          ActiveFilter(
            label: strings.statusNeedsReview,
            onRemove: notifier.clearNeedsReviewOnly,
          ),
        if (filter.preset != DateRangePreset.last30Days)
          ActiveFilter(
            label: TransactionFilterSheet.rangeLabel(strings, filter.preset),
            onRemove: () => notifier.setPreset(DateRangePreset.last30Days),
          ),
        for (final kind in filter.kinds)
          ActiveFilter(
            label: TransactionRow.kindLabel(strings, kind),
            onRemove: () => notifier.toggleKind(kind),
          ),
        for (final subtype in filter.subtypes)
          ActiveFilter(
            label: TransactionRow.subtypeLabel(strings, subtype),
            onRemove: () => notifier.toggleSubtype(subtype),
          ),
        if (filter.accountId != null)
          ActiveFilter(
            label: strings.filterChipAccount(
              accounts[filter.accountId]?.name ?? filter.accountId!,
            ),
            onRemove: () => notifier.setAccount(null),
          ),
        if (filter.payeeId != null)
          ActiveFilter(
            label: strings.filterChipPayee(
              payees[filter.payeeId]?.name ?? filter.payeeId!,
            ),
            onRemove: () => notifier.setPayee(null),
          ),
      ],
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final days = ref.watch(transactionDaysProvider);

    return days.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(filteredTransactionsProvider),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoTransactions,
            body: strings.emptyBodyNoTransactions,
            icon: Icons.receipt_long_outlined,
            actionLabel: strings.addExpense,
            onAction: () => context.push(Routes.transactionNew),
          );
        }
        final clock = ref.watch(clockProvider);
        final background = Theme.of(context).scaffoldBackgroundColor;
        return CustomScrollView(
          slivers: [
            for (final group in groups)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      date: group.date,
                      clock: clock,
                      background: background,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: group.transactions.length,
                    itemBuilder: (context, index) =>
                        _Row(transaction: group.transactions[index]),
                  ),
                ],
              ),
            const SliverToBoxAdapter(child: SizedBox(height: AlayaSpacing.xxxl)),
          ],
        );
      },
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final results = ref.watch(transactionSearchResultsProvider);

    return results.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(transactionSearchResultsProvider),
      ),
      // Search results are ranked by relevance, so they are deliberately not grouped by day — a date
      // header over a relevance-ordered list asserts an order the list does not have.
      data: (rows) => rows.isEmpty
          ? EmptyState(
              title: strings.emptyTitleNoResults,
              body: strings.emptyBodyNoResults,
              icon: Icons.search_off_outlined,
            )
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) => _Row(transaction: rows[index]),
            ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>{};
    final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;

    return TransactionRow(
      transaction: transaction,
      decimalDigits: digits,
      payee: payeeId == null ? null : payees[payeeId],
      fromAccount: from == null ? null : accounts[from],
      toAccount: to == null ? null : accounts[to],
      onTap: () => context.push(Routes.transactionDetail(transaction.id)),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  const _DayHeader({
    required this.date,
    required this.clock,
    required this.background,
  });

  final DateKey date;
  final Clock clock;
  final Color background;

  // The tap-target floor rather than a hand-picked figure: it is the one height token that stays
  // legible when the text scale doubles, which a guessed 36 would not.
  @override
  double get minExtent => AlayaSpacing.minTapTarget;

  @override
  double get maxExtent => AlayaSpacing.minTapTarget;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: DateText.relative(
              date,
              clock: clock,
              textStyle: AlayaTypography.sectionHeader,
            ),
          ),
        ),
      );

  @override
  bool shouldRebuild(_DayHeader oldDelegate) =>
      oldDelegate.date != date || oldDelegate.background != background;
}
```

### `lib/features/expense/providers/quick_add_providers.dart`

```dart
/// View-model state for the quick-add sheet (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// What the quick-add sheet is holding.
class QuickAddState {
  /// Creates the sheet's state.
  const QuickAddState({
    this.kind = TransactionKind.withdrawal,
    this.amount,
    this.accountId,
    this.tagId,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
  });

  /// Money out by default: an expense tracker is opened to record spending far more often than
  /// income, and defaulting to the rarer case costs a tap every single time.
  final TransactionKind kind;

  /// The typed amount, null while it does not parse. The one required field (Law U11).
  final Money? amount;

  /// The chosen account. Null lets the repository fill it from last-used, then the default.
  final String? accountId;

  /// An optional tag.
  final String? tagId;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field. An int rather than a bool so two consecutive rejections
  /// shake twice — a bool already true produces no change and reads as the app ignoring the tap.
  final int shakeTrigger;

  /// Whether the sheet holds anything worth confirming before a dismissal.
  bool get isDirty => amount != null || tagId != null;

  /// Returns a copy with the supplied changes.
  QuickAddState copyWith({
    TransactionKind? kind,
    Money? amount,
    bool clearAmount = false,
    String? accountId,
    String? tagId,
    bool clearTag = false,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
  }) =>
      QuickAddState(
        kind: kind ?? this.kind,
        amount: clearAmount ? null : (amount ?? this.amount),
        accountId: accountId ?? this.accountId,
        tagId: clearTag ? null : (tagId ?? this.tagId),
        submitting: submitting ?? this.submitting,
        amountMissing: amountMissing ?? this.amountMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
      );
}

/// The quick-add sheet's view model.
final quickAddProvider =
    NotifierProvider.autoDispose<QuickAddNotifier, QuickAddState>(QuickAddNotifier.new);

/// Captures an amount and as little else as the user is willing to give (Law U11).
class QuickAddNotifier extends AutoDisposeNotifier<QuickAddState> {
  @override
  QuickAddState build() => const QuickAddState();

  /// Switches between money in and money out.
  void setKind(TransactionKind kind) => state = state.copyWith(kind: kind);

  /// Records the parsed amount, clearing any outstanding "enter an amount" message.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true)
      : state.copyWith(amount: amount, amountMissing: false);

  /// Chooses the account the money moves through.
  void setAccount(String accountId) => state = state.copyWith(accountId: accountId);

  /// Applies or removes the optional tag.
  void toggleTag(String tagId) => state = state.tagId == tagId
      ? state.copyWith(clearTag: true)
      : state.copyWith(tagId: tagId);

  /// Saves, returning the created transaction, or null when the form was rejected.
  ///
  /// Marks the row `needsReview` so the nudge can offer it back later: capturing an amount and
  /// nothing else is the point of this sheet, and the flag is what stops that shortcut becoming
  /// silent data rot (ARCH_5 §7.2).
  Future<Transaction?> submit() async {
    final amount = state.amount;
    if (amount == null) {
      state = state.copyWith(
        amountMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    state = state.copyWith(submitting: true);

    final clock = ref.read(clockProvider);
    final isDeposit = state.kind == TransactionKind.deposit;
    final transaction = Transaction(
      id: ref.read(uidGeneratorProvider).generate(),
      kind: state.kind,
      subtype: isDeposit ? TransactionSubtype.otherIn : TransactionSubtype.otherOut,
      occurredAtUtc: clock.now().toUtc(),
      dateKey: clock.today(),
      originalAmount: amount,
      needsReview: true,
      fromAccountId: isDeposit ? null : state.accountId,
      toAccountId: isDeposit ? state.accountId : null,
    );

    final tagId = state.tagId;
    final result = await ref.read(transactionRepositoryProvider).create(
          transaction: transaction,
          tagIds: [if (tagId != null) tagId],
        );
    state = state.copyWith(submitting: false);
    return result.valueOrNull;
  }

  /// Removes a transaction this sheet created, for the snack bar's Undo.
  Future<void> undo(String id) async {
    await ref.read(transactionRepositoryProvider).delete(id: id);
  }
}

/// Tags offered in the sheet, scoped to the direction the user has chosen.
///
/// A tag scoped to withdrawals must not appear while the toggle says money in — "Kitchen" in the
/// deposit picker is the spec's own test case for the scoping matrix (ARCH_2 §14).
final quickAddTagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  final kind = ref.watch(quickAddProvider.select((s) => s.kind));
  final scope = kind == TransactionKind.deposit ? TagScope.deposit : TagScope.withdrawal;
  return ref.watch(tagRepositoryProvider).watchByScope(scope);
});
```

### `lib/features/expense/presentation/sheets/quick_add_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Captures a transaction in one field (ARCH_5 §3 archetype A).
///
/// **The amount is the only required field, and everything else is a chip.** This sheet is used at a
/// till, one-handed, in under eight seconds — a column of dropdowns would make it a form nobody
/// fills in at a checkout, and the row would simply not get recorded. Every other field has a
/// defensible default and the row is saved `needsReview`, which is what makes the shortcut honest
/// rather than lossy (Law U11, ARCH_5 §7.2).
///
/// Chips rather than pickers for the same reason: a chip row shows the current choice *and* the
/// likely alternatives without a tap, where a dropdown hides both behind one.
class QuickAddSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const QuickAddSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => const QuickAddSheet(),
      );

  Future<void> _save(BuildContext context, WidgetRef ref, {required bool thenEdit}) async {
    final strings = AlayaStrings.of(context);
    final navigator = Navigator.of(context);
    final messengerContext = context;
    final created = await ref.read(quickAddProvider.notifier).submit();
    if (created == null) return;
    if (navigator.canPop()) navigator.pop();
    if (!messengerContext.mounted) return;

    if (thenEdit) {
      messengerContext.push(Routes.transactionEdit(created.id));
      return;
    }
    showUndoSnack(
      messengerContext,
      message: strings.actionSaved,
      undoLabel: strings.actionUndo,
      onUndo: () => ref.read(quickAddProvider.notifier).undo(created.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(quickAddProvider);
    final notifier = ref.read(quickAddProvider.notifier);
    final currency = ref.watch(homeCurrencyCodeProvider).valueOrNull ?? 'INR';
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final tags = ref.watch(quickAddTagsProvider).valueOrNull ?? const <Tag>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.quickAddTitle,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.quickAddMoneyOut),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.quickAddMoneyIn),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            autofocus: true,
            label: strings.labelAmount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelAccount,
            children: [
              for (final account in accounts)
                _Choice(
                  label: account.name,
                  selected: state.accountId == account.id,
                  onTap: () => notifier.setAccount(account.id),
                ),
            ],
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelTags,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () => notifier.toggleTag(tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting ? null : () => _save(context, ref, thenEdit: false),
          child: Text(strings.quickAddSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: state.submitting ? null : () => _save(context, ref, thenEdit: true),
          child: Text(strings.actionAddDetails),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AlayaTypography.label.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(spacing: AlayaSpacing.xs, runSpacing: AlayaSpacing.xs, children: children),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
      );
}
```

### `lib/features/expense/providers/transaction_detail_providers.dart`

```dart
/// View-model providers for one transaction's detail screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// One transaction, re-read whenever it changes.
///
/// A `StreamProvider` over the date-range watch would be the wrong shape here — the detail screen
/// wants one row, and `byId` is a future. It is invalidated explicitly after a write instead.
final transactionByIdProvider =
    FutureProvider.autoDispose.family<Transaction?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).byId(id),
);

/// The lines itemising one transaction, in entry order.
final transactionLinesProvider =
    StreamProvider.autoDispose.family<List<TransactionLine>, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchLines(id),
);

/// One transaction's allocation summary, for the unallocated chip.
final transactionAllocationProvider =
    StreamProvider.autoDispose.family<TransactionAllocation?, String>(
  (ref, id) => ref.watch(transactionRepositoryProvider).watchAllocation(id),
);

/// The tags applied to one transaction.
final transactionTagsProvider = StreamProvider.autoDispose.family<List<Tag>, String>(
  (ref, id) => ref.watch(tagRepositoryProvider).watchForTransaction(id),
);

/// Payment methods by id, so a detail row can name one without a query per row.
final paymentMethodsByIdProvider = StreamProvider<Map<String, PaymentMethod>>(
  (ref) => ref
      .watch(paymentMethodRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// The currencies a conversion may be frozen into.
final enabledCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// Writes for the detail screen, so the widget holds no repository call of its own.
final transactionActionsProvider = Provider<TransactionActions>(
  (ref) => TransactionActions(ref),
);

/// Delete, undo and freeze, with the invalidations each one implies.
class TransactionActions {
  /// Creates the action set.
  const TransactionActions(this._ref);

  final Ref _ref;

  /// Deletes [id], optionally recording [reason], and reports what it detached.
  ///
  /// Never cascades to the batches or assets the transaction's lines created — you deleted a
  /// receipt, not the groceries (anomaly A10). The returned report is what lets the screen offer to
  /// remove a provably untouched batch as a separate, explicit action.
  Future<DetachedArtefacts?> delete(String id, {String? reason}) async {
    final result =
        await _ref.read(transactionRepositoryProvider).delete(id: id, reason: reason);
    _ref.invalidate(transactionByIdProvider(id));
    return result.valueOrNull;
  }

  // There is deliberately no undoDelete here, and it is a contract gap rather than an omission.
  //
  // `TransactionRepository` exposes exactly one deletion method and no `restore`. `update()` cannot
  // stand in for one: it reads `TransactionDao.byId` first, that DAO selects from
  // `v_active_transactions`, and the view filters `deleted_at IS NULL` — so a deleted row is
  // invisible to it and `update()` returns `NotFoundFailure`. An Undo wired to `update()` would
  // fail silently, which is the worst outcome Law U9 exists to prevent.
  //
  // Until `restore(String id)` is added to the 3A contract, deletion is treated as the
  // non-reversible tier of ARCH_5 §5.5: a sheet that names the consequence, not a snack with Undo.

  /// Freezes a converted snapshot of [id] into [toCurrencyCode], on the transaction's own date.
  ///
  /// A separate, frozen artefact that is never recomputed. It cannot touch the original amount or
  /// its currency — those are immutable once saved (Law L9) and the signature has no parameter for
  /// them.
  Future<bool> freezeConversion({
    required Transaction transaction,
    required String toCurrencyCode,
  }) async {
    final result = await _ref.read(transactionRepositoryProvider).freezeConversion(
          id: transaction.id,
          on: transaction.dateKey,
          toCurrencyCode: toCurrencyCode,
        );
    _ref.invalidate(transactionByIdProvider(transaction.id));
    return result.isOk;
  }
}
```

### `lib/features/expense/presentation/sheets/delete_transaction_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Captures an optional reason before deleting (ARCH_5 §3 archetype A).
///
/// **This is not the primary delete.** Deleting a transaction is reversible, so the ordinary path
/// does it immediately and offers Undo — a confirmation dialog on an undoable action is friction
/// with no safety value, and it trains people to tap through the confirmations that do matter
/// (ARCH_5 §5.5).
///
/// This sheet exists only for the "delete with a reason" path, which is what surfaces
/// `transactions.deleteReason` (ARCH_5 §7.2). A household ledger genuinely needs "duplicate" or
/// "wrong account" recorded sometimes, and Phase 8B's trash screen shows it back. It still ends in
/// an Undo rather than a confirmation.
class DeleteTransactionSheet extends StatefulWidget {
  /// Creates the sheet. Prefer [show].
  const DeleteTransactionSheet({super.key});

  /// Opens the sheet, resolving to the typed reason, or null if the user backed out.
  ///
  /// An empty reason resolves to the empty string rather than null, so a caller can tell "deleted
  /// without saying why" from "changed their mind".
  static Future<String?> show(BuildContext context) => AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const DeleteTransactionSheet(),
      );

  @override
  State<DeleteTransactionSheet> createState() => _DeleteTransactionSheetState();
}

class _DeleteTransactionSheetState extends State<DeleteTransactionSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionDeleteTransaction,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.confirmDeleteBody,
          style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: strings.deleteReasonHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(strings.actionDelete),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/sheets/freeze_conversion_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Picks the currency to freeze a converted snapshot into (ARCH_5 §3 archetype A).
///
/// **A frozen snapshot, not a rewrite.** The original amount and its currency are immutable once
/// saved (Law L9); freezing writes `convertedAmountMinor`, `conversionRate`, `conversionRateRaw` and
/// `conversionDateKey` alongside them as a separate artefact that is never recomputed. The raw rate
/// string is stored so a figure the user later questions can be reproduced exactly.
///
/// The rate used is the one for the transaction's own date, resolved by the greatest
/// `rateDateKey <= D` rule — never interpolated, and marked approximate when only an earlier rate
/// exists (ARCH_3 §1.3).
class FreezeConversionSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const FreezeConversionSheet({required this.excludeCode, super.key});

  /// The transaction's own currency, which is never offered as a target.
  final String excludeCode;

  /// Opens the sheet, resolving to the chosen currency code or null.
  static Future<String?> show(BuildContext context, {required String excludeCode}) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => FreezeConversionSheet(excludeCode: excludeCode),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final currencies = ref.watch(enabledCurrenciesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionFreezeConversion,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        currencies.when(
          loading: () => AlayaListSkeleton(
            label: strings.loadingLabel,
            rows: 3,
            hasTrailing: false,
          ),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(enabledCurrenciesProvider),
          ),
          data: (rows) {
            final options = rows.where((c) => c.code != excludeCode).toList();
            if (options.isEmpty) {
              return EmptyState(
                title: strings.emptyTitleNoResults,
                body: strings.errorBodyGeneric,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final currency in options)
                  ListTile(
                    title: Text(currency.name),
                    trailing: Text(currency.code, style: AlayaTypography.label),
                    onTap: () => Navigator.of(context).pop(currency.code),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/screens/transaction_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// One transaction in full (ARCH_5 §3 archetype E).
///
/// Routed **outside** the drawer shell, so it gets a back arrow rather than a hamburger: `AppBar`
/// resolves `hasDrawer` before `canPop`, and a detail screen inside the shell leaves the system
/// gesture as the only way out (Law U18).
///
/// The hero answers the question the user opened the screen with. Everything below is a
/// [KeyValueRow], and a row with no value renders nothing at all — a screen of dashes reads as
/// broken data rather than as a record with optional fields.
///
/// **Delete is treated as the non-reversible tier of ARCH_5 §5.5**, which is a contract limitation
/// rather than a design choice: `TransactionRepository` exposes no `restore`, and `update()` cannot
/// stand in because it reads through `v_active_transactions` and so cannot see a deleted row. The
/// sheet therefore acts as the confirmation and captures the optional reason. When `restore` lands
/// with Phase 8B's trash, this becomes an immediate delete with an Undo snack.
class TransactionDetailScreen extends ConsumerWidget {
  /// Shows the transaction with [transactionId].
  const TransactionDetailScreen({required this.transactionId, super.key});

  /// Which transaction to show.
  final String transactionId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final reason = await DeleteTransactionSheet.show(context);
    if (reason == null) return;
    final detached =
        await ref.read(transactionActionsProvider).delete(transactionId, reason: reason);
    if (!context.mounted) return;
    if (detached == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.transactionDeleted);
  }

  Future<void> _freeze(BuildContext context, WidgetRef ref, Transaction transaction) async {
    final strings = AlayaStrings.of(context);
    final code = await FreezeConversionSheet.show(
      context,
      excludeCode: transaction.originalAmount.currencyCode,
    );
    if (code == null || !context.mounted) return;
    final ok = await ref.read(transactionActionsProvider).freezeConversion(
          transaction: transaction,
          toCurrencyCode: code,
        );
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.actionSaved)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionByIdProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.navExpenses),
        actions: [
          IconButton(
            onPressed: () => context.push(Routes.transactionEdit(transactionId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionByIdProvider(transactionId)),
        ),
        data: (transaction) => transaction == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(
                transaction: transaction,
                onDelete: () => _delete(context, ref),
                onFreeze: () => _freeze(context, ref, transaction),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.transaction,
    required this.onDelete,
    required this.onFreeze,
  });

  final Transaction transaction;
  final VoidCallback onDelete;
  final VoidCallback onFreeze;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(accountsByIdProvider).valueOrNull ?? const <String, Account>{};
    final payees = ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final methods =
        ref.watch(paymentMethodsByIdProvider).valueOrNull ?? const <String, PaymentMethod>{};
    final tags = ref.watch(transactionTagsProvider(transaction.id)).valueOrNull ?? const [];
    final allocation = ref.watch(transactionAllocationProvider(transaction.id)).valueOrNull;
    final lines = ref.watch(transactionLinesProvider(transaction.id));
    final clock = ref.watch(clockProvider);

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;
    final methodId = transaction.paymentMethodId;
    final frozen = transaction.frozenConversion;

    // `CustomScrollView`, not `ListView(children: [...])`. The lines list is fed by a repository
    // stream and U13 admits no row-count exemption — an itemised grocery receipt runs to dozens of
    // rows, so it is a `SliverList.builder` and the fixed sections around it are adapters.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: AlayaCard(
            tier: 2,
            padding: const EdgeInsets.all(AlayaSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AmountText(
                  transaction.signedAmount,
                  kind: transaction.kind,
                  size: AmountSize.large,
                  decimalDigits: digits,
                ),
                if (frozen != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  AmountText(frozen, size: AmountSize.small, showSign: false, muted: true),
                ],
                const SizedBox(height: AlayaSpacing.xs),
                DateText.relative(transaction.dateKey, clock: clock),
                if (transaction.needsReview ||
                    (allocation?.hasMismatch ?? false) ||
                    frozen != null) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Wrap(
                    spacing: AlayaSpacing.xs,
                    runSpacing: AlayaSpacing.xs,
                    children: [
                      if (transaction.needsReview)
                        StatusChip(label: strings.statusNeedsReview, tone: StatusTone.info),
                      if (allocation != null && allocation.hasMismatch)
                        StatusChip(
                          label: strings.statusUnallocated,
                          tone: StatusTone.warning,
                          trailing: AmountText(
                            allocation.unallocated.abs(),
                            size: AmountSize.small,
                            showSign: false,
                            decimalDigits: digits,
                          ),
                        ),
                      if (frozen != null)
                        StatusChip(label: strings.statusApproximate),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
          ),
        SliverList.list(
          children: [
        SectionHeader(label: strings.detailSectionDetails),
        KeyValueRow(label: strings.labelKind, value: TransactionRow.kindLabel(strings, transaction.kind)),
        KeyValueRow(
          label: strings.labelSubtype,
          value: TransactionRow.subtypeLabel(strings, transaction.subtype),
        ),
        KeyValueRow(
          label: strings.labelDate,
          valueWidget: DateText(transaction.dateKey, style: DateTextStyle.full),
        ),
        if (transaction.kind == TransactionKind.transfer) ...[
          KeyValueRow(label: strings.labelFrom, value: from == null ? null : accounts[from]?.name),
          KeyValueRow(label: strings.labelTo, value: to == null ? null : accounts[to]?.name),
        ] else
          KeyValueRow(
            label: strings.labelAccount,
            value: accounts[from ?? to ?? '']?.name,
          ),
        KeyValueRow(
          label: strings.labelPaymentMethod,
          value: methodId == null ? null : methods[methodId]?.name,
        ),
        KeyValueRow(
          label: strings.labelPayee,
          value: payeeId == null ? null : payees[payeeId]?.name,
        ),
        KeyValueRow(label: strings.labelNote, value: transaction.note),
        if (frozen != null)
          KeyValueRow(
            label: strings.actionFreezeConversion,
            value: strings.frozenConversionNote(
              transaction.frozenConversionDateKey?.toIso() ?? '',
              transaction.frozenConversionRateRaw ?? '',
            ),
          ),
        if (tags.isNotEmpty) ...[
          SectionHeader(label: strings.labelTags),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xs,
              children: [for (final tag in tags) TagChip(tag: tag)],
            ),
          ),
        ],
        SectionHeader(label: strings.detailSectionLines),
          ],
        ),
        lines.when(
          loading: () => SliverToBoxAdapter(
            child: AlayaListSkeleton(label: strings.loadingLabel, rows: 2),
          ),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              title: strings.errorTitleGeneric,
              body: strings.errorBodyGeneric,
            ),
          ),
          data: (rows) => rows.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlayaSpacing.screenEdge,
                      vertical: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.emptyBodyNoResults,
                      style: AlayaTypography.caption.copyWith(color: semantic.muted),
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      _LineRow(line: rows[index], decimalDigits: digits),
                ),
        ),
        SliverList.list(
          children: [
        const SizedBox(height: AlayaSpacing.xxl),
        if (frozen == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
            child: OutlinedButton(
              onPressed: onFreeze,
              child: Text(strings.actionFreezeConversion),
            ),
          ),
        const SizedBox(height: AlayaSpacing.sm),
        // Destructive last, quiet, and never a filled button: a red button at the top of a detail
        // screen is a mis-tap waiting to happen.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.screenEdge),
          child: TextButton(
            onPressed: onDelete,
            style: TextButton.styleFrom(foregroundColor: semantic.danger),
            child: Text(strings.actionDeleteTransaction),
          ),
        ),
        const SizedBox(height: AlayaSpacing.xxxl),
          ],
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.decimalDigits});

  final TransactionLine line;
  final int decimalDigits;

  /// Where this line's artefact lives, or null when it created nothing.
  ///
  /// Surfaces `transaction_lines.created*Id` (ARCH_5 §7.2): a purchase that produced a television
  /// or two kilos of potatoes should say so, and let the user walk to it.
  String? _artefactRoute() {
    final itemId = line.itemId;
    if (line.createdBatchId != null && itemId != null) return Routes.itemDetail(itemId);
    final assetId = line.createdAssetId;
    if (assetId != null) return Routes.assetDetail(assetId);
    final templateId = line.createdRecurringTemplateId;
    if (templateId != null) return Routes.recurringDetail(templateId);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final route = _artefactRoute();
    final quantity = line.quantity;
    final amount = line.lineAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description,
                  style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
                ),
                if (quantity != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  QtyText(quantity, muted: true),
                ],
                if (route != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  InkWell(
                    onTap: () => context.push(route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xxs),
                      child: Text(
                        strings.lineCreatedLink(line.description),
                        style: AlayaTypography.caption.copyWith(color: semantic.transfer),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: AlayaSpacing.sm),
            AmountText(
              amount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ],
      ),
    );
  }
}
```


### `lib/features/expense/state/transaction_editor_state.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// Everything the transaction editor is holding (ARCH_5 §3 archetype B).
///
/// **The currency is here and has no setter.** Law L9 makes `originalCurrencyCode` immutable once
/// saved: changing it would reinterpret the stored minor units against a different precision and
/// symbol, silently and unrecoverably. The amount *is* editable — forbidding that would make a
/// mistyped figure permanent with delete-and-recreate as the only remedy, which loses the batch and
/// asset links the fan-out created (ARCH_4 §5.1 item 18).
class TransactionEditorState {
  /// Creates the editor's state.
  const TransactionEditorState({
    required this.currencyCode,
    required this.dateKey,
    this.id,
    this.kind = TransactionKind.withdrawal,
    this.subtype = TransactionSubtype.otherOut,
    this.amount,
    this.fromAccountId,
    this.toAccountId,
    this.paymentMethodId,
    this.payeeId,
    this.note,
    this.tagIds = const <String>{},
    this.lines = const <TransactionLine>[],
    this.warrantyStart,
    this.warrantyEnd,
    this.alsoAddToInventory = false,
    this.toOwnAccount = true,
    this.needsReview = false,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.fanOutError,
    this.saveError,
    this.wantsTemplate = false,
    this.recurringOccurrenceId,
    this.accountMissing = false,
    this.createdAssetId,
    this.sourceEntryIds = const <String>[],
  });

  /// The transaction being edited, or null when this is a new one.
  final String? id;

  /// The flow type. Drives which accounts the shape requires (ARCH_2 §4.1).
  final TransactionKind kind;

  /// The structural subtype. Decides which sub-form is visible.
  final TransactionSubtype subtype;

  /// The amount. The one required field.
  final Money? amount;

  /// The currency, fixed for the life of the record (Law L9).
  final String currencyCode;

  /// The civil date the money moved.
  final DateKey dateKey;

  /// Where the money came from.
  final String? fromAccountId;

  /// Where the money went.
  final String? toAccountId;

  /// The rail it travelled on.
  final String? paymentMethodId;

  /// The counterparty.
  final String? payeeId;

  /// A free note, searchable through FTS.
  final String? note;

  /// The tags applied.
  final Set<String> tagIds;

  /// The lines itemising this transaction.
  final List<TransactionLine> lines;

  /// Warranty start for the asset an electronics line will create.
  final DateKey? warrantyStart;

  /// Warranty end for the asset an electronics line will create.
  final DateKey? warrantyEnd;

  /// Whether an electronics purchase should also produce an inventory batch.
  ///
  /// Off by default: a television is an Asset, not consumable stock, and pushing it to both is
  /// anomaly A12 — neither module then owns the truth.
  final bool alsoAddToInventory;

  /// For the transfer form: whether the money is going to the user's own account.
  ///
  /// True means `kind = transfer` and both accounts are the user's. False means a real withdrawal
  /// with `subtype = transferOut` and a payee — the distinction anomaly A02 exists for, because
  /// treating a self-transfer as a withdrawal destroys net worth.
  final bool toOwnAccount;

  /// Whether the record is still flagged as needing details.
  final bool needsReview;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Why the last save wrote the transaction but could not create the stock or assets its lines
  /// asked for, or null when it created them all.
  final String? fanOutError;

  /// Why the last save was refused outright, or null when it committed.
  ///
  /// The repository's own message. A withdrawal with no account and a line that will not validate
  /// fail for entirely different reasons, and reporting both as "something went wrong" is why neither
  /// was diagnosable from the screen.
  final String? saveError;

  /// Whether a line asked to become a recurring template, so the editor hands the user to the builder
  /// instead of dropping the request on the floor.
  final bool wantsTemplate;

  /// The recurring occurrence this payment settles, or null for an ordinary bill.
  ///
  /// **When set, saving goes through `payOccurrence` instead of `create`.** That call writes the
  /// transaction *and* settles the occurrence together, so there is exactly one write and exactly one
  /// record — an editor that created its own transaction as well would produce two for one payment.
  final String? recurringOccurrenceId;

  /// The asset a line just created, so the editor can hand the user to it.
  ///
  /// **The fan-out was already creating it.** A line marked for assets produces an `Asset` named after
  /// the description, typed `other`, with no warranty — because a receipt line carries none of that.
  /// Nothing then said so, so a television bought as an expense appeared under "Other" with no cover
  /// dates and looked like the feature had not worked. The id travels out and the editor opens on it.
  final String? createdAssetId;

  /// Whether a bill payment could not resolve an account and needs one chosen.
  ///
  /// A field-level error rather than a snack: the choice is made in the form, so the message belongs
  /// beside it (§5.5). It is only ever set when the template, the app default and a sole account all
  /// failed to answer.
  final bool accountMissing;

  /// Shopping entries this transaction fulfils, carried in from a draft and marked purchased on save.
  final List<String> sourceEntryIds;

  /// Whether this is editing an existing record rather than creating one.
  bool get isEditing => id != null;

  /// The subtypes offered for the current [kind].
  List<TransactionSubtype> get availableSubtypes => subtypesFor(kind);

  /// The subtypes a given [kind] may take.
  ///
  /// **Static, and taking the kind explicitly, because callers need to ask about a kind the state
  /// does not have yet.** `setKind` must decide whether the current subtype survives the switch, and
  /// an instance getter can only answer for the kind already applied — which silently answers the
  /// wrong question and leaves the record in a shape the subtype picker cannot render. That defect
  /// showed up as a red screen the moment the user chose Income.
  ///
  /// A deposit cannot be a grocery purchase, and offering the full list would let a user save a
  /// shape the schema's CHECK constraints reject at write time rather than at choose time.
  static List<TransactionSubtype> subtypesFor(TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => const [
            TransactionSubtype.salaryIn,
            TransactionSubtype.otherIn,
          ],
        TransactionKind.transfer => const [TransactionSubtype.transferSelf],
        TransactionKind.withdrawal => const [
            TransactionSubtype.grocery,
            TransactionSubtype.household,
            TransactionSubtype.electronics,
            TransactionSubtype.bill,
            TransactionSubtype.transferOut,
            TransactionSubtype.otherOut,
          ],
        TransactionKind.adjustmentIncrease => const [TransactionSubtype.otherIn],
        TransactionKind.adjustmentDecrease => const [TransactionSubtype.otherOut],
      };

  /// The sum of the lines, or null when there are none.
  Money? get lineTotal {
    if (lines.isEmpty) return null;
    var total = Money.zero(currencyCode);
    for (final line in lines) {
      final lineAmount = line.lineAmount;
      if (lineAmount != null) total += lineAmount;
    }
    return total;
  }

  /// The difference between the transaction amount and its lines.
  ///
  /// Surfaced as an "unallocated" chip and **never auto-balanced**: the transaction amount is the
  /// source of truth and the lines are optional detail, so forcing them equal would silently invent
  /// a line the user did not buy (anomaly A11).
  Money? get unallocated {
    final total = lineTotal;
    final value = amount;
    if (total == null || value == null) return null;
    final difference = value - total;
    return difference.isZero ? null : difference;
  }

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  TransactionEditorState copyWith({
    String? id,
    TransactionKind? kind,
    TransactionSubtype? subtype,
    Money? amount,
    bool clearAmount = false,
    DateKey? dateKey,
    String? fromAccountId,
    bool clearFromAccount = false,
    String? toAccountId,
    bool clearToAccount = false,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
    String? payeeId,
    bool clearPayee = false,
    String? note,
    Set<String>? tagIds,
    List<TransactionLine>? lines,
    DateKey? warrantyStart,
    DateKey? warrantyEnd,
    bool? alsoAddToInventory,
    bool? toOwnAccount,
    bool? needsReview,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
    bool? dirty,
    String? fanOutError,
    String? saveError,
    bool? wantsTemplate,
    String? recurringOccurrenceId,
    bool? accountMissing,
    String? createdAssetId,
    bool clearOccurrence = false,
    bool clearErrors = false,
    List<String>? sourceEntryIds,
  }) =>
      TransactionEditorState(
        id: id ?? this.id,
        kind: kind ?? this.kind,
        subtype: subtype ?? this.subtype,
        amount: clearAmount ? null : (amount ?? this.amount),
        currencyCode: currencyCode,
        dateKey: dateKey ?? this.dateKey,
        fromAccountId: clearFromAccount ? null : (fromAccountId ?? this.fromAccountId),
        toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
        paymentMethodId:
            clearPaymentMethod ? null : (paymentMethodId ?? this.paymentMethodId),
        payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
        note: note ?? this.note,
        tagIds: tagIds ?? this.tagIds,
        lines: lines ?? this.lines,
        warrantyStart: warrantyStart ?? this.warrantyStart,
        warrantyEnd: warrantyEnd ?? this.warrantyEnd,
        alsoAddToInventory: alsoAddToInventory ?? this.alsoAddToInventory,
        toOwnAccount: toOwnAccount ?? this.toOwnAccount,
        needsReview: needsReview ?? this.needsReview,
        submitting: submitting ?? this.submitting,
        amountMissing: amountMissing ?? this.amountMissing,
        shakeTrigger: shakeTrigger ?? this.shakeTrigger,
        dirty: dirty ?? true,
        // **Preserved unless explicitly cleared.** These were written as `fanOutError: fanOutError`,
        // so every later `copyWith` that did not mention them — including the `submitting: false` in
        // `save`'s `finally` — wiped the reason microseconds before the screen read it. Two separate
        // attempts to surface a real failure produced "something went wrong" because of this line.
        fanOutError: clearErrors ? null : (fanOutError ?? this.fanOutError),
        saveError: clearErrors ? null : (saveError ?? this.saveError),
        wantsTemplate: wantsTemplate ?? this.wantsTemplate,
        recurringOccurrenceId: clearOccurrence
            ? null
            : (recurringOccurrenceId ?? this.recurringOccurrenceId),
        accountMissing: accountMissing ?? this.accountMissing,
        createdAssetId: createdAssetId ?? this.createdAssetId,
        sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
      );

  /// Builds the entity this state describes.
  ///
  /// [occurredAtUtc] comes from the caller's clock rather than `DateTime.now()`, so a save is
  /// reproducible in a test.
  Transaction toTransaction({required String newId, required DateTime occurredAtUtc}) =>
      Transaction(
        id: id ?? newId,
        kind: kind,
        subtype: subtype,
        occurredAtUtc: occurredAtUtc,
        dateKey: dateKey,
        originalAmount: amount ?? Money.zero(currencyCode),
        needsReview: needsReview,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        paymentMethodId: paymentMethodId,
        payeeId: payeeId,
        note: note,
      );

  /// Loads an existing transaction into an editor state.
  static TransactionEditorState fromTransaction(
    Transaction transaction, {
    required List<TransactionLine> lines,
    required Set<String> tagIds,
  }) =>
      TransactionEditorState(
        id: transaction.id,
        kind: transaction.kind,
        subtype: transaction.subtype,
        amount: transaction.originalAmount,
        currencyCode: transaction.originalAmount.currencyCode,
        dateKey: transaction.dateKey,
        fromAccountId: transaction.fromAccountId,
        toAccountId: transaction.toAccountId,
        paymentMethodId: transaction.paymentMethodId,
        payeeId: transaction.payeeId,
        note: transaction.note,
        tagIds: tagIds,
        lines: lines,
        needsReview: transaction.needsReview,
        toOwnAccount: transaction.kind == TransactionKind.transfer,
      );
}
```

### `lib/features/expense/providers/transaction_editor_providers.dart`

```dart
/// View-model state for the transaction editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';

/// Raised when a transaction genuinely is not there, as opposed to failing to load.
class TransactionNotFound implements Exception {
  /// Creates the marker.
  const TransactionNotFound(this.id);

  /// The transaction that is not there.
  final String id;

  @override
  String toString() => 'Transaction $id not found.';
}

/// The editor for one transaction, or for a new one when the argument is null.
///
/// The family argument arrives as a `build` parameter against `AutoDisposeFamilyNotifier`, which is
/// the shape this project's Riverpod actually resolves to. Riverpod 3.0's published guide describes
/// a fused `Notifier` taking the argument in its constructor; that does not compile here, and
/// checking the changelog instead of the analyzer is how Phase 6A got it wrong once already
/// (ARCH_1 §7.3, ARCH_4 R22).
final transactionEditorProvider = NotifierProvider.autoDispose
    .family<TransactionEditorNotifier, AsyncValue<TransactionEditorState>, String?>(
  TransactionEditorNotifier.new,
);

/// Loads, edits and saves one transaction.
class TransactionEditorNotifier
    extends AutoDisposeFamilyNotifier<AsyncValue<TransactionEditorState>, String?> {
  @override
  AsyncValue<TransactionEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final code = await settings.readHomeCurrencyCode() ?? 'INR';
      if (id == null) {
        // A draft another module prepared, if one is waiting. `take()` clears it, so a draft is
        // applied exactly once and a stale one cannot ambush the next blank editor.
        final draft = ref.read(transactionDraftProvider.notifier).take();
        state = AsyncValue.data(
          TransactionEditorState(
            currencyCode: code,
            dateKey: ref.read(clockProvider).today(),
            kind: draft?.kind ?? TransactionKind.withdrawal,
            subtype: draft?.subtype ?? TransactionSubtype.otherOut,
            lines: draft?.lines ?? const [],
            note: draft?.note,
            sourceEntryIds: draft?.sourceEntryIds ?? const [],
          ),
        );
        return;
      }
      final repository = ref.read(transactionRepositoryProvider);
      final transaction = await repository.byId(id);
      if (transaction == null) {
        state = AsyncValue.error(TransactionNotFound(id), StackTrace.current);
        return;
      }
      // `_firstOrEmpty`, not `.first`. `watchLines` returns without emitting when it cannot resolve
      // the parent's currency, and `.first` on a stream that closes empty throws `StateError: No
      // element` — which the editor then reported as "this may have been deleted".
      final lines = await _firstOrEmpty(repository.watchLines(id));
      final tags = await _firstOrEmpty(ref.read(tagRepositoryProvider).watchForTransaction(id));
      state = AsyncValue.data(
        TransactionEditorState.fromTransaction(
          transaction,
          lines: lines,
          tagIds: {for (final tag in tags) tag.id},
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TransactionEditorState Function(TransactionEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Switches the flow type, keeping every field the new shape still has.
  ///
  /// **Nothing is cleared that the new shape can hold.** Changing withdrawal to deposit must not
  /// wipe the amount the user has already typed; only the accounts move, because a deposit needs a
  /// destination and no source and a withdrawal is the mirror of that (ARCH_2 §4.1).
  void setKind(TransactionKind kind) => _edit((s) {
        // Against the **new** kind, not the state's current one: `s` is the pre-change state, so
        // `s.availableSubtypes` would answer for the kind being replaced.
        final subtype = TransactionEditorState.subtypesFor(kind).contains(s.subtype)
            ? s.subtype
            : _defaultSubtypeFor(kind);
        return s.copyWith(
          kind: kind,
          subtype: subtype,
          fromAccountId: kind == TransactionKind.deposit ? null : s.fromAccountId ?? s.toAccountId,
          clearFromAccount: kind == TransactionKind.deposit,
          toAccountId: kind == TransactionKind.deposit ? s.toAccountId ?? s.fromAccountId : null,
          clearToAccount: kind == TransactionKind.withdrawal,
        );
      });

  /// Switches the visible sub-form.
  void setSubtype(TransactionSubtype subtype) => _edit((s) => s.copyWith(subtype: subtype));

  /// Records the parsed amount, in the record's own currency.
  ///
  /// There is no currency setter anywhere on this notifier, and that is Law L9 rather than an
  /// oversight.
  void setAmount(Money? amount) => _edit(
        (s) => amount == null
            ? s.copyWith(clearAmount: true)
            : s.copyWith(amount: amount, amountMissing: false),
      );

  /// Sets the civil date the money moved.
  void setDate(DateKey date) => _edit((s) => s.copyWith(dateKey: date));

  /// Sets the source account.
  void setFromAccount(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearFromAccount: true) : s.copyWith(fromAccountId: id),
      );

  /// Sets the destination account.
  void setToAccount(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearToAccount: true) : s.copyWith(toAccountId: id),
      );

  /// Sets the rail the money travelled on.
  void setPaymentMethod(String? id) => _edit(
        (s) => id == null ? s.copyWith(clearPaymentMethod: true) : s.copyWith(paymentMethodId: id),
      );

  /// Sets the counterparty.
  void setPayee(String? id) =>
      _edit((s) => id == null ? s.copyWith(clearPayee: true) : s.copyWith(payeeId: id));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Sets which recurring occurrence this payment settles, or clears the link.
  ///
  /// Selecting one also adopts the template's usual amount, because that is the figure the user is
  /// about to confirm or correct — leaving the field blank would make the common case extra typing.
  void setRecurringOccurrence({
    String? occurrenceId,
    Money? defaultAmount,
    String? accountId,
  }) =>
      _edit(
        (s) => occurrenceId == null
            ? s.copyWith(clearOccurrence: true)
            : s.copyWith(
                recurringOccurrenceId: occurrenceId,
                amount: defaultAmount ?? s.amount,
                // The account comes across too, so the common path is one tap and not two. It is
                // whatever the template, the app default or a sole account already says.
                fromAccountId: accountId ?? s.fromAccountId,
                amountMissing: false,
                accountMissing: false,
              ),
      );

  /// Applies or removes a tag.
  void toggleTag(String tagId) => _edit((s) {
        final next = {...s.tagIds};
        if (next.contains(tagId)) {
          next.remove(tagId);
        } else {
          next.add(tagId);
        }
        return s.copyWith(tagIds: next);
      });

  /// Chooses between a transfer between the user's own accounts and a withdrawal to someone else.
  ///
  /// The whole point of anomaly A02: moving money between your own accounts must not reduce net
  /// worth, so it is `kind = transfer` with both accounts. Sending it to someone else is a real
  /// withdrawal with `subtype = transferOut` and a payee.
  void setTransferTarget({required bool toOwnAccount}) => _edit(
        (s) => s.copyWith(
          toOwnAccount: toOwnAccount,
          kind: toOwnAccount ? TransactionKind.transfer : TransactionKind.withdrawal,
          subtype: toOwnAccount
              ? TransactionSubtype.transferSelf
              : TransactionSubtype.transferOut,
          clearToAccount: !toOwnAccount,
          clearPayee: toOwnAccount,
        ),
      );

  /// Sets the warranty window for the asset an electronics line will create.
  void setWarranty({DateKey? start, DateKey? end}) =>
      _edit((s) => s.copyWith(warrantyStart: start, warrantyEnd: end));

  /// Opts an electronics purchase into also producing an inventory batch.
  void setAlsoAddToInventory({required bool value}) =>
      _edit((s) => s.copyWith(alsoAddToInventory: value));

  /// Adds or replaces a line, keyed on its id.
  void upsertLine(TransactionLine line) => _edit((s) {
        final next = [...s.lines];
        final index = next.indexWhere((existing) => existing.id == line.id);
        if (index >= 0) {
          next[index] = line;
        } else {
          next.add(line.copyWith(lineNo: next.length + 1));
        }
        return s.copyWith(lines: next);
      });

  /// Removes a line.
  void removeLine(String lineId) => _edit((s) {
        final next = [...s.lines.where((line) => line.id != lineId)];
        return s.copyWith(
          lines: [
            for (var i = 0; i < next.length; i++) next[i].copyWith(lineNo: i + 1),
          ],
        );
      });

  /// Creates a payee inline and selects it, so the editor never sends the user to Settings.
  ///
  /// Returns whether it worked. **The result is reported rather than dropped**: a save that fails
  /// silently leaves the user typing the same name again, wondering why it never appears, with
  /// nothing on screen to tell them the write was refused.
  Future<bool> createPayee(String name) async {
    final normalizer = ref.read(normalizerProvider);
    final payee = Payee(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: normalizer.normalize(name),
      kind: PayeeKind.merchant,
    );
    final saved = await ref.read(payeeRepositoryProvider).save(payee);
    final value = saved.valueOrNull;
    if (value == null) return false;
    setPayee(value.id);
    return true;
  }

  /// Saves the transaction and everything its lines produce.
  ///
  /// **Idempotent rather than atomic, and that is a recorded deviation from Law L14.** Atomicity is
  /// unavailable from here: three repositories are written and no repository may own another's
  /// transaction (ARCH_4 §5.1 item 17). What is achievable is that re-running is a no-op —
  /// `PurchaseFanOutService.planAll` skips any line that already carries a `created*Id`, and the
  /// ids are written back to the lines before this returns. Without that write-back, re-saving an
  /// edited transaction would create a second television every time.
  ///
  /// Returns the transaction's id on success, or null when the form was rejected or a write failed.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.amount == null) {
      _edit((s) => s.copyWith(amountMissing: true, shakeTrigger: s.shakeTrigger + 1));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearErrors: true));
    // **`finally`, not a clear on each early return.** A `SqliteException` thrown anywhere below used
    // to propagate out of `save`, leaving `submitting: true` forever — the footer button stayed in its
    // progress state and the only way out of the screen was to kill the app.
    try {
      return await _write(current);
    } on Object catch (error, stack) {
      _edit((s) => s.copyWith(saveError: error.toString()));
      ref.read(loggerProvider).log(
        'Transaction save failed',
        level: LogLevel.error,
        tag: 'expense.editor',
        error: error,
        stackTrace: stack,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Commits [current], and is safe to call again after a failure partway through.
  ///
  /// **Five writes, no outer transaction — by design, and this is what makes that safe.** The
  /// sequence spans three repositories, and ARCH_4 §5.1 item 17 already ruled that none of them may
  /// own another's transaction; idempotency is the sanctioned answer instead. `planAll` supplies half
  /// of it by skipping any line that already carries a `created*Id`. This supplies the other half.
  ///
  /// Once the transaction row exists, its id is written back into the editor's state. A retry then
  /// sees `isEditing` and takes the update path, so a save that got as far as `create` and then threw
  /// is resumed rather than duplicated. Without this, `current.id` stayed null and every retry minted
  /// a second transaction — which is how a failed save left orphans in the ledger.
  Future<String?> _write(TransactionEditorState current) async {
    final uids = ref.read(uidGeneratorProvider);
    final clock = ref.read(clockProvider);
    final repository = ref.read(transactionRepositoryProvider);

    final amount = current.amount!;
    final id = current.id ?? uids.generate();
    // **Every line gets a fresh id on every attempt, create or edit.**
    //
    // Two reasons, and the second is the one that bit. `replaceLines` soft-deletes the existing rows
    // rather than removing them (Law L6), so an edit reusing an id collides with the row still
    // physically there. And a line id held in state — one a shopping draft minted, or one a previous
    // failed attempt already inserted — is reused verbatim by the next attempt, so any save that got
    // as far as writing lines makes every retry fail with `UNIQUE constraint failed:
    // transaction_lines.id` and mask whatever actually went wrong the first time.
    //
    // A line id has no meaning outside its row: nothing references it but the batch it produced, and
    // that link is written after the insert. So it is assigned here, at write time, never carried in.
    final lines = [
      for (final line in current.lines)
        line.copyWith(id: uids.generate(), transactionId: id),
    ];
    final transaction =
        current.toTransaction(newId: id, occurredAtUtc: clock.now().toUtc());

    // **A bill settling a recurring occurrence has exactly one write, and it is not this one.**
    // `payOccurrence` creates the transaction *and* marks the occurrence paid in the same call, so
    // going through `create` as well produced two transactions for one payment — the amount typed
    // here and the amount confirmed in a sheet both landed. The editor's amount is now the only
    // figure, and this is the only save.
    final settling = current.recurringOccurrenceId;
    if (settling != null && !current.isEditing) {
      // Resolved rather than demanded: the template's default, then the app default, then a sole
      // account. Only a genuine ambiguity — several accounts and no default anywhere — reaches the
      // rejection, and `payOccurrence` cannot take null because a withdrawal with no source account
      // makes every balance and every insight quietly wrong.
      final account = current.fromAccountId ??
          current.toAccountId ??
          ref.read(resolvedBillAccountProvider(null));
      if (account == null) {
        _edit((s) => s.copyWith(accountMissing: true));
        return null;
      }
      final paid = await ref.read(recurringRepositoryProvider).payOccurrence(
            occurrenceId: settling,
            amount: amount,
            paidOn: current.dateKey,
            accountId: account,
            paymentMethodId: current.paymentMethodId,
          );
      final failure = paid.failureOrNull;
      if (failure != null) {
        _edit((s) => s.copyWith(saveError: failure.message));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false, clearOccurrence: true));
      return paid.valueOrNull?.id;
    }

    final written = current.isEditing
        ? await repository.update(transaction)
        : await repository.create(
            transaction: transaction,
            lines: lines,
            tagIds: current.tagIds.toList(),
          );
    if (written.isFailure) {
      // The repository says what it refused — an account a withdrawal needs, a currency that is not
      // enabled, a line that will not validate. Discarding that is what made a save unfixable.
      _edit((s) => s.copyWith(saveError: written.failureOrNull?.message));
      return null;
    }

    // The row is committed. From here on this is an edit, whatever happens next.
    if (!current.isEditing) {
      _edit((s) => s.copyWith(id: id));
    }

    if (current.isEditing) {
      final replaced = await repository.replaceLines(transactionId: id, lines: lines);
      if (replaced.isFailure) {
        _edit((s) => s.copyWith(saveError: replaced.failureOrNull?.message));
        return null;
      }
    }

    final fanned = await _fanOut(transaction: transaction, lines: lines, state: current);
    // One column per line, through the write built for it — never `replaceLines`, which would insert
    // rows whose ids already exist.
    for (final line in fanned.lines) {
      if (line.createdBatchId == null &&
          line.createdAssetId == null &&
          line.createdRecurringTemplateId == null) {
        continue;
      }
      await repository.recordCreatedArtefact(
        lineId: line.id,
        createdBatchId: line.createdBatchId,
        createdAssetId: line.createdAssetId,
        createdRecurringTemplateId: line.createdRecurringTemplateId,
      );
    }
    // The loop closes here. `markPurchased` exists for exactly this and takes the ids the draft
    // carried across, so the shopping entries stop being outstanding the moment the expense that
    // fulfils them is committed (anomaly A25). Guarded, so an ordinary expense never touches it.
    if (current.sourceEntryIds.isNotEmpty) {
      await ref.read(shoppingRepositoryProvider).markPurchased(
            entryIds: current.sourceEntryIds,
            transactionId: id,
          );
    }
    // `clearErrors` first so a previous attempt's message cannot outlive it, then the new one.
    _edit((s) => s.copyWith(dirty: false, clearErrors: true));
    _edit(
      (s) => s.copyWith(
        fanOutError: fanned.error,
        wantsTemplate: fanned.wantsTemplate,
        createdAssetId: fanned.createdAsset,
      ),
    );
    return id;
  }

  /// Creates the batches, assets and template names the lines call for, and writes their ids back.
  ///
  /// **Reports whether anything was refused.** `_planBatch` rejects a line with no `itemId` or no
  /// quantity, and an earlier version dropped that failure on the floor — the transaction saved, the
  /// snack said so, and the stock never appeared in the inventory with nothing on screen to explain
  /// why. A write that half-succeeds must say which half (U9).
  Future<({List<TransactionLine> lines, String? error, bool wantsTemplate, String? createdAsset})>
      _fanOut({
    required Transaction transaction,
    required List<TransactionLine> lines,
    required TransactionEditorState state,
  }) async {
    if (lines.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    final uids = ref.read(uidGeneratorProvider);
    final planned = ref.read(purchaseFanOutServiceProvider).planAll(
          lines: lines,
          transaction: transaction,
          newArtefactIds: [for (var i = 0; i < lines.length; i++) uids.generate()],
        );
    final plans = planned.valueOrNull;
    if (plans == null) {
      // Every line that asked for an artefact was refused — almost always a line marked for
      // inventory with no catalogued item behind it.
      final wanted = lines.any(
        (line) => line.destination != TransactionLineDestination.none,
      );
      return (
        lines: const <TransactionLine>[],
        error: wanted ? planned.failureOrNull?.message : null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    if (plans.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }

    String? refused;
    var requestedTemplate = false;
    String? createdAsset;
    final updated = [...lines];
    for (final plan in plans) {
      final index = updated.indexWhere((line) => line.id == plan.lineId);
      if (index < 0) continue;
      switch (plan.target) {
        case FanOutTarget.batch:
          final batch = plan.batch;
          if (batch == null) continue;
          final saved = await ref.read(batchRepositoryProvider).create(batch);
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdBatchId: value.id);
          }
        case FanOutTarget.asset:
          final asset = plan.asset;
          if (asset == null) continue;
          // The warranty window lives on the form rather than on the line, because a receipt line
          // has no column for it — so it is applied to the planned asset here.
          final saved = await ref.read(assetRepositoryProvider).save(
                asset.copyWith(
                  warrantyStartDateKey: state.warrantyStart,
                  warrantyEndDateKey: state.warrantyEnd,
                ),
              );
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdAssetId: value.id);
            // Carried out so the editor can open the asset it just made. It is typed `other` with no
            // warranty, because a receipt line has no way to say otherwise — which is exactly why the
            // user needs to land on it rather than go hunting.
            createdAsset ??= value.id;
          }
        case FanOutTarget.recurringTemplate:
          // A schedule needs an interval and an anchor a receipt line does not contain, so the name
          // and amount are handed to Phase 6D's builder and the user supplies the rest. Inventing a
          // monthly-on-the-1st default would create an obligation nobody agreed to.
          //
          // **This branch used to `break` and do nothing at all** — the control was tickable, saved
          // cleanly, and produced no template and no message.
          ref.read(templateDraftProvider.notifier).offer(
                TemplateDraft(
                  name: plan.recurringTemplateName ?? updated[index].description,
                  amount: updated[index].lineAmount ?? state.amount,
                ),
              );
          requestedTemplate = true;
        case FanOutTarget.none:
          break;
      }
    }
    return (
      lines: updated,
      error: refused,
      wantsTemplate: requestedTemplate,
      createdAsset: createdAsset,
    );
  }

  static TransactionSubtype _defaultSubtypeFor(TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => TransactionSubtype.otherIn,
        TransactionKind.withdrawal => TransactionSubtype.otherOut,
        TransactionKind.transfer => TransactionSubtype.transferSelf,
        TransactionKind.adjustmentIncrease => TransactionSubtype.otherIn,
        TransactionKind.adjustmentDecrease => TransactionSubtype.otherOut,
      };
}

/// Payment methods offered in the editor.
final editorPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Payees offered in the editor.
final editorPayeesProvider = StreamProvider<List<Payee>>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll(),
);

/// Tags offered for a given flow direction.
final editorTagsProvider = StreamProvider.autoDispose.family<List<Tag>, TransactionKind>(
  (ref, kind) => ref.watch(tagRepositoryProvider).watchByScope(
        kind == TransactionKind.deposit ? TagScope.deposit : TagScope.withdrawal,
      ),
);

/// The first event of [stream], or an empty list when it closes without emitting one.
Future<List<T>> _firstOrEmpty<T>(Stream<List<T>> stream) async {
  await for (final value in stream) {
    return value;
  }
  return <T>[];
}
```

### `lib/features/expense/presentation/screens/line_items_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything on one receipt, in one place (ARCH_5 §3 archetype D).
///
/// **A page rather than a sheet per line.** Itemising a fifteen-line grocery receipt through
/// `LineItemEditor` alone meant fifteen open-close cycles with no view of what had been entered, no
/// running total, and no way to correct line three without starting over. This keeps the list, the
/// figures and the add action on screen together; the sheet is still what edits one line, reached from
/// here. `LineItemDraft.addAnother` lets the sheet stay open across a whole receipt.
///
/// **It edits the editor's state, and writes nothing.** The lines belong to
/// `transactionEditorProvider`, which stays alive because the editor screen remains mounted beneath
/// this route — so Done simply pops, and nothing is committed until the user saves the transaction.
class LineItemsScreen extends ConsumerWidget {
  /// Shows the lines of [transactionId], or of a new transaction when null.
  const LineItemsScreen({this.transactionId, super.key});

  /// Which transaction's lines to show.
  final String? transactionId;

  Future<void> _addMany(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    int digits,
  ) async {
    final notifier = ref.read(transactionEditorProvider(transactionId).notifier);
    var another = true;
    while (another && context.mounted) {
      final draft = await LineItemEditor.show(
        context,
        currencyCode: state.currencyCode,
        decimalDigits: digits,
        defaultDestination: TransactionLineDestination.none,
      );
      if (draft == null) return;
      notifier.upsertLine(draft.line);
      another = draft.addAnother;
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    TransactionLine line,
    int digits,
  ) async {
    final draft = await LineItemEditor.show(
      context,
      currencyCode: state.currencyCode,
      decimalDigits: digits,
      defaultDestination: line.destination,
      line: line,
    );
    if (draft == null) return;
    ref.read(transactionEditorProvider(transactionId).notifier).upsertLine(draft.line);
  }

  void _remove(BuildContext context, WidgetRef ref, TransactionLine line) {
    final strings = AlayaStrings.of(context);
    ref.read(transactionEditorProvider(transactionId).notifier).removeLine(line.id);
    // No undo offered: nothing has been written, so re-adding the line is the same two taps that
    // created it, and a snack promising undo for an uncommitted edit would be lying (§5.4).
    showResultSnack(context, message: strings.lineRemoved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;

    return Scaffold(
      appBar: AppBar(title: Text(strings.lineItemsTitle)),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionEditorProvider(transactionId)),
        ),
        data: (state) => Column(
          children: [
            _Summary(state: state, decimalDigits: digits),
            Expanded(
              child: state.lines.isEmpty
                  ? EmptyState(
                      title: strings.emptyTitleNoLineItems,
                      body: strings.emptyBodyNoLineItems,
                      icon: Icons.receipt_long_outlined,
                      actionLabel: strings.lineItemsAdd,
                      onAction: () => _addMany(context, ref, state, digits),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                      itemCount: state.lines.length,
                      itemBuilder: (context, index) {
                        final line = state.lines[index];
                        return _LineTile(
                          line: line,
                          decimalDigits: digits,
                          onTap: () => _edit(context, ref, state, line, digits),
                          onRemove: () => _remove(context, ref, line),
                        );
                      },
                    ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(AlayaSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.lines.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _addMany(context, ref, state, digits),
                      icon: const Icon(Icons.add, size: AlayaIconSize.md),
                      label: Text(strings.lineItemsAdd),
                    ),
                  const SizedBox(height: AlayaSpacing.xs),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.actionDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.decimalDigits});

  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final unallocated = state.unallocated;
    final allocated = state.lineTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.lineItemsCount(state.lines.length),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          if (allocated != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AlayaSpacing.xxs,
              children: [
                Text(
                  strings.lineItemsAllocated,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
                AmountText(
                  allocated,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
              ],
            ),
          if (unallocated != null && !unallocated.isZero)
            StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.decimalDigits,
    required this.onTap,
    required this.onRemove,
  });

  final TransactionLine line;
  final int decimalDigits;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final amount = line.lineAmount;
    final quantity = line.quantity;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.description,
                      style: AlayaTypography.body
                          .copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    // Quantity, amount and destination all wrap together: at a doubled text scale a
                    // Row of them would starve the description beside it (Law U21).
                    const SizedBox(height: AlayaSpacing.xxs),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (quantity != null) QtyText(quantity, muted: true),
                        if (amount != null)
                          AmountText(
                            amount,
                            size: AmountSize.small,
                            showSign: false,
                            decimalDigits: decimalDigits,
                          ),
                        if (line.destination == TransactionLineDestination.inventory)
                          StatusChip(
                            label: strings.destinationInventory,
                            icon: Icons.inventory_2_outlined,
                          ),
                        if (line.destination == TransactionLineDestination.asset)
                          StatusChip(
                            label: strings.destinationAsset,
                            icon: Icons.build_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: strings.actionRemove,
                icon: Icon(
                  Icons.close,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/expense/presentation/sheets/line_item_editor.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

/// Items the line editor can attach a quantity to.
final lineEditorItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Units in the category of the currently chosen item.
final lineEditorUnitsProvider =
    StreamProvider.autoDispose.family<List<Unit>, UnitCategory?>(
  (ref, category) => category == null
      ? Stream.value(const <Unit>[])
      : ref.watch(unitRepositoryProvider).watchByCategory(category),
);

/// What [LineItemEditor] hands back: the line, and whether another should open straight away.
class LineItemDraft {
  /// Creates a result.
  const LineItemDraft({required this.line, this.addAnother = false});

  /// The line the user built.
  final TransactionLine line;

  /// Whether to reopen the editor blank once this one is stored.
  ///
  /// A grocery receipt is fifteen lines, and closing the sheet between each one made itemising an
  /// expense feel like fifteen separate tasks. The caller loops while this is true.
  final bool addAnother;
}

/// Edits one line of a transaction (ARCH_5 §3 archetype A).
///
/// **An Item can be created here, and that is what makes the receipt reach the inventory at all.**
/// `PurchaseFanOutService._planBatch` refuses a line without `itemId`, so without an inline create a
/// user on a fresh install itemises a grocery receipt, saves it, and nothing ever appears in the
/// inventory — the batch was never planned. The catalogue is discovered while typing the receipt,
/// exactly as a payee is.
///
/// **Quantity is offered only once an Item is chosen, and that is the schema talking rather than a
/// simplification.** A `Qty` is an integer plus a `UnitCategory`, and the category comes from the
/// Item — it is immutable per Item and cross-category conversion does not exist (Law L8). A free-text
/// line has no category, so a quantity on it would be a number whose meaning nothing records. It is
/// also exactly what the fan-out requires: `_planBatch` refuses a line without a catalogued item,
/// because a batch with a guessed quantity is stock the user never bought.
class LineItemEditor extends ConsumerStatefulWidget {
  /// Edits [line], or creates a new one when it is null.
  const LineItemEditor({
    required this.currencyCode,
    required this.decimalDigits,
    required this.defaultDestination,
    this.line,
    super.key,
  });

  /// The transaction's currency. A line cannot be denominated in another.
  final String currencyCode;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line should default to — inventory for a grocery or household purchase.
  final TransactionLineDestination defaultDestination;

  /// The line being edited, or null for a new one.
  final TransactionLine? line;

  /// Opens the sheet, resolving to the edited line or null.
  static Future<LineItemDraft?> show(
    BuildContext context, {
    required String currencyCode,
    required int decimalDigits,
    required TransactionLineDestination defaultDestination,
    TransactionLine? line,
  }) =>
      AlayaBottomSheet.show<LineItemDraft>(
        context: context,
        builder: (context) => LineItemEditor(
          currencyCode: currencyCode,
          decimalDigits: decimalDigits,
          defaultDestination: defaultDestination,
          line: line,
        ),
      );

  @override
  ConsumerState<LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends ConsumerState<LineItemEditor> {
  late final TextEditingController _description =
      TextEditingController(text: widget.line?.description ?? '');
  late TransactionLineDestination _destination =
      widget.line?.destination ?? widget.defaultDestination;
  late String? _itemId = widget.line?.itemId;
  late Qty? _quantity = widget.line?.quantity;
  /// The unit code the quantity is entered in.
  ///
  /// **Held as a code, seeded from the saved line.** `QtyField` formats its initial text against the
  /// `selectedUnit` it is handed, so a null here fell back to `units.first` — milligram — and a line
  /// saved as `50 kg` reopened as `50000000 mg`. The units list arrives asynchronously, so the code is
  /// what persists and the `Unit` is resolved from it on each build.
  late String? _unitCode = widget.line?.unitCode;
  late Money? _unitPrice = widget.line?.unitPrice;
  late Money? _lineAmount = widget.line?.lineAmount;
  bool _descriptionMissing = false;
  bool _creatingItem = false;
  UnitCategory _newItemCategory = UnitCategory.count;
  bool _createFailed = false;

  Future<void> _createItem() async {
    final name = _description.text.trim();
    if (name.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final item = Item(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: ref.read(normalizerProvider).normalize(name),
      unitCategory: _newItemCategory,
      defaultDisplayUnitCode: _newItemCategory.baseUnitCode,
      itemKind: ItemKind.generic,
      isFavorite: false,
    );
    final saved = await ref.read(itemRepositoryProvider).save(item);
    if (!mounted) return;
    final value = saved.valueOrNull;
    setState(() {
      _createFailed = value == null;
      if (value == null) return;
      _itemId = value.id;
      _creatingItem = false;
      _unitCode = value.defaultDisplayUnitCode;
      _quantity = null;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  void _submit({bool addAnother = false}) {
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final existing = widget.line;
    final line = TransactionLine(
      id: existing?.id ?? ref.read(uidGeneratorProvider).generate(),
      transactionId: existing?.transactionId ?? '',
      lineNo: existing?.lineNo ?? 1,
      description: description,
      destination: _destination,
      itemId: _itemId,
      quantity: _quantity,
      unitCode: _unitCode ?? existing?.unitCode,
      unitPrice: _unitPrice,
      lineAmount: _lineAmount,
      createdBatchId: existing?.createdBatchId,
      createdAssetId: existing?.createdAssetId,
      createdRecurringTemplateId: existing?.createdRecurringTemplateId,
      note: existing?.note,
    );
    Navigator.of(context).pop(LineItemDraft(line: line, addAnother: addAnother));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final items = ref.watch(lineEditorItemsProvider).valueOrNull ?? const <Item>[];
    Item? selectedItem;
    for (final item in items) {
      if (item.id == _itemId) {
        selectedItem = item;
        break;
      }
    }
    final units =
        ref.watch(lineEditorUnitsProvider(selectedItem?.unitCategory)).valueOrNull ??
            const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == _unitCode) selectedUnit = unit;
    }
    // Prefer the item's own display unit over the first in the list: a catalogue entry measured in
    // kilograms should not open in milligrams just because that sorts first.
    if (selectedUnit == null) {
      for (final unit in units) {
        if (unit.code == selectedItem?.defaultDisplayUnitCode) selectedUnit = unit;
      }
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.lineDescription,
          style: AlayaTypography.cardTitle.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.lineDescription,
            errorText: _descriptionMissing ? strings.errorFieldRequired : null,
          ),
          onChanged: (_) {
            if (_descriptionMissing) setState(() => _descriptionMissing = false);
          },
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionLineDestination>(
          key: ValueKey(_destination),
          initialValue: _destination,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelCategory),
          items: [
            for (final destination in TransactionLineDestination.values)
              DropdownMenuItem(
                value: destination,
                child: Text(_destinationLabel(strings, destination)),
              ),
          ],
          onChanged: (value) =>
              value == null
                  ? null
                  : setState(() {
                      _destination = value;
                      // Cleared with the fields: a stale item link on an asset line would reach
                      // `_planBatch` and be refused, for a quantity the user was never shown.
                      if (value != TransactionLineDestination.inventory) {
                        _itemId = null;
                        _quantity = null;
                        _unitCode = null;
                        _creatingItem = false;
                      }
                    }),
        ),
        // **The label alone never said which was which.** "Add to inventory" and "Add to services"
        // are indistinguishable to anyone who has not read the schema, so an iPhone went to inventory,
        // was refused for want of a quantity, and appeared in neither place. The helper names a real
        // example of each: consumed versus kept is the whole distinction.
        Padding(
          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
          child: Text(
            _destinationHelp(strings, _destination),
            style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Only inventory needs an item, a quantity and a unit.** A television has no grams and a
        // recurring line has no stock; offering the fields anyway invited an iPhone to be filed as
        // measured stock, which `_planBatch` then refused for want of a quantity. The whole block is
        // gated on the destination rather than each field being individually pointless.
        if (_destination == TransactionLineDestination.inventory) ...[
          if (_creatingItem)
            _NewItemRow(
              category: _newItemCategory,
              onCategoryChanged: (category) =>
                  setState(() => _newItemCategory = category),
              onCreate: _createItem,
              onCancel: () => setState(() => _creatingItem = false),
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: items.isEmpty
                      ? Text(
                          strings.itemCreateHint,
                          style: AlayaTypography.caption
                              .copyWith(color: context.semantic.muted),
                        )
                      : DropdownButtonFormField<String>(
              // **`selectedItem?.id`, not `_itemId`.** The items arrive from a stream, so on the frame
              // right after an inline create the state already names the new item while the list has
              // not re-emitted it — and a dropdown holding a value none of its items carry throws
              // "There should be exactly one item", which is a red screen. Deriving the value from the
              // list being rendered makes the mismatch unrepresentable.
              key: ValueKey(selectedItem?.id),
              initialValue: selectedItem?.id,
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.labelItem),
              items: [
                for (final item in items)
                  DropdownMenuItem(
                    value: item.id,
                    child: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() {
                // **Picking an item fills the description.** The two are different columns — the
                // description is what the receipt said, `itemId` is what it stocks — but the receipt
                // almost always says the item's name, and making the user retype "onion" after
                // choosing Onion is friction with no purpose. An edit of their own is never
                // overwritten: the fill only happens while the field is empty or still holds the
                // previously-picked item's name.
                final previous = _nameOf(items, _itemId);
                _itemId = value;
                final picked = _nameOf(items, value);
                final typed = _description.text.trim();
                if (picked != null && (typed.isEmpty || typed == previous)) {
                  _description.text = picked;
                  _descriptionMissing = false;
                }
                // The category changed, so any unit and quantity chosen against the old one is now
                // meaningless rather than merely stale — Law L8 has no cross-category conversion.
                _unitCode = null;
                _quantity = null;
              }),
            ),
                ),
                const SizedBox(width: AlayaSpacing.xs),
                TextButton(
                  onPressed: () => setState(() => _creatingItem = true),
                  child: Text(strings.itemCreate),
                ),
              ],
            ),
          if (_createFailed) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(color: context.semantic.danger),
            ),
          ],
          if (selectedItem != null && units.isNotEmpty && selectedUnit != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            QtyField(
              key: ValueKey('${selectedItem.id}:${selectedUnit.code}'),
              category: selectedItem.unitCategory,
              units: units,
              selectedUnit: selectedUnit,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: _quantity,
              onChanged: (quantity) => _quantity = quantity,
              onUnitChanged: (unit) => setState(() => _unitCode = unit.code),
            ),
          ],
        ],
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineUnitPrice,
          initialValue: _unitPrice,
          onChanged: (value) => _unitPrice = value,
        ),
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineAmount,
          initialValue: _lineAmount,
          onChanged: (value) => _lineAmount = value,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(onPressed: _submit, child: Text(strings.actionDone)),
        const SizedBox(height: AlayaSpacing.xs),
        // The bulk path. Itemising a receipt should not mean opening and closing this sheet once per
        // line, so this commits and reopens blank; the caller keeps looping while it is asked to.
        TextButton.icon(
          onPressed: () => _submit(addAnother: true),
          icon: const Icon(Icons.add, size: AlayaIconSize.sm),
          label: Text(strings.lineItemsSaveAndAnother),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }

  static String? _nameOf(List<Item> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  static String _destinationLabel(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) =>
      switch (destination) {
        TransactionLineDestination.none => strings.destinationNone,
        TransactionLineDestination.inventory => strings.destinationInventory,
        TransactionLineDestination.asset => strings.destinationAsset,
        TransactionLineDestination.recurring => strings.destinationRecurring,
      };

  static String _destinationHelp(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) =>
      switch (destination) {
        TransactionLineDestination.none => strings.destinationHelpNone,
        TransactionLineDestination.inventory => strings.destinationHelpInventory,
        TransactionLineDestination.asset => strings.destinationHelpAsset,
        TransactionLineDestination.recurring => strings.destinationHelpRecurring,
      };
}

class _NewItemRow extends StatelessWidget {
  const _NewItemRow({
    required this.category,
    required this.onCategoryChanged,
    required this.onCreate,
    required this.onCancel,
  });

  final UnitCategory category;
  final ValueChanged<UnitCategory> onCategoryChanged;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.itemCreateCategoryPrompt,
          style: AlayaTypography.label.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        SegmentedButton<UnitCategory>(
          segments: [
            for (final option in UnitCategory.values)
              ButtonSegment(
                value: option,
                label: Text(_LineItemEditorState._categoryLabel(strings, option)),
              ),
          ],
          selected: {category},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onCategoryChanged(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Row(
          children: [
            Expanded(
              child: FilledButton(onPressed: onCreate, child: Text(strings.itemCreate)),
            ),
            const SizedBox(width: AlayaSpacing.xs),
            TextButton(onPressed: onCancel, child: Text(strings.actionCancel)),
          ],
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/line_items_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The "what you bought" section, shared by every sub-form that itemises (ARCH_5 §4).
///
/// One widget rather than one per sub-form: grocery, household, electronics and other all itemise
/// identically, and four copies is how one component becomes four that drift (ARCH_4 R25). Only the
/// default destination differs, so that is the parameter.
///
/// **The unallocated chip is never auto-balanced.** The transaction amount is the source of truth
/// and the lines are optional detail; forcing them equal would invent a line the user did not buy
/// (anomaly A11). Note the chip appears only when lines exist — with none at all, "unallocated"
/// equals the whole amount, which is not a mismatch.
class LineItemsSection extends ConsumerWidget {
  /// Creates the section for [state], defaulting new lines to [defaultDestination].
  const LineItemsSection({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    this.defaultDestination = TransactionLineDestination.inventory,
    super.key,
  });

  /// The editor family argument, so the section writes to the right notifier.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line starts as.
  final TransactionLineDestination defaultDestination;

  /// Opens the dedicated items page.
  ///
  /// **A page, not the sheet.** Adding one line at a time through a sheet meant a fifteen-item receipt
  /// was fifteen open-close cycles with no view of what had been entered. The page keeps the list, the
  /// running total and the add action on screen together; the sheet is still what edits a single line,
  /// reached from there.
  void _openItems(BuildContext context) =>
      context.push(Routes.transactionLines(state.id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final unallocated = state.unallocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionWhatYouBought,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        for (final line in state.lines)
          AlayaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.sm,
              vertical: AlayaSpacing.xs,
            ),
            onTap: () async {
              final edited = await LineItemEditor.show(
                context,
                currencyCode: state.currencyCode,
                decimalDigits: decimalDigits,
                defaultDestination: defaultDestination,
                line: line,
              );
              if (edited != null) notifier.upsertLine(edited.line);
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
                if (line.lineAmount != null)
                  AmountText(
                    line.lineAmount!,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                  ),
                IconButton(
                  onPressed: () => notifier.removeLine(line.id),
                  tooltip: strings.actionDelete,
                  icon: Icon(
                    Icons.close,
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
        if (unallocated != null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              // Through `AmountText`, not `minor.toString()`. `Money` is minor units, so the old call
              // put `200000` on screen for two thousand rupees (Law U7).
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openItems(context),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(strings.lineAdd),
          ),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/payee_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// Picks a counterparty, and creates one inline when it does not exist yet.
///
/// **Inline creation rather than a trip to Settings.** A payee is discovered at the moment of
/// recording a purchase — you find out the shop is called "Reliance Fresh" while you are typing the
/// receipt, not before. Sending the user to a settings screen to add one guarantees the field is
/// left blank, and a blank payee is the column that makes "top payees by spend" useless.
///
/// One widget rather than one per sub-form: six of the seven need it, and six copies is how one
/// component becomes six that drift (ARCH_4 R25).
class PayeeField extends ConsumerStatefulWidget {
  /// Creates the field for the editor identified by [editorId].
  const PayeeField({required this.editorId, required this.selectedId, super.key});

  /// The editor family argument, so the field writes to the right notifier.
  final String? editorId;

  /// The payee currently chosen.
  final String? selectedId;

  @override
  ConsumerState<PayeeField> createState() => _PayeeFieldState();
}

class _PayeeFieldState extends ConsumerState<PayeeField> {
  final TextEditingController _newName = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    final strings = AlayaStrings.of(context);
    final created =
        await ref.read(transactionEditorProvider(widget.editorId).notifier).createPayee(name);
    if (!mounted) return;
    // **The field stays open on failure, holding what was typed.** Closing it and clearing the name
    // would discard the user's input and leave them with an empty picker and no explanation — which
    // reads as the app having quietly ignored them.
    if (!created) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    _newName.clear();
    setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees = ref.watch(editorPayeesProvider).valueOrNull ?? const <Payee>[];
    final notifier = ref.read(transactionEditorProvider(widget.editorId).notifier);

    Payee? current;
    for (final payee in payees) {
      if (payee.id == widget.selectedId) {
        current = payee;
        break;
      }
    }

    if (_creating) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _newName,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: strings.labelPayee),
              onSubmitted: (_) => _create(),
            ),
          ),
          const SizedBox(width: AlayaSpacing.xs),
          TextButton(onPressed: _create, child: Text(strings.actionAdd)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(current?.id),
            initialValue: current?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelPayee),
            items: [
              for (final payee in payees)
                DropdownMenuItem(
                  value: payee.id,
                  child: Text(payee.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: notifier.setPayee,
          ),
        ),
        const SizedBox(width: AlayaSpacing.xs),
        TextButton(
          onPressed: () => setState(() => _creating = true),
          child: Text(strings.actionAdd),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/grocery_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The grocery purchase sub-form.
///
/// Lines default to `destination = inventory`: a grocery receipt is the single most common way stock
/// enters the house, and defaulting to anything else means the inventory module stays empty however
/// diligently the user records their spending.
class GroceryForm extends ConsumerWidget {
  /// Creates the form.
  const GroceryForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PayeeField(editorId: editorId, selectedId: state.payeeId),
          LineItemsSection(
            editorId: editorId,
            state: state,
            decimalDigits: decimalDigits,
            defaultDestination: TransactionLineDestination.inventory,
          ),
        ],
      );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/household_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The household purchase sub-form.
///
/// Identical in shape to the grocery form, and deliberately a separate file rather than an alias:
/// the two subtypes exist because they land in different analytics buckets, and a single shared
/// widget invites the first divergence to be made by editing the other module's form.
class HouseholdForm extends ConsumerWidget {
  /// Creates the form.
  const HouseholdForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PayeeField(editorId: editorId, selectedId: state.payeeId),
          LineItemsSection(
            editorId: editorId,
            state: state,
            decimalDigits: decimalDigits,
            defaultDestination: TransactionLineDestination.inventory,
          ),
        ],
      );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/electronics_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The electronics purchase sub-form.
///
/// **Lines default to `destination = asset`, not inventory, and the inventory opt-in is explicit.**
/// A television is a durable, serviceable thing with a warranty and a service history — it is not
/// consumable stock. Pushing it to both modules is anomaly A12: neither then owns the truth about
/// what you actually have. The opt-in exists because a few things genuinely are both, and it is off
/// by default because most are not.
///
/// The warranty window is collected here rather than on the line, because `transaction_lines` has no
/// column for it. The editor applies it to the asset the fan-out plans.
class ElectronicsForm extends ConsumerWidget {
  /// Creates the form.
  const ElectronicsForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.sectionWarranty,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        DatePickerField(
          value: state.warrantyStart,
          formatted: format,
          label: strings.labelFrom,
          hint: strings.hintSelectDate,
          onChanged: (date) => notifier.setWarranty(start: date, end: state.warrantyEnd),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.warrantyEnd,
          formatted: format,
          label: strings.labelTo,
          hint: strings.hintSelectDate,
          onChanged: (date) => notifier.setWarranty(start: state.warrantyStart, end: date),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        CheckboxListTile(
          value: state.alsoAddToInventory,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(strings.alsoAddToInventory),
          onChanged: (value) =>
              notifier.setAlsoAddToInventory(value: value ?? false),
        ),
        LineItemsSection(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
          defaultDestination: state.alsoAddToInventory
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.asset,
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/bill_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/due_bills_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The bill payment sub-form.
///
/// A bill paid off-template is an ordinary withdrawal with `subtype = bill` and a null
/// `recurringTemplateId` — which is why this form never requires a template. Paying a bill you never
/// set up must not be harder than paying one you did.
///
/// **Selecting a due bill links this payment to it; it does not pay it here.** An earlier version
/// opened the pay sheet from this list, which left two write paths reachable at once: the sheet
/// recorded one transaction and then saving the editor recorded a second for the same payment. There
/// is now one amount field and one save — picking a bill routes that save through `payOccurrence`,
/// which settles the occurrence and writes the transaction together.
class BillForm extends ConsumerWidget {
  /// Creates the form.
  const BillForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final due = ref.watch(dueBillsProvider);
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.billDueSection,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        due.when(
          // A failed or pending schedule read costs the shortcut, never the ability to record a bill
          // by hand — which is what this form does without any of this.
          loading: () => Text(
            strings.loadingRecurring,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          error: (error, stack) => Text(
            error.toString(),
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
          data: (rows) => rows.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.billNothingDue,
                      style: AlayaTypography.caption.copyWith(color: semantic.muted),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    TextButton.icon(
                      onPressed: () => context.push(Routes.recurringNew),
                      icon: const Icon(Icons.event_repeat, size: AlayaIconSize.sm),
                      label: Text(strings.billSetUpAction),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.billSettleHelp,
                      style: AlayaTypography.caption.copyWith(color: semantic.muted),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    RadioGroup<String?>(
                      groupValue: state.recurringOccurrenceId,
                      onChanged: (value) {
                        if (value == null) {
                          notifier.setRecurringOccurrence();
                          return;
                        }
                        for (final row in rows) {
                          if (row.occurrence!.id != value) continue;
                          notifier.setRecurringOccurrence(
                            occurrenceId: value,
                            defaultAmount: row.template.defaultAmount,
                            accountId: ref.read(
                              resolvedBillAccountProvider(
                                row.template.defaultAccountId,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RadioListTile<String?>(
                            value: null,
                            contentPadding: EdgeInsets.zero,
                            title: Text(strings.billSettleNone),
                          ),
                          for (final row in rows)
                            RadioListTile<String?>(
                              value: row.occurrence!.id,
                              contentPadding: EdgeInsets.zero,
                              title: Text(row.template.name),
                              subtitle: Wrap(
                                spacing: AlayaSpacing.xs,
                                runSpacing: AlayaSpacing.xxs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  AmountText(
                                    row.template.defaultAmount,
                                    size: AmountSize.small,
                                    showSign: false,
                                    decimalDigits: digits,
                                  ),
                                  DateText(
                                    row.occurrence!.dueDateKey,
                                    style: DateTextStyle.medium,
                                    muted: true,
                                  ),
                                  if (row.occurrence!.isOverdue(today))
                                    StatusChip(
                                      label: strings.recurringOverdue,
                                      tone: StatusTone.danger,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.recurringOccurrenceId != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Text(
                        strings.billAmountBecomesPaid,
                        style: AlayaTypography.caption.copyWith(color: semantic.transfer),
                      ),
                      // Only reached when the template, the app default and a sole account all failed
                      // to answer — so it is asked once and remembered on the bill, never per payment.
                      if (state.accountMissing) ...[
                        const SizedBox(height: AlayaSpacing.xs),
                        Text(
                          strings.billAccountAskOnce,
                          style: AlayaTypography.caption.copyWith(color: semantic.danger),
                        ),
                      ] else if (state.fromAccountId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                          child: Text(
                            strings.billAccountAuto,
                            style: AlayaTypography.caption.copyWith(color: semantic.muted),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/transfer_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The transfer sub-form — and the one place in this app where the copy has to be exact.
///
/// **"To my own account" and "To someone else" are different transaction kinds, not two phrasings
/// of one.** Moving ₹5,000 from Cash to Bank must not reduce net worth: it is `kind = transfer`,
/// it appears in both accounts' ledgers with opposite signs, and it nets to zero by construction.
/// Sending ₹5,000 to your brother is a real withdrawal with `subtype = transferOut` and a payee.
///
/// Getting this wrong is anomaly A02, and the symptom is a net worth that falls every time the user
/// moves their own money between their own accounts — a number they cannot explain and will not
/// trust again.
class TransferForm extends ConsumerWidget {
  /// Creates the form.
  const TransferForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(strings.transferOwnAccount)),
            ButtonSegment(value: false, label: Text(strings.transferSomeoneElse)),
          ],
          selected: {state.toOwnAccount},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              notifier.setTransferTarget(toOwnAccount: selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          state.toOwnAccount
              ? strings.transferOwnAccountHelp
              : strings.transferSomeoneElseHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: accountFor(state.fromAccountId),
          label: strings.labelFrom,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setFromAccount(account.id),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.toOwnAccount)
          AccountPicker(
            accounts: accounts,
            selected: accountFor(state.toAccountId),
            label: strings.labelTo,
            hint: strings.hintSelectAccount,
            // Excluded so a transfer cannot have the same account on both sides, which the
            // transactions CHECK constraint rejects anyway (ARCH_2 §4.1).
            excludeId: state.fromAccountId,
            onChanged: (account) => notifier.setToAccount(account.id),
          )
        else
          PayeeField(editorId: editorId, selectedId: state.payeeId),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/other_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The catch-all withdrawal sub-form.
///
/// Lines default to `destination = none` and the chooser in the line editor is where the user says
/// otherwise. This is the form that can produce any of the three artefacts, which is why the
/// destination is a decision here rather than an assumption.
class OtherForm extends ConsumerWidget {
  /// Creates the form.
  const OtherForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PayeeField(editorId: editorId, selectedId: state.payeeId),
          LineItemsSection(
            editorId: editorId,
            state: state,
            decimalDigits: decimalDigits,
            defaultDestination: TransactionLineDestination.none,
          ),
        ],
      );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/deposit_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The deposit sub-form.
///
/// A deposit needs a destination account and no source — the mirror of a withdrawal, and the shape
/// the `transactions` CHECK constraint enforces (ARCH_2 §4.1). The payee is the *source* of the
/// money here rather than its recipient, which is why one `payees` table serves both directions.
class DepositForm extends ConsumerWidget {
  /// Creates the form.
  const DepositForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? selected;
    for (final account in accounts) {
      if (account.id == state.toAccountId) {
        selected = account;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: selected,
          label: strings.labelTo,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setToAccount(account.id),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/screens/transaction_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/bill_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/electronics_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/household_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/other_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// The full transaction editor (ARCH_5 §3 archetype B).
///
/// Routed **outside** the drawer shell, and led by a close button rather than a back arrow: an
/// editor is a task, and ✕ says "abandon" where ← says "go up". Both route through
/// `AlayaFormScaffold`'s unsaved-changes guard (Law U10).
///
/// **Sections group by decision, not by table.** "What and how much" precedes "where it came from",
/// and the sub-form that appears depends on the subtype — never a screen listing every column the
/// `transactions` row happens to have.
class TransactionEditorScreen extends ConsumerWidget {
  /// Edits [transactionId], or creates a new transaction when it is null.
  const TransactionEditorScreen({this.transactionId, super.key});

  /// The transaction being edited, or null for a new one.
  final String? transactionId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref.read(transactionEditorProvider(transactionId).notifier).save();
    if (!context.mounted) return;
    if (saved == null) {
      // The reason, not a stand-in for it (U9).
      final why = ref.read(transactionEditorProvider(transactionId)).valueOrNull?.saveError;
      showFailureSnack(context, message: why ?? strings.errorBodyGeneric);
      return;
    }
    final after = ref.read(transactionEditorProvider(transactionId)).valueOrNull;
    final fanOutError = after?.fanOutError;
    // A line that asked to become recurring replaces this screen with the builder rather than popping,
    // so the draft it just offered is picked up on the next frame instead of going nowhere.
    // An asset the fan-out just created opens for the type and the warranty a receipt could not carry.
    // Checked before the recurring hand-off because a line cannot be both.
    final createdAsset = after?.createdAssetId;
    if (createdAsset != null) {
      // **The router is captured before the pop, not looked up inside the action.**
      //
      // A snack outlives the screen that showed it, so by the time the user taps its action this
      // `context` is a deactivated element — and `context.push` walks the ancestor tree to find the
      // router, which throws *"Looking up a deactivated widget's ancestor is unsafe"*. The `GoRouter`
      // itself survives the pop; holding a reference to it is what makes the action safe.
      //
      // The messenger is captured for the same reason: `ScaffoldMessenger.of` would fail too.
      final router = GoRouter.of(context);
      final target = Routes.assetEdit(createdAsset);
      if (context.canPop()) context.pop();
      if (!context.mounted) return;
      showResultSnack(
        context,
        message: strings.assetCreatedFromPurchase,
        actionLabel: strings.actionSetWarranty,
        onAction: () => router.push(target),
      );
      return;
    }
    if (after?.wantsTemplate ?? false) {
      context.pushReplacement(Routes.recurringNew);
      if (!context.mounted) return;
      showResultSnack(context, message: strings.recurringScheduleNext);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    // A half-succeeded write says which half. The transaction is saved either way; what failed is the
    // stock or asset a line asked for, and saying nothing is how a receipt silently fails to reach
    // the inventory (U9).
    fanOutError != null
        ? showFailureSnack(context, message: fanOutError)
        : showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          transactionId == null ? strings.editorTitleNew : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        // "It may have been deleted" only when it actually is. Anything else is a load failure and
        // says so, with a retry — reporting both the same way is what made four different bugs
        // arrive as one indistinguishable symptom.
        error: (error, stack) => error is TransactionNotFound
            ? ErrorState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
              )
            : ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(transactionEditorProvider(transactionId)),
              ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: _saveLabel(strings, state.kind),
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: transactionId, state: state),
        ),
      ),
    );
  }

  static String _saveLabel(AlayaStrings strings, TransactionKind kind) => switch (kind) {
        TransactionKind.deposit => strings.saveIncome,
        TransactionKind.transfer => strings.saveTransfer,
        TransactionKind.withdrawal => strings.saveExpense,
        TransactionKind.adjustmentIncrease => strings.saveIncome,
        TransactionKind.adjustmentDecrease => strings.saveExpense,
      };
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts = ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final methods = ref.watch(editorPaymentMethodsProvider).valueOrNull ?? const <PaymentMethod>[];
    final tags = ref.watch(editorTagsProvider(state.kind)).valueOrNull ?? const <Tag>[];
    final localeTag = Localizations.localeOf(context).toString();

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.kindWithdrawal),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.kindDeposit),
            ),
            ButtonSegment(
              value: TransactionKind.transfer,
              label: Text(strings.kindTransfer),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        SectionHeader(
          label: strings.sectionWhatAndHowMuch,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelAmount,
            initialValue: state.amount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          label: strings.labelDate,
          formatted: (date) => DateFormat.yMMMd(localeTag).format(date.toUtcMidnight()),
          onChanged: notifier.setDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionSubtype>(
          key: ValueKey(state.subtype),
          initialValue: state.subtype,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelSubtype),
          items: [
            for (final subtype in state.availableSubtypes)
              DropdownMenuItem(
                value: subtype,
                child: Text(TransactionRow.subtypeLabel(strings, subtype)),
              ),
          ],
          onChanged: (value) => value == null ? null : notifier.setSubtype(value),
        ),
        if (state.kind != TransactionKind.transfer) ...[
          SectionHeader(
            label: state.kind == TransactionKind.deposit
                ? strings.sectionWhereItCameFrom
                : strings.sectionWhereItWent,
            padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
          ),
          if (state.kind != TransactionKind.deposit)
            AccountPicker(
              accounts: accounts,
              selected: accountFor(state.fromAccountId),
              label: strings.labelAccount,
              hint: strings.hintSelectAccount,
              onChanged: (account) => notifier.setFromAccount(account.id),
            ),
          const SizedBox(height: AlayaSpacing.md),
          DropdownButtonFormField<String>(
            key: ValueKey(state.paymentMethodId),
            initialValue: state.paymentMethodId,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelPaymentMethod),
            items: [
              for (final method in methods)
                DropdownMenuItem(value: method.id, child: Text(method.name)),
            ],
            onChanged: notifier.setPaymentMethod,
          ),
          const SizedBox(height: AlayaSpacing.md),
        ],
        _SubtypeForm(editorId: editorId, state: state, decimalDigits: digits),
        if (tags.isNotEmpty) ...[
          SectionHeader(
            label: strings.labelTags,
            padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
          ),
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagIds.contains(tag.id),
                  onTap: () => notifier.toggleTag(tag.id),
                ),
            ],
          ),
        ],
        SectionHeader(
          label: strings.labelNote,
          padding: const EdgeInsets.only(top: AlayaSpacing.xl, bottom: AlayaSpacing.xs),
        ),
        TextFormField(
          initialValue: state.note,
          maxLines: 3,
          decoration: InputDecoration(hintText: strings.hintNote),
          onChanged: notifier.setNote,
        ),
      ],
    );
  }
}

class _SubtypeForm extends StatelessWidget {
  const _SubtypeForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
  });

  final String? editorId;
  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    if (state.kind == TransactionKind.transfer ||
        state.subtype == TransactionSubtype.transferOut) {
      return TransferForm(editorId: editorId, state: state);
    }
    return switch (state.subtype) {
      TransactionSubtype.grocery => GroceryForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.household => HouseholdForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.electronics => ElectronicsForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
      TransactionSubtype.bill => BillForm(editorId: editorId, state: state),
      TransactionSubtype.salaryIn ||
      TransactionSubtype.otherIn =>
        DepositForm(editorId: editorId, state: state),
      TransactionSubtype.transferSelf ||
      TransactionSubtype.transferOut =>
        TransferForm(editorId: editorId, state: state),
      TransactionSubtype.otherOut => OtherForm(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
        ),
    };
  }
}
```

### `lib/app/router/app_router.dart`

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/placeholder_screen.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      redirect: (context, state) {
        final atLock = state.matchedLocation == Routes.lock;
        if (locked() && !atLock) return Routes.lock;
        if (!locked() && atLock) return Routes.dashboard;
        return null;
      },
      routes: [
        GoRoute(
          path: Routes.lock,
          builder: (context, state) =>
              const PlaceholderScreen(owningPhase: 'Phase 8A'),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            _destination(Routes.insights, 'Phase 7B'),
            _destination(Routes.settings, 'Phase 8A'),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
          ),
        ),
      ],
    );
  }

  /// A top-level drawer destination, rendered inside the shell.
  static GoRoute _destination(String path, String owningPhase) => GoRoute(
    path: path,
    builder: (context, state) => PlaceholderScreen(owningPhase: owningPhase),
  );

  /// A detail route, rendered outside the shell so it gets a back arrow rather than a hamburger.
  static GoRoute _detail(String pattern, String owningPhase) => GoRoute(
    path: pattern,
    builder: (context, state) => _DetailScaffold(
      title: AlayaDrawer.titleFor(context, state.uri.path),
      child: PlaceholderScreen(owningPhase: owningPhase),
    ),
  );
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
        ],
      ),
      body: child,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;

  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;

  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}
```

### `test/support/expense_harness.dart`

```dart
/// Shared scaffolding for the Expense module's widget tests.
///
/// **Overrides the feature's own view-model providers rather than faking twenty repositories.** A
/// widget test's job is the widget: whether it renders four states correctly, survives a doubled
/// text scale and meets the tap-target floor. Reaching through the whole provider graph to arrange
/// a loading state would test Riverpod, and would make each of these files four times longer for no
/// extra coverage.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The smallest width this app supports, paired with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so "Today" and "Yesterday" are the same two days on every machine.
final Clock kTestClock = FixedClock(DateTime(2026, 8, 1, 9, 30));

/// Today, according to [kTestClock].
const DateKey kToday = DateKey(20260801);

/// A stream that never emits and never closes, so an `AsyncValue` stays in its loading state.
///
/// `Stream.empty()` will not do: it closes immediately, which resolves the provider rather than
/// leaving it pending.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// A future that never completes, for the loading branch of a `FutureProvider`.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A sample account.
const Account kAccount = Account(
  id: 'acc-1',
  name: 'HDFC Savings',
  normalizedName: 'hdfc savings',
  kind: AccountKind.bank,
  currencyCode: 'INR',
  openingBalance: Money(0, 'INR'),
  openingBalanceDateKey: DateKey(20260101),
  isArchived: false,
  includeInNetWorth: true,
  sortOrder: 0,
);

/// A sample payee.
const Payee kPayee = Payee(
  id: 'pay-1',
  name: 'Reliance Fresh',
  normalizedName: 'reliance fresh',
  kind: PayeeKind.merchant,
);

/// A sample transaction, flagged for review so the nudge has something to count.
Transaction sampleTransaction({
  String id = 'tx-1',
  bool needsReview = false,
  TransactionKind kind = TransactionKind.withdrawal,
  int minor = 125050,
}) =>
    Transaction(
      id: id,
      kind: kind,
      subtype: TransactionSubtype.grocery,
      occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      dateKey: kToday,
      originalAmount: Money(minor, 'INR'),
      needsReview: needsReview,
      fromAccountId: kAccount.id,
      payeeId: kPayee.id,
    );

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The `MediaQuery` sits inside `MaterialApp.builder` rather than above it: `WidgetsApp`
/// re-establishes it from the view, so an outer override never reaches the widget under test.
Future<void> pumpExpense(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: child,
      ),
    ),
  );
  await tester.pump();
}
```

### `test/features/expense/transaction_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, a narrow viewport at a doubled text scale, and the tap-target floor (ARCH_5 §9.1).
void main() {
  List<Override> overrides(AsyncValue<List<TransactionDayGroup>> days, {int needsReview = 0}) => [
        clockProvider.overrideWithValue(kTestClock),
        transactionDaysProvider.overrideWith((ref) => days),
        needsReviewCountProvider.overrideWith((ref) => Stream.value(needsReview)),
        accountsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
        ),
        payeesByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
        ),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
      ];

  final populated = AsyncValue.data([
    TransactionDayGroup(date: kToday, transactions: [sampleTransaction()]),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to act rather than reporting emptiness', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Add your first expense and it will appear here.'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row per transaction', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Reliance Fresh'), findsOneWidget);
  });

  testWidgets('the needs-review nudge hides at zero and appears above it', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.text('Review'), findsNothing);

    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated, needsReview: 3),
    );
    expect(find.byType(NeedsReviewBanner), findsOneWidget);
    expect(find.text('3 transactions need details'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated, needsReview: 2),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/expense/transaction_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/expense_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: a null value renders no row,
/// and the destructive action sits last.
void main() {
  const id = 'tx-1';

  List<Override> overrides(AsyncValue<Transaction?> transaction) => [
        clockProvider.overrideWithValue(kTestClock),
        transactionByIdProvider(id).overrideWith((ref) async => transaction.valueOrNull),
        transactionLinesProvider(id)
            .overrideWith((ref) => Stream.value(const <TransactionLine>[])),
        transactionAllocationProvider(id).overrideWith((ref) => Stream.value(null)),
        transactionTagsProvider(id).overrideWith((ref) => Stream.value(const <Tag>[])),
        paymentMethodsByIdProvider
            .overrideWith((ref) => Stream.value(const <String, PaymentMethod>{})),
        accountsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
        ),
        payeesByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
        ),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(id).overrideWith((ref) => pendingFuture<Transaction?>()),
      ],
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing transaction reads as not found, not as a crash', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(const AsyncValue.data(null)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(id).overrideWith((ref) async => throw StateError('boom')),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders the hero and hides rows with no value', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reliance Fresh'), findsOneWidget);
    // The sample has no note and no payment method, so neither row exists at all — a screen of
    // dashes reads as broken data rather than as a record with optional fields.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Payment method'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('the destructive action is present and is not a filled button', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    // The screen is a ListView and the destructive action is deliberately its last child, so on a
    // 320x640 viewport it is not built until scrolled to. That it sits below everything else is the
    // point (ARCH_5 §5.5) — the test travels to it rather than assuming it is on screen.
    await tester.scrollUntilVisible(
      find.text('Delete transaction'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Delete transaction'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Delete transaction'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction(needsReview: true))),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(const AsyncValue.data(null)),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/expense/quick_add_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/expense_harness.dart';

/// The capture path's contract: one required field, everything else optional, and a rejection that
/// says so out loud rather than doing nothing (Laws U9 and U11).
void main() {
  List<Override> overrides({List<Account> accounts = const [kAccount]}) => [
        homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
        selectableAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
        quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      ];

  Widget host() => Scaffold(
        body: AlayaBottomSheet(child: const QuickAddSheet()),
      );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
  });

  testWidgets('offers accounts as chips, never a dropdown', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(DropdownButtonFormField<Account>), findsNothing);
  });

  testWidgets('an empty account list simply omits the chip row', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(accounts: const []));
    expect(find.text('Account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saving with no amount shakes and says why, rather than doing nothing',
      (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    final before = tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger;

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    final after = tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger;
    expect(after, greaterThan(before));
    expect(find.text('Enter an amount'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('loading accounts still lets the amount be typed', (tester) async {
    await pumpExpense(
      tester,
      host(),
      overrides: overrides(accounts: const []),
    );
    await tester.pump();
    // A capture sheet takes its first keystroke on its first frame (§5.2): the account list may still
    // be arriving and the amount field is already there.
    expect(find.byType(AmountField), findsOneWidget);
  });

  testWidgets('every target is labelled', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/expense/line_items_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  TransactionLine line({
    String id = 'line-1',
    String description = 'Onion',
    int? amountMinor = 4000,
    Qty? quantity,
    TransactionLineDestination destination = TransactionLineDestination.none,
  }) =>
      TransactionLine(
        id: id,
        transactionId: '',
        lineNo: 1,
        description: description,
        destination: destination,
        quantity: quantity,
        lineAmount: amountMinor == null ? null : Money(amountMinor, 'INR'),
      );

  TransactionEditorState state({List<TransactionLine> lines = const [], int? amountMinor = 20000}) =>
      TransactionEditorState(
        currencyCode: 'INR',
        dateKey: kToday,
        amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
        lines: lines,
      );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TransactionEditorState> value) => [
        transactionEditorProvider.overrideWith(() => _StubEditor(value)),
        homeDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first item and says what happens if you skip it',
      (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing itemised yet'), findsOneWidget);
    // Itemising is optional (anomaly A11), and the empty state has to say so or it reads as a
    // required step blocking the save.
    expect(find.textContaining('Anything you leave out still counts'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated lists every line with its figure', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(lines: [line(), line(id: 'line-2', description: 'Tomato', amountMinor: 6000)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('the running figures show what is itemised and what is not', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line()], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    // 200.00 entered, 40.00 itemised. The gap is shown, never auto-balanced (anomaly A11).
    expect(find.text('Itemised'), findsOneWidget);
    expect(find.text('Unallocated'), findsOneWidget);
  });

  testWidgets('a fully itemised transaction shows no unallocated chip', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line(amountMinor: 20000)], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unallocated'), findsNothing);
  });

  testWidgets('an inventory line is marked as one', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('500 g'), findsOneWidget);
  });

  testWidgets('removing a line reports it', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    // No Undo: nothing has been written, so a snack promising undo for an uncommitted edit would be
    // lying (§5.4). It confirms, and stops there.
    expect(find.text('Item removed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Done leaves without committing anything', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    // The page edits editor state; the transaction is written by the editor's own save.
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
              line(id: 'line-2', description: 'Tomato', amountMinor: 6000),
            ],
          ),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

### `test/features/expense/transaction_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// The editor's four states, and the two behaviours the phase brief singles out: the sub-form
/// switches on subtype, and switching flow type preserves what the new shape can still hold.
void main() {
  TransactionEditorState seed({
    TransactionKind kind = TransactionKind.withdrawal,
    TransactionSubtype subtype = TransactionSubtype.grocery,
  }) =>
      TransactionEditorState(
        currencyCode: 'INR',
        dateKey: kToday,
        kind: kind,
        subtype: subtype,
      );

  List<Override> overrides(AsyncValue<TransactionEditorState> state) => [
        transactionEditorProvider(null).overrideWith(() => _StubEditor(state)),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
        selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
        editorPaymentMethodsProvider
            .overrideWith((ref) => Stream.value(const <PaymentMethod>[])),
        editorPayeesProvider.overrideWith((ref) => Stream.value(const [kPayee])),
        for (final kind in TransactionKind.values)
          editorTagsProvider(kind).overrideWith((ref) => Stream.value(const <Tag>[])),
      ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new transaction opens on the form, which is its empty state', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsOneWidget);
  });

  testWidgets('the visible sub-form switches on subtype', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(GroceryForm), findsOneWidget);
    expect(find.byType(TransferForm), findsNothing);

    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(kind: TransactionKind.deposit, subtype: TransactionSubtype.salaryIn),
        ),
      ),
    );
    expect(find.byType(DepositForm), findsOneWidget);
    expect(find.byType(GroceryForm), findsNothing);
  });

  testWidgets('a transfer shows the two-option toggle, not a payee-only form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(kind: TransactionKind.transfer, subtype: TransactionSubtype.transferSelf),
        ),
      ),
    );
    expect(find.byType(TransferForm), findsOneWidget);
    expect(find.text('To my own account'), findsOneWidget);
    expect(find.text('To someone else'), findsOneWidget);
    // The copy states the consequence rather than the mechanism — this is anomaly A02's whole point.
    expect(find.text('Moves money between your accounts. Your total does not change.'),
        findsOneWidget);
  });

  testWidgets('the commit lives in the footer, never in the app bar', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    final appBar = find.byType(AppBar);
    expect(
      find.descendant(of: appBar, matching: find.widgetWithText(TextButton, 'Save expense')),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier that reports a fixed state, so each of the four branches can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<TransactionEditorState> _state;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _state;
}
```

### `test/shared/layout_overflow_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/batch.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';
import 'package:alaya/domain/entities/shopping_list.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/inventory/presentation/sheets/consume_sheet.dart';
import 'package:alaya/features/inventory/providers/consume_providers.dart';
import 'package:alaya/features/inventory/providers/item_editor_providers.dart';
import 'package:alaya/features/shopping/presentation/sheets/entry_editor_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/generate_sheet.dart';
import 'package:alaya/features/shopping/presentation/sheets/list_manager_sheet.dart';
import 'package:alaya/features/shopping/providers/entry_editor_providers.dart';
import 'package:alaya/features/shopping/providers/shopping_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_expandable_fab.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/loading_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/features/recurring/presentation/sheets/pay_sheet.dart';
import 'package:alaya/features/recurring/providers/pay_providers.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/day_sheet.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/service/presentation/sheets/dispose_sheet.dart';
import 'package:alaya/features/service/presentation/widgets/contact_action.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/domain/services/balance_service.dart';
import 'package:alaya/features/dashboard/presentation/widgets/funds_header.dart';
import 'package:alaya/features/dashboard/presentation/widgets/insight_card.dart';
import 'package:alaya/features/dashboard/providers/funds_providers.dart';
import 'package:alaya/features/dashboard/providers/insight_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

import '../support/expense_harness.dart';
import '../support/fake_settings_repository.dart';
// Prefixed: `kToday` and `kNarrowPhone` are declared by every harness in this project, and this is
// the only file that imports two of them.
import '../support/calendar_harness.dart' as cal;

/// The only thing in this project that catches a layout overflow (ARCH_3 §8.3, ARCH_5 U2).
///
/// **Every sheet and every full-height state belongs here.** These defects are invisible to
/// `dart analyze`, to a file-by-file scan and to looking at the screen, because the missing
/// affordance is always an *ancestor*: the widget under review is locally correct and the parent
/// that should have given it room, or a way to scroll, is the one at fault.
///
/// They are also invisible to an ordinary widget test. A `RenderFlex` overflow reports through
/// `FlutterError.onError` rather than throwing at the site, so a test only fails on one if something
/// asks — which is exactly how an overflow hides in a suite that otherwise looks green. Every case
/// below asks, via `tester.takeException()`.
void main() {
  /// Roughly what a software keyboard takes from a phone in portrait.
  const double keyboardInset = 320;

  /// Roughly the room a list area has left on a small phone with a keyboard up.
  const Size squeezed = Size(320, 140);

  Widget host(
    Widget child, {
    double bottomInset = 0,
    double textScale = 1,
    List<Override> overrides = const [],
  }) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AlayaTheme.light(AlayaPresets.activePreset),
          // Every expense sheet reads `AlayaStrings.of(context)`, which unwraps a null without a
          // delegate installed. The Phase 5 groups pass literal strings, so this file went without
          // one until real screens arrived — and then failed as a null-check rather than as a
          // missing translation, which is why it read like five separate defects.
          localizationsDelegates: const [
            AlayaStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AlayaStrings.supportedLocales,
          // Inside the app rather than above it. `WidgetsApp` re-establishes `MediaQuery` from the
          // view, so an outer one is discarded before anything under test can read it — and a test
          // that believes it has simulated a keyboard when it has not is worse than no test.
          builder: (context, inner) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              viewInsets: EdgeInsets.only(bottom: bottomInset),
              textScaler: TextScaler.linear(textScale),
            ),
            child: inner!,
          ),
          home: Scaffold(body: child),
        ),
      );

  /// Content taller than the room a keyboard leaves, so the assertions are about the scaffold rather
  /// than about how long a particular string happens to be.
  Widget tallContent() => const Column(
        mainAxisSize: MainAxisSize.min,
        children: [SizedBox(width: 200, height: 400)],
      );

  group('AlayaBottomSheet', () {
    testWidgets('scrolls rather than overflowing with a keyboard up', (tester) async {
      await tester.pumpWidget(
        host(AlayaBottomSheet(child: tallContent()), bottomInset: keyboardInset),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('still fits when there is no keyboard', (tester) async {
      await tester.pumpWidget(host(AlayaBottomSheet(child: tallContent())));
      expect(tester.takeException(), isNull);
    });

    // The bug, reproduced deliberately. `Padding(bottom: viewInsets)` around a `MainAxisSize.min`
    // Column is correct in each half and broken together: the padding shrinks the space and the
    // Column has no way to give up the room it already took. **If this ever stops overflowing, the
    // guard above has stopped testing anything** — and the reason AlayaBottomSheet exists has
    // quietly gone away.
    testWidgets('the un-scaffolded shape it replaces still overflows', (tester) async {
      await tester.pumpWidget(
        host(
          Padding(
            padding: const EdgeInsets.only(bottom: keyboardInset),
            child: tallContent(),
          ),
        ),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });
  });

  group('ConfirmSheet', () {
    testWidgets('survives a keyboard and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => ConfirmSheet.show(
                context,
                title: 'Delete this transaction?',
                body: 'You can undo this for the next few seconds.',
                confirmLabel: 'Delete',
                cancelLabel: 'Cancel',
                destructive: true,
              ),
              child: const Text('open'),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('AlayaFormScaffold', () {
    Widget form({bool submitting = false}) => AlayaFormScaffold(
          primaryLabel: 'Save expense',
          onPrimary: () {},
          secondaryLabel: 'Cancel',
          onSecondary: () {},
          isDirty: true,
          isSubmitting: submitting,
          discardTitle: 'Discard your changes?',
          discardBody: 'What you have typed will not be saved.',
          discardConfirmLabel: 'Discard',
          discardCancelLabel: 'Keep editing',
          child: const Column(
            children: [SizedBox(height: 300), TextField(), SizedBox(height: 300)],
          ),
        );

    testWidgets('body scrolls and the footer stays above the keyboard', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset));
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a doubled text scale with a keyboard up', (tester) async {
      await tester.pumpWidget(host(form(), bottomInset: keyboardInset, textScale: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the submitting footer does not grow the row past its box', (tester) async {
      await tester.pumpWidget(host(form(submitting: true), textScale: 2));
      expect(tester.takeException(), isNull);
    });
  });

  // Every sheet Phase 6A adds, at a keyboard inset and a doubled text scale — the two conditions
  // under which each of them is first used and least likely to have been looked at.
  group('expense sheets', () {
    final expenseOverrides = <Override>[
      homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
      homeDecimalDigitsProvider.overrideWith((ref) => 2),
      selectableAccountsProvider.overrideWith((ref) => Stream.value(const [kAccount])),
      quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      accountsByIdProvider
          .overrideWith((ref) => Stream.value(<String, Account>{kAccount.id: kAccount})),
      lineEditorItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      enabledCurrenciesProvider.overrideWith(
        (ref) => Stream.value(const [
          Currency(
            code: 'USD',
            name: 'US Dollar',
            symbol: r'$',
            decimalDigits: 2,
            isEnabled: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: expenseOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets('QuickAddSheet', (tester) => pumpSheet(tester, const QuickAddSheet()));

    testWidgets(
      'TransactionFilterSheet',
      (tester) => pumpSheet(tester, const TransactionFilterSheet()),
    );

    testWidgets(
      'LineItemEditor',
      (tester) => pumpSheet(
        tester,
        const LineItemEditor(
          currencyCode: 'INR',
          decimalDigits: 2,
          defaultDestination: TransactionLineDestination.inventory,
        ),
      ),
    );

    testWidgets(
      'DeleteTransactionSheet',
      (tester) => pumpSheet(tester, const DeleteTransactionSheet()),
    );

    testWidgets(
      'FreezeConversionSheet',
      (tester) => pumpSheet(tester, const FreezeConversionSheet(excludeCode: 'INR')),
    );
  });

  // Phase 6B's sheet, at a keyboard inset and a doubled text scale — the two conditions under
  // which it is first used and least likely to have been looked at (U2).
  group('inventory sheets', () {
    final inventoryOverrides = <Override>[
      consumeFefoProvider('item-1').overrideWith((ref) => Stream.value(const <Batch>[])),
      unitsInCategoryProvider(UnitCategory.weight).overrideWith(
        (ref) => Stream.value(const [
          Unit(
            code: 'kg',
            category: UnitCategory.weight,
            factorToBaseMilli: 1000000,
            displayName: 'kilogram',
            isSystem: true,
            sortOrder: 1,
          ),
        ]),
      ),
    ];

    testWidgets('ConsumeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: ConsumeSheet(
              itemId: 'item-1',
              unitCode: 'kg',
              category: UnitCategory.weight,
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: inventoryOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6C's three sheets, at a keyboard inset and a doubled text scale — the two conditions under
  // which each is first used and least likely to have been looked at (U2).
  group('shopping sheets', () {
    final shoppingOverrides = <Override>[
      entryItemsProvider.overrideWith((ref) => Stream.value(const <Item>[])),
      entryTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
      entryCurrencyProvider.overrideWith((ref) async => 'INR'),
      entryDecimalDigitsProvider.overrideWith((ref) async => 2),
      entriesProvider('list-1').overrideWith((ref) => Stream.value(const <ShoppingEntry>[])),
      shoppingItemsByIdProvider.overrideWith((ref) => Stream.value(const <String, Item>{})),
      allListsProvider.overrideWith((ref) => Stream.value(const <ShoppingList>[])),
    ];

    Future<void> pumpSheet(WidgetTester tester, Widget sheet) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(child: sheet),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: shoppingOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    testWidgets(
      'EntryEditorSheet',
      (tester) => pumpSheet(tester, const EntryEditorSheet(listId: 'list-1')),
    );

    testWidgets(
      'GenerateSheet',
      (tester) => pumpSheet(tester, const GenerateSheet(listId: 'list-1')),
    );

    testWidgets(
      'ListManagerSheet',
      (tester) => pumpSheet(tester, const ListManagerSheet()),
    );
  });

  // Phase 6D's pay sheet, at a keyboard inset and a doubled text scale — an amount field, a date
  // field, an account dropdown and a two-line note, all growing at once.
  group('recurring sheets', () {
    final recurringOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      payAccountsProvider.overrideWith((ref) => Stream.value(const <Account>[])),
      payDecimalDigitsProvider('INR').overrideWith((ref) async => 2),
    ];

    testWidgets('PaySheet', (tester) async {
      await tester.pumpWidget(
        host(
          AlayaBottomSheet(
            child: PaySheet(
              occurrenceId: 'occ-1',
              template: RecurringTemplate(
                id: 'tpl-1',
                name: 'A rent template with a name long enough to wrap at a doubled scale',
                normalizedName: 'rent',
                kind: RecurringKind.rent,
                direction: RecurringDirection.outflow,
                defaultAmount: const Money(120000, 'INR'),
                intervalUnit: RecurringIntervalUnit.month,
                intervalCount: 1,
                startDateKey: const DateKey(20260131),
                nextDueDateKey: const DateKey(20260831),
                isPaused: false,
                autoRemind: true,
                remindDaysBefore: 3,
                anchorDayOfMonth: 31,
              ),
            ),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: recurringOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6D adds, with a clamp note on every row.
  group('FrequencyPreview at a doubled text scale', () {
    testWidgets('three dates, two of them clamped', (tester) async {
      await tester.pumpWidget(
        host(
          const FrequencyPreview(
            dates: [
              PreviewedDate(dateKey: DateKey(20260131)),
              PreviewedDate(dateKey: DateKey(20260228), clamped: true),
              PreviewedDate(dateKey: DateKey(20260331)),
            ],
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6E's dispose sheet: seven choice chips, a date field, an optional amount and a note, all
  // growing at once under a keyboard inset.
  group('service sheets', () {
    final serviceOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      serviceDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('DisposeSheet', (tester) async {
      await tester.pumpWidget(
        host(
          const AlayaBottomSheet(
            child: DisposeSheet(assetId: 'asset-1', currencyCode: 'INR'),
          ),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: serviceOverrides,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The contact block: a name, a number and a call button, none of them flexible.
  group('ContactAction at a doubled text scale', () {
    testWidgets('a long name beside a long number', (tester) async {
      await tester.pumpWidget(
        host(
          const ContactAction(
            phone: '+91 98765 43210',
            name: 'A service centre with a name long enough to wrap',
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6F's dashboard sections. Each is a card whose figures, chips and labels all grow at once, and
  // the funds header carries the only display-sized amount in the app.
  group('dashboard sections', () {
    final dashOverrides = <Override>[
      clockProvider.overrideWithValue(FixedClock(DateTime(2026, 8, 1))),
      // InsightCard's notifier restores its side from `app_settings` on the first frame, which
      // resolves `databaseProvider` unless this is here — the failure reads as a database bug in a
      // test that never mentions one (ARCH_6 P6).
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      dashboardCurrencyProvider.overrideWith((ref) async => 'INR'),
      dashboardDigitsProvider.overrideWith((ref) async => 2),
      totalFundsProvider.overrideWith(
        (ref) async => const NetWorth(
          total: Money(98765432, 'INR'),
          unconvertedCount: 3,
          isApproximate: true,
        ),
      ),
      upcomingProvider.overrideWith((ref) async => const <UpcomingEntry>[]),
    ];

    testWidgets('FundsHeader with both chips at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const FundsHeader(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('InsightCard with its switch at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const InsightCard(), textScale: 2, overrides: dashOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // The one shared widget Phase 6F adds. Two lines of text and a glyph inside a fixed aspect ratio is
  // exactly the shape that overflows when the text doubles and the box does not.
  group('ModuleTile at a doubled text scale', () {
    testWidgets('a long label beside a long count', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 160,
            height: 108,
            child: ModuleTile(
              label: 'Recurring commitments',
              icon: Icons.event_repeat,
              detail: '17 need attention before the end of the month',
              onTap: () {},
            ),
          ),
          textScale: 2,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 7A. Both shapes here are the ones that have already cost this project rounds: a sheet whose
  // content outgrows the viewport, and a grid of text cells whose row height does not move with the text.
  // Zero width, which is not a hypothetical: Android reports it on the first frame of every launch
  // ("D/FlutterRenderer: Width is zero. 0,0") and the FAB's slot subtracted padding from it, producing a
  // negative width and a red screen on startup. Every widget harness sets a real viewport before pumping,
  // which is exactly why nothing here caught it — so the degenerate viewport is now stated outright.
  group('degenerate viewports', () {
    testWidgets('the expandable FAB survives a zero-width first frame', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size.zero),
            child: Scaffold(
              floatingActionButton: AlayaExpandableFab(
                openLabel: 'Add',
                closeLabel: 'Close',
                actions: [
                  FabAction(label: 'One', icon: Icons.add, onPressed: () {}),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('calendar', () {
    List<Override> calOverrides({List<CalendarEvent> events = const []}) =>
        cal.calendarOverrides(cal.FakeCalendarRepository(events: events));

    final busyDay = <CalendarEvent>[
      cal.event(title: 'A payee with a name long enough to wrap at a doubled scale', amountMinor: 98765432),
      cal.event(
        type: CalendarEventType.serviceDue,
        refType: 'asset',
        refId: 'as-1',
        title: 'The boiler in the upstairs cupboard',
        baseSeverity: CalendarSeverity.warning,
      ),
      cal.event(
        type: CalendarEventType.batchExpiry,
        refType: 'inventoryBatch',
        refId: 'ba-1',
        title: 'Yoghurt, the large tub',
        baseSeverity: CalendarSeverity.warning,
      ),
    ];

    testWidgets('DaySheet with three grouped entries at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('DaySheet with a keyboard up as well', (tester) async {
      await tester.pumpWidget(
        host(
          const DaySheet(dateKey: cal.kToday),
          bottomInset: keyboardInset,
          textScale: 2,
          overrides: calOverrides(events: busyDay),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // U26: `TableCalendar` takes a fixed `rowHeight`, so the grid computes one from the text scaler. If
    // that computation is ever replaced by a constant, this is the test that says so.
    testWidgets('the month grid at a doubled scale on the narrowest phone', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('the month grid at a tripled scale, which is past what U15 asks for',
        (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 3, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    // The range header prints two formatted dates and a dash, which is the longest single string this
    // screen can produce — and it appears only in a mode the other cases never enter.
    testWidgets('the range header at a doubled scale', (tester) async {
      await tester.pumpWidget(
        host(const CalendarScreen(), textScale: 2, overrides: calOverrides(events: busyDay)),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('10'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('22'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    // The screen's own composition, which the shared full-height group cannot reach: six measured rows
    // plus a header are taller than a squeezed list area on their own, so the grid and the state beneath
    // it have to share a scroll rather than compete for a fixed box.
    for (final scale in [1.0, 2.0]) {
      testWidgets('the whole screen in a squeezed viewport at ${scale}x', (tester) async {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: scale,
            overrides: calOverrides(events: busyDay),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    // Each of the three states in turn, in the same squeezed box. Loading and error sit in the sliver
    // that fills the remainder, and that remainder is negative here.
    testWidgets('loading, empty and error all survive the squeezed box', (tester) async {
      for (final repo in [
        cal.FakeCalendarRepository(pending: true),
        cal.FakeCalendarRepository(),
        cal.FakeCalendarRepository(error: 'view unavailable'),
      ]) {
        await tester.pumpWidget(
          host(
            SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: const CalendarScreen(),
            ),
            textScale: 2,
            overrides: cal.calendarOverrides(repo),
          ),
        );
        // `pump`, not `pumpAndSettle`: the loading case holds a `CircularProgressIndicator`, which
        // animates forever, so `pumpAndSettle` times out rather than settling. Two frames is enough to
        // resolve the completed futures in the other two cases.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('full-height states in a squeezed viewport', () {
    Widget inSqueezedBox(Widget child) => host(
          Center(
            child: SizedBox(width: squeezed.width, height: squeezed.height, child: child),
          ),
        );

    testWidgets('EmptyState with an icon, body and action', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          EmptyState(
            title: 'No transactions yet',
            body: 'Add your first expense and it will appear here.',
            icon: Icons.receipt_long_outlined,
            actionLabel: 'Add expense',
            onAction: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('ErrorState with a retry — the tallest of the three', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          ErrorState(
            title: 'That did not work',
            body: 'Something went wrong on our side. Try again.',
            retryLabel: 'Try again',
            onRetry: () {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('LoadingState', (tester) async {
      await tester.pumpWidget(inSqueezedBox(const LoadingState(label: 'Loading')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AlayaListSkeleton clips rather than overflowing', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(const AlayaListSkeleton(label: 'Loading transactions')),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EmptyState at a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(
          Center(
            child: SizedBox(
              width: squeezed.width,
              height: squeezed.height,
              child: EmptyState(
                title: 'No transactions yet',
                body: 'Add your first expense and it will appear here.',
                icon: Icons.receipt_long_outlined,
                actionLabel: 'Add expense',
                onAction: () {},
              ),
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    // The states are also the shape the Theme Lab renders inside a half-width pane, which is where
    // the 150px `SizedBox` around an EmptyState used to overflow by roughly 58px.
    testWidgets('EmptyState in a half-width pane', (tester) async {
      await tester.pumpWidget(
        inSqueezedBox(
          const SizedBox(
            width: 134,
            child: EmptyState(title: 'No matches', body: 'Try a shorter search.'),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  // Phase 6A's line-items page: a full-height screen whose summary row, list rows and footer all
  // grow under text scale at once. Squeezed and doubled, which is the pair U21 exists for.
  group('the line items page', () {
    final editorOverrides = <Override>[
      transactionEditorProvider.overrideWith(
        () => _FixedEditor(
          AsyncValue.data(
            TransactionEditorState(
              currencyCode: 'INR',
              dateKey: const DateKey(20260801),
              amount: const Money(20000, 'INR'),
              lines: [
                TransactionLine(
                  id: 'l1',
                  transactionId: '',
                  lineNo: 1,
                  description: 'A description long enough to need two lines at a doubled scale',
                  destination: TransactionLineDestination.inventory,
                  quantity: const Qty(500000, UnitCategory.weight),
                  lineAmount: const Money(4000, 'INR'),
                ),
              ],
            ),
          ),
        ),
      ),
      homeDecimalDigitsProvider.overrideWith((ref) async => 2),
    ];

    testWidgets('populated at 320dp and a doubled text scale', (tester) async {
      await tester.pumpWidget(
        host(const LineItemsScreen(), textScale: 2, overrides: editorOverrides),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('kit rows at a doubled text scale', () {
    testWidgets('KeyValueRow wraps a long value instead of overflowing', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 320,
            child: KeyValueRow(
              label: 'Payment method',
              value: 'Bank transfer from HDFC Savings ending 4417',
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FilterChipBar wraps rather than clipping a row of chips', (tester) async {
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 320,
            child: FilterChipBar(
              clearAllLabel: 'Clear all',
              onClearAll: () {},
              filters: [
                ActiveFilter(label: 'Account: HDFC Savings', onRemove: () {}),
                ActiveFilter(label: 'Tag: Groceries', onRemove: () {}),
                ActiveFilter(label: 'Jan 2026 – Aug 2026', onRemove: () {}),
              ],
            ),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('StatusChip ellipsises a long label in a narrow box', (tester) async {
      await tester.pumpWidget(
        host(
          const SizedBox(
            width: 96,
            child: StatusChip(label: 'Needs details', tone: StatusTone.info),
          ),
          textScale: 2,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}

/// A transaction editor reporting a fixed state, so a layout can be pumped without a database.
class _FixedEditor extends TransactionEditorNotifier {
  _FixedEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

---

## COVERAGE — ARCH_5 §7 rows closed by Phase 6A

| Row | Closed by |
|---|---|
| `transactions` | quick-add creates · editor creates and updates · list reads · detail reads · delete sheet retires |
| `transaction_lines` | `LineItemEditor` + `LineItemsSection` create and edit · detail lists them |
| `transaction_tags` | quick-add's tag chips · the editor's scoped tag picker · detail renders them |
| `payees` *(inline create)* | `PayeeField` creates one without leaving the editor |
| §7.2 `needsReview` | `NeedsReviewBanner` + the row's `StatusChip` + the `needsReviewOnly` filter |
| §7.2 `converted*` / `conversionRateRaw` | `FreezeConversionSheet` → `freezeConversion`, rendered as a secondary amount and a frozen-rate row |
| §7.2 `deleteReason` | `DeleteTransactionSheet` |
| §7.2 line `destination` | the destination chooser in `LineItemEditor`, defaulted per sub-form |
| §7.2 `created*Id` | the "Created: …" link on a detail line, routing to the item, asset or template |
| §7.2 `unallocatedMinor` | the unallocated `StatusChip`, in the editor and on detail — never auto-balanced |

**Deferred, with an owner — for ARCH_5 §7.3**

| Gap | Why | Owner |
|---|---|---|
| Filter by tag | No 3A contract exposes a tag-to-transactions reverse lookup; filtering would cost one query per row | 7B, which needs the same join for spend-by-tag |
| Undo after delete | `TransactionRepository` has no `restore`, and `update()` reads through `v_active_transactions` so it cannot see a deleted row. Delete is therefore ARCH_5 §5.5's non-reversible tier: a sheet that names the consequence | 8B, whose trash screen needs `restore` anyway |
| Recurring template picker on the bill form | Needs the schedule model | 6D |
