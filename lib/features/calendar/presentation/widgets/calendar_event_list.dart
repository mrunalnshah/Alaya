import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/calendar_event.dart';
import 'package:alaya/features/calendar/presentation/widgets/event_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The route for the record behind [event], or null where the feed cannot address it.
///
/// `v_calendar_events` carries `ref_type` and `ref_id` but not the parent id that three of the six
/// detail routes need — a batch route wants its item, a service record wants its asset, and a recurring
/// occurrence has no route of its own. Those land on the owning module instead. Closing it means a
/// `parent_ref_id` column on the view, which is a Phase 2A change.
String? calendarEventRoute(CalendarEvent event) => switch (event.refType) {
  'transaction' => Routes.transactionDetail(event.refId),
  'asset' => Routes.assetDetail(event.refId),
  'shoppingList' => Routes.shoppingList(event.refId),
  'inventoryBatch' => Routes.inventory,
  'serviceRecord' => Routes.services,
  'recurringOccurrence' => Routes.recurring,
  _ => null,
};

/// Calendar entries under one heading per event type, each tappable through to its record.
///
/// Shared by the inline day section and the day sheet, because the same list rendered twice is a list
/// that will disagree with itself (ARCH_4 R25).
class CalendarEventList extends ConsumerWidget {
  /// Creates the list.
  const CalendarEventList({required this.events, this.onNavigate, super.key});

  /// The entries, with severity already resolved by `CalendarAggregator`.
  final List<CalendarEvent> events;

  /// Called just before navigating away — a sheet uses it to close itself first.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final byType = <CalendarEventType, List<CalendarEvent>>{};
    for (final event in events) {
      (byType[event.type] ??= <CalendarEvent>[]).add(event);
    }

    // Declaration order rather than severity order: a reader scanning the same day twice should find
    // the same thing in the same place.
    final types = CalendarEventType.values.where(byType.containsKey).toList();

    return ListView.builder(
      shrinkWrap: true,
      itemCount: types.length,
      itemBuilder: (context, index) {
        final type = types[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(label: type.labelOf(strings)),
            for (final event in byType[type]!)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xs),
                child: _Tappable(event: event, onNavigate: onNavigate),
              ),
          ],
        );
      },
    );
  }
}

/// An event card wired to its record, or inert where the feed cannot address one.
class _Tappable extends StatelessWidget {
  const _Tappable({required this.event, this.onNavigate});

  final CalendarEvent event;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final route = calendarEventRoute(event);
    return EventCard(
      event: event,
      // The type is already the heading above this card.
      showType: false,
      onTap: route == null
          ? null
          : () {
              onNavigate?.call();
              context.push(route);
            },
    );
  }
}
