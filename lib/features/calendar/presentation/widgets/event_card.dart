import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The wording and glyph for one [CalendarEventType].
extension CalendarEventTypeDisplay on CalendarEventType {
  /// The localised name of this event type.
  String labelOf(AlayaStrings strings) => switch (this) {
    CalendarEventType.transaction => strings.eventTypeTransaction,
    CalendarEventType.recurringDue => strings.eventTypeRecurringDue,
    CalendarEventType.batchExpiry => strings.eventTypeBatchExpiry,
    CalendarEventType.warrantyEnd => strings.eventTypeWarrantyEnd,
    CalendarEventType.serviceDue => strings.eventTypeServiceDue,
    CalendarEventType.shoppingTarget => strings.eventTypeShoppingTarget,
  };

  /// The glyph for this event type.
  IconData get icon => switch (this) {
    CalendarEventType.transaction => Icons.receipt_long_outlined,
    CalendarEventType.recurringDue => Icons.event_repeat,
    CalendarEventType.batchExpiry => Icons.inventory_2_outlined,
    CalendarEventType.warrantyEnd => Icons.verified_outlined,
    CalendarEventType.serviceDue => Icons.handyman_outlined,
    CalendarEventType.shoppingTarget => Icons.shopping_basket_outlined,
  };
}

/// The colour and wording for one [CalendarSeverity].
extension CalendarSeverityDisplay on CalendarSeverity {
  /// The chip tone matching this severity.
  StatusTone get tone => switch (this) {
    CalendarSeverity.info => StatusTone.info,
    CalendarSeverity.warning => StatusTone.warning,
    CalendarSeverity.danger => StatusTone.danger,
  };

  /// The localised severity word, or null where there is nothing to warn about.
  String? labelOrNull(AlayaStrings strings) => switch (this) {
    CalendarSeverity.info => null,
    CalendarSeverity.warning => strings.calendarSeverityWarning,
    CalendarSeverity.danger => strings.calendarSeverityDanger,
  };

  /// The colour for this severity's glyph.
  Color colorOf(AlayaSemanticColors semantic) => switch (this) {
    CalendarSeverity.info => semantic.muted,
    CalendarSeverity.warning => semantic.warning,
    CalendarSeverity.danger => semantic.danger,
  };
}

/// One calendar entry, severity-coloured and severity-labelled.
///
/// The severity word is not decoration beside the colour — it is the carrier. Colour alone fails a
/// colour-blind reader and fails in grayscale, so `warning` and `danger` always say so (Law U9).
class EventCard extends StatelessWidget {
  /// Creates a card for [event].
  const EventCard({
    required this.event,
    required this.onTap,
    this.decimalDigits = 2,
    this.showType = true,
    super.key,
  });

  /// The entry to render, with its severity already resolved by `CalendarAggregator`.
  final CalendarEvent event;

  /// Opens the underlying record.
  final VoidCallback? onTap;

  /// Minor-unit digits for the amount, from the household's currency.
  final int decimalDigits;

  /// Whether to name the event type on the card.
  ///
  /// False inside a list already grouped by type: the heading says "Transaction" and so did every card
  /// under it, which is noise on the screen and two matches for one finder in the tests.
  final bool showType;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final severityLabel = event.baseSeverity.labelOrNull(strings);
    final typeLabel = event.type.labelOf(strings);

    return AlayaCard(
      onTap: onTap,
      semanticsLabel: [
        event.title,
        typeLabel,
        if (severityLabel != null) severityLabel,
      ].join('. '),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            event.type.icon,
            size: AlayaIconSize.md,
            color: event.baseSeverity.colorOf(semantic),
          ),
          const SizedBox(width: AlayaSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: AlayaTypography.body.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AlayaSpacing.xxs),
                // Wrap, not Row: the type label and the severity chip both grow with text scale and
                // side by side one of them starves at 320dp (Law U21).
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (showType)
                      Text(
                        typeLabel,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                      ),
                    if (severityLabel != null)
                      StatusChip(
                        label: severityLabel,
                        tone: event.baseSeverity.tone,
                      ),
                  ],
                ),
                if (event.amount != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  // Under the text, not beside it (Law U21).
                  //
                  // Beside it, the amount was the Row's one inflexible child: it took its natural width
                  // first and left the `Expanded` column whatever remained. At a doubled scale on a 320dp
                  // card that remainder was about 64px, and `StatusChip` cannot shrink below its own
                  // label — so the chip overflowed by 124px. Making the amount `Flexible` only splits the
                  // starvation two ways; the fix is to stop competing for the same axis.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AmountText(
                      event.amount!,
                      size: AmountSize.small,
                      showSign: false,
                      decimalDigits: decimalDigits,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
