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
  }) : _clock = null,
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
  }) : style = DateTextStyle.relative,
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
      style: (textStyle ?? AlayaTypography.caption).copyWith(
        color: muted ? semantic.muted : null,
      ),
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
