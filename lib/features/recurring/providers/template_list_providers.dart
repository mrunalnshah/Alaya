/// View-model state for the recurring template list (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// A template with the soonest outstanding occurrence against it, if any.
class TemplateRow {
  /// Creates a row.
  const TemplateRow({required this.template, this.next});

  /// The template.
  final RecurringTemplate template;

  /// Its soonest outstanding occurrence, or null when nothing is materialised yet.
  final RecurringOccurrence? next;
}

/// One direction's worth of templates.
class TemplateGroup {
  /// Creates a group.
  const TemplateGroup({required this.direction, required this.rows});

  /// Whether these are outflows or inflows.
  final RecurringDirection direction;

  /// The rows under it.
  final List<TemplateRow> rows;
}

/// Materialises occurrences up to today, once per list mount.
///
/// **Lazy, and never automatic beyond this.** Occurrences are created up to today so the list can show
/// what is due; not one of them is paid, and no transaction exists until a user taps (anomaly A14). An
/// app unopened for three months produces three due rows and zero transactions.
final materialiseProvider = FutureProvider<int>((ref) async {
  final result = await ref
      .watch(recurringRepositoryProvider)
      .materialiseUpTo(ref.watch(clockProvider).today());
  return result.valueOrNull ?? 0;
});

/// Every template.
final templatesProvider = StreamProvider<List<RecurringTemplate>>(
  (ref) => ref.watch(recurringRepositoryProvider).watchAllTemplates(),
);

/// Outstanding occurrences for one template, soonest first.
final occurrencesProvider = StreamProvider.autoDispose
    .family<List<RecurringOccurrence>, String>(
      (ref, templateId) =>
          ref.watch(recurringRepositoryProvider).watchOccurrences(templateId),
    );

/// Templates grouped by direction, each with its soonest outstanding occurrence.
///
/// Grouped by direction rather than sorted by date because a salary and a rent bill are not two
/// entries on one list — the §7.2 row this closes is precisely that an inflow must read as income
/// rather than as a negative bill.
final templateGroupsProvider = Provider<AsyncValue<List<TemplateGroup>>>((ref) {
  // Depended on so the list cannot render before today's rows exist; its own value is not needed.
  ref.watch(materialiseProvider);
  final templates = ref.watch(templatesProvider);
  if (templates.hasError) {
    return AsyncValue.error(templates.error!, templates.stackTrace!);
  }
  final all = templates.valueOrNull;
  if (all == null) return const AsyncValue.loading();

  List<TemplateRow> rowsFor(RecurringDirection direction) =>
      [
        for (final template in all)
          if (template.direction == direction)
            TemplateRow(
              template: template,
              next: _soonestOutstanding(
                ref.watch(occurrencesProvider(template.id)).valueOrNull,
              ),
            ),
      ]..sort(
        (a, b) =>
            a.template.nextDueDateKey.compareTo(b.template.nextDueDateKey),
      );

  final outflow = rowsFor(RecurringDirection.outflow);
  final inflow = rowsFor(RecurringDirection.inflow);
  return AsyncValue.data([
    if (outflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.outflow, rows: outflow),
    if (inflow.isNotEmpty)
      TemplateGroup(direction: RecurringDirection.inflow, rows: inflow),
  ]);
});

RecurringOccurrence? _soonestOutstanding(
  List<RecurringOccurrence>? occurrences,
) {
  if (occurrences == null) return null;
  RecurringOccurrence? soonest;
  for (final occurrence in occurrences) {
    if (!occurrence.isOutstanding) continue;
    if (soonest == null || occurrence.dueDateKey.isBefore(soonest.dueDateKey)) {
      soonest = occurrence;
    }
  }
  return soonest;
}

/// How many templates have an occurrence past its due date, for the header count.
///
/// Derived from the clock through `RecurringEngine.isOverdue`, never a stored flag (ARCH_2 §12.2): a
/// flag would be wrong the moment midnight passed with the app closed.
final overdueCountProvider = Provider<int>((ref) {
  final groups = ref.watch(templateGroupsProvider).valueOrNull ?? const [];
  final engine = ref.watch(recurringEngineProvider);
  final today = ref.watch(clockProvider).today();
  var count = 0;
  for (final group in groups) {
    for (final row in group.rows) {
      final next = row.next;
      if (next == null) continue;
      if (engine.isOverdue(occurrence: next, today: today)) count++;
    }
  }
  return count;
});

/// Writes the template list performs.
final templateActionsProvider = Provider<TemplateActions>(TemplateActions.new);

/// Pauses, resumes and deletes templates.
class TemplateActions {
  /// Creates the actions.
  TemplateActions(this._ref);

  final Ref _ref;

  /// Pauses or resumes a template, returning the failure's own message or null on success.
  Future<String?> setPaused({
    required String id,
    required bool isPaused,
  }) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .setTemplatePaused(id: id, isPaused: isPaused);
    return result.failureOrNull?.message;
  }

  /// Deletes a template.
  ///
  /// Its occurrences go with it; the transactions any of them created stay, because a payment that
  /// happened happened (Law L6).
  Future<String?> delete(String id) async {
    final result = await _ref
        .read(recurringRepositoryProvider)
        .deleteTemplate(id);
    return result.failureOrNull?.message;
  }
}
