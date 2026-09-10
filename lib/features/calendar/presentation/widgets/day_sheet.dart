import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/calendar/providers/calendar_providers.dart';
import 'package:alaya/features/calendar/presentation/widgets/calendar_event_list.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/loading_state.dart';

/// One day's calendar entries, grouped by event type (ARCH_5 §3 archetype A).
class DaySheet extends ConsumerWidget {
  /// Creates the sheet for [dateKey].
  const DaySheet({required this.dateKey, super.key});

  /// Opens the sheet for [dateKey].
  static Future<void> show({
    required BuildContext context,
    required DateKey dateKey,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (_) => DaySheet(dateKey: dateKey),
  );

  /// The day being shown.
  final DateKey dateKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final events = ref.watch(dayEventsProvider(dateKey));

    // The box, not the screen. Two rounds were lost guessing at this arithmetic from `MediaQuery`:
    // first `sizeOf().height * 0.6`, which ignored the keyboard; then the same minus
    // `viewInsetsOf().bottom`, which reads **zero** here because `Scaffold` with
    // `resizeToAvoidBottomInset` consumes the inset — it shrinks the body and hands the body a
    // `MediaQuery` with the bottom inset already removed. The height I was subtracting had been
    // subtracted for me, and the box I was ignoring was the only honest number in the frame.
    //
    // `LayoutBuilder` reads that box directly, and `Flexible` gives the list whatever the header leaves
    // rather than a fraction anyone has to reason about. No arithmetic, so nothing to get wrong.
    return LayoutBuilder(
      builder: (context, constraints) {
        final header = <Widget>[
          DateText(dateKey, style: DateTextStyle.full),
          const SizedBox(height: AlayaSpacing.sm),
        ];

        final body = events.when(
          loading: () => LoadingState(label: strings.calendarLoadingDay),
          error: (error, stack) => ErrorState(
            title: strings.calendarDayErrorTitle,
            body: error.toString(),
            retryLabel: strings.calendarRetry,
            onRetry: () => ref.invalidate(dayEventsProvider(dateKey)),
          ),
          data: (list) => list.isEmpty
              ? EmptyState(
                  title: strings.calendarDayEmptyTitle,
                  body: strings.calendarDayEmptyBody,
                  icon: Icons.event_available_outlined,
                )
              : CalendarEventList(
                  events: list,
                  // Close the sheet before the push, or the record opens behind it.
                  onNavigate: () => Navigator.of(context).pop(),
                ),
        );

        // Unbounded is legitimate — a sheet host may let its content decide the height — and `Flexible`
        // asserts there, so it only appears when there is a box to divide.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...header,
            if (constraints.hasBoundedHeight) Flexible(child: body) else body,
          ],
        );
      },
    );
  }
}
