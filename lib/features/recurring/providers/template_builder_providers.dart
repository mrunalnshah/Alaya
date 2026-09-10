/// View-model state for the recurring template builder (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';
import 'package:alaya/features/recurring/providers/template_list_providers.dart';
import 'package:alaya/features/recurring/state/template_builder_state.dart';
import 'package:alaya/shared/widgets/frequency_preview.dart';

/// Accounts the pay sheet may default to.
final builderAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The home currency, so an amount is never denominated in a guess.
final builderCurrencyProvider = FutureProvider.autoDispose<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// The home currency's decimal digits (ARCH_1 §4.1).
final builderDecimalDigitsProvider = FutureProvider.autoDispose<int>((
  ref,
) async {
  final code = await ref.watch(builderCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The builder for one template, or for a new one when the argument is null.
final templateBuilderProvider = NotifierProvider.autoDispose
    .family<TemplateBuilderNotifier, AsyncValue<TemplateBuilderState>, String?>(
      TemplateBuilderNotifier.new,
    );

/// The next three dates the current frequency would land on.
///
/// **Walked through `RecurringEngine.nextDue`, the same method materialisation uses.** A second copy
/// of the clamp here would let the preview and the written occurrences disagree, which is the one
/// thing this preview exists to prevent (anomaly A13).
final previewProvider = Provider.autoDispose.family<List<PreviewedDate>, String?>((
  ref,
  editorId,
) {
  final state = ref.watch(templateBuilderProvider(editorId)).valueOrNull;
  if (state == null || !state.isComplete) return const [];
  final engine = ref.watch(recurringEngineProvider);
  final template = state.toTemplate(
    newId: 'preview',
    normalizedName: 'preview',
    nextDue: state.startDateKey,
  );

  final dates = <PreviewedDate>[];
  var cursor = state.startDateKey;
  final end = state.endDateKey;
  final anchor = state.anchorDayOfMonth;
  while (dates.length < 3) {
    if (end != null && cursor.isAfter(end)) break;
    dates.add(
      PreviewedDate(
        dateKey: cursor,
        // A clamp is visible exactly when the anchor could not be reached this month. Only a monthly
        // or yearly interval anchors to a day, so a weekly template never reports one.
        clamped: anchor != null && state.needsDayAnchor && cursor.day != anchor,
      ),
    );
    cursor = engine.nextDue(from: cursor, template: template);
  }
  return dates;
});

/// Loads, edits and saves one recurring template.
class TemplateBuilderNotifier
    extends
        AutoDisposeFamilyNotifier<AsyncValue<TemplateBuilderState>, String?> {
  @override
  AsyncValue<TemplateBuilderState> build(String? arg) {
    // A new template needs nothing fetched beyond the currency, so it does not flash a skeleton for a
    // form it could have shown. Assigning state from a synchronous path inside `build` is what
    // Riverpod refuses, so the load is always awaited.
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      if (id == null) {
        final today = ref.read(clockProvider).today();
        // A draft another module prepared, if one is waiting. `take()` clears it, so it is applied
        // exactly once and a stale one cannot ambush the next blank builder.
        final draft = ref.read(templateDraftProvider.notifier).take();
        state = AsyncValue.data(
          TemplateBuilderState(
            currencyCode: code,
            startDateKey: today,
            anchorDayOfMonth: today.day,
            name: draft?.name ?? '',
            amount: draft?.amount,
          ),
        );
        return;
      }
      final template = await ref
          .read(recurringRepositoryProvider)
          .templateById(id);
      if (template == null) {
        state = AsyncValue.error(
          StateError('Recurring template $id not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(TemplateBuilderState.fromTemplate(template));
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TemplateBuilderState Function(TemplateBuilderState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Sets the name.
  void setName(String name) =>
      _edit((s) => s.copyWith(name: name, clearIssue: true));

  /// Sets bill, subscription, rent or salary.
  ///
  /// Salary implies an inflow, and setting it also flips the direction — a salary rendered as a
  /// negative bill is the §7.2 row this module exists to close, and making the user set both is how
  /// that mistake gets made.
  void setKind(RecurringKind kind) => _edit(
    (s) => s.copyWith(
      kind: kind,
      direction: kind == RecurringKind.salary
          ? RecurringDirection.inflow
          : s.direction,
    ),
  );

  /// Sets whether money leaves or arrives.
  void setDirection(RecurringDirection direction) =>
      _edit((s) => s.copyWith(direction: direction));

  /// Sets the usual amount.
  void setAmount(Money? amount) =>
      _edit((s) => s.copyWith(amount: amount, clearIssue: true));

  /// Sets the interval unit, and drops an anchor the new unit cannot use.
  void setIntervalUnit(RecurringIntervalUnit unit) => _edit((s) {
    final anchored =
        unit == RecurringIntervalUnit.month ||
        unit == RecurringIntervalUnit.year;
    return s.copyWith(
      intervalUnit: unit,
      anchorDayOfMonth: anchored
          ? (s.anchorDayOfMonth ?? s.startDateKey.day)
          : null,
      clearAnchor: !anchored,
      clearIssue: true,
    );
  });

  /// Sets how many units make up one interval.
  void setIntervalCount(int count) =>
      _edit((s) => s.copyWith(intervalCount: count < 1 ? 1 : count));

  /// Sets the day of the month the schedule anchors to.
  void setAnchorDay(int? day) => _edit(
    (s) => day == null
        ? s.copyWith(clearAnchor: true)
        : s.copyWith(anchorDayOfMonth: day, clearIssue: true),
  );

  /// Sets when it starts, carrying the day anchor with it unless the user has chosen one.
  ///
  /// **The anchor followed nothing before, and that was a due-date bug.** The builder seeds the anchor
  /// from today; moving the start date to the 15th left it on today's day, so the first occurrence
  /// landed on the 15th and every one after it on some unrelated day. The anchor only stops following
  /// once `setAnchorDay` is called, which is the user saying they meant a different day.
  void setStartDate(DateKey date) => _edit((s) {
    final follows =
        s.anchorDayOfMonth == null || s.anchorDayOfMonth == s.startDateKey.day;
    return s.copyWith(
      startDateKey: date,
      anchorDayOfMonth: follows && s.needsDayAnchor
          ? date.day
          : s.anchorDayOfMonth,
    );
  });

  /// Sets when it stops, or clears the end date.
  void setEndDate(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearEndDate: true)
        : s.copyWith(endDateKey: date),
  );

  /// Sets which account the pay sheet defaults to.
  void setAccount(String? accountId) =>
      _edit((s) => s.copyWith(accountId: accountId));

  /// Sets how many days of warning to give.
  void setRemindDaysBefore(int days) =>
      _edit((s) => s.copyWith(remindDaysBefore: days < 0 ? 0 : days));

  /// Turns reminders on or off.
  void toggleRemind() => _edit((s) => s.copyWith(autoRemind: !s.autoRemind));

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Saves the template, returning its id on success and null on rejection or failure.
  ///
  /// Every refusal is named before the repository sees it, and a rejection carries the repository's own
  /// message — the builder has three ways to be incomplete and "something went wrong" distinguishes
  /// none of them (Law U9).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.name.trim().isEmpty) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.nameMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (!(current.amount?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.amountMissing,
          shakeTrigger: s.shakeTrigger + 1,
        ),
      );
      return null;
    }
    if (current.needsDayAnchor && current.anchorDayOfMonth == null) {
      _edit((s) => s.copyWith(issue: TemplateSaveIssue.anchorMissing));
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearIssue: true));
    try {
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final saved = await ref
          .read(recurringRepositoryProvider)
          .saveTemplate(
            current.toTemplate(
              newId: id,
              normalizedName: ref
                  .read(normalizerProvider)
                  .normalize(current.name.trim()),
              // A new template's first occurrence is its start date, not one interval after it.
              // Editing leaves the cursor alone: materialisation owns it, and resetting it would
              // resurrect occurrences already paid.
              nextDue: current.isEditing
                  ? (await ref
                                .read(recurringRepositoryProvider)
                                .templateById(id))
                            ?.nextDueDateKey ??
                        current.startDateKey
                  : current.startDateKey,
            ),
          );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: TemplateSaveIssue.rejected,
            rejection: failure.message,
          ),
        );
        return null;
      }
      // Materialisation runs once per list mount, so a template created afterwards would show no
      // occurrence until the next launch. Invalidating it here is what makes the first due row appear
      // immediately rather than looking like nothing happened.
      ref.invalidate(materialiseProvider);
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Recurring template save failed',
            level: LogLevel.error,
            tag: 'recurring.builder',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: TemplateSaveIssue.rejected,
          rejection: error.toString(),
        ),
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }
}
