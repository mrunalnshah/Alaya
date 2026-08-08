import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';

/// One occurrence a materialisation pass would create.
class PlannedOccurrence {
  /// Creates a planned occurrence.
  const PlannedOccurrence({required this.templateId, required this.dueDateKey});

  /// The template it belongs to.
  final String templateId;

  /// The civil date it is due on.
  final DateKey dueDateKey;
}

/// What one template's materialisation pass produced.
class MaterialisationPlan {
  /// Creates a plan.
  const MaterialisationPlan({
    required this.templateId,
    required this.occurrences,
    required this.nextDueDateKey,
    required this.stoppedAtSafetyBound,
  });

  /// The template.
  final String templateId;

  /// The occurrences to create, oldest first. **Every one is `due`** — never paid.
  final List<PlannedOccurrence> occurrences;

  /// Where `nextDueDateKey` should be left afterwards.
  final DateKey nextDueDateKey;

  /// True when the pass hit [RecurringEngine.maxOccurrencesPerPass] rather than reaching the target
  /// date, which means the template is almost certainly misconfigured.
  final bool stoppedAtSafetyBound;

  /// True when nothing needs writing.
  bool get isEmpty => occurrences.isEmpty;
}

/// The transaction shape settling an occurrence should create.
///
/// Returned rather than written, so the caller commits it through `TransactionRepository` and
/// inherits its shape validation and `monthKey` derivation instead of this service reimplementing
/// them.
class SettlementIntent {
  /// Creates an intent.
  const SettlementIntent({
    required this.kind,
    required this.subtype,
    required this.amount,
    required this.dateKey,
    required this.fromAccountId,
    required this.toAccountId,
    required this.templateId,
    required this.occurrenceId,
    this.payeeId,
    this.tagId,
    this.note,
  });

  /// Withdrawal for an outflow, deposit for an inflow.
  final TransactionKind kind;

  /// The analytics bucket.
  final TransactionSubtype subtype;

  /// The amount actually paid, which may differ from the template's default.
  final Money amount;

  /// The civil date it was paid on.
  final DateKey dateKey;

  /// Source account — set for an outflow, null for an inflow.
  final String? fromAccountId;

  /// Destination account — set for an inflow, null for an outflow.
  final String? toAccountId;

  /// The template being settled.
  final String templateId;

  /// The occurrence being settled.
  final String occurrenceId;

  /// The counterparty, carried from the template.
  final String? payeeId;

  /// The tag to apply, carried from the template.
  final String? tagId;

  /// The note to put on the transaction.
  final String? note;
}

/// Computes recurring schedules: the next due date, what to materialise, and what settling implies.
///
/// **Pure.** No clock, no database — every method takes the dates it needs. That is what makes the
/// month-end clamp testable against a fixed calendar rather than against whenever the suite happens
/// to run.
///
/// Phase 3D held `nextDue` and the materialisation loop inside `RecurringRepositoryImpl`. They live
/// here now for one definition, consolidated the same way Phase 4A consolidated the currency
/// cross-rate.
final class RecurringEngine {
  /// Creates the engine.
  const RecurringEngine();

  /// How many occurrences one pass will create per template before stopping.
  ///
  /// Twenty years of monthly, or eight months of daily, is past any honest backlog. Beyond it the
  /// template is misconfigured, and a device left unopened for two years should not materialise 700
  /// rows inside the startup path. The bound engages instead, and [MaterialisationPlan] says so.
  static const int maxOccurrencesPerPass = 240;

  /// The next due date after [from], per [template]'s interval.
  ///
  /// Day and week intervals are plain day arithmetic. Month and year intervals do calendar
  /// arithmetic and then clamp **the stored anchor** into the target month's real length — never the
  /// current day, which may itself already be clamped.
  ///
  /// That distinction is the whole of anomaly A13. A bill anchored on the 31st renders as the 28th in
  /// February and returns to the 31st in March. Advancing from the clamped 28th instead would walk it
  /// permanently backwards after a single February, and no later month would ever recover it.
  DateKey nextDue({
    required DateKey from,
    required RecurringTemplate template,
  }) {
    final count = template.intervalCount;
    switch (template.intervalUnit) {
      case RecurringIntervalUnit.day:
        return from.addDays(count);
      case RecurringIntervalUnit.week:
        return from.addDays(7 * count);
      case RecurringIntervalUnit.month:
        final total = from.year * 12 + (from.month - 1) + count;
        final year = total ~/ 12;
        final month = total % 12 + 1;
        return DateKey.fromYmd(
          year,
          month,
          clampDayOfMonth(template.anchorDayOfMonth ?? from.day, year, month),
        );
      case RecurringIntervalUnit.year:
        final year = from.year + count;
        return DateKey.fromYmd(
          year,
          from.month,
          clampDayOfMonth(
            template.anchorDayOfMonth ?? from.day,
            year,
            from.month,
          ),
        );
    }
  }

  /// [day] limited to the last real day of `year-month`.
  ///
  /// Day zero of the following month is the last day of this one, which resolves February in both
  /// leap and non-leap years without a lookup table.
  int clampDayOfMonth(int day, int year, int month) {
    final lastDay = DateTime.utc(year, month + 1, 0).day;
    return day < lastDay ? day : lastDay;
  }

  /// Plans every occurrence [template] owes up to and including [asOf].
  ///
  /// **Creates no money.** Every planned occurrence is `due`; only an explicit user tap settles one.
  /// An app unopened for three months plans three occurrences and zero transactions (anomaly A14).
  ///
  /// [alreadyMaterialised] makes the pass idempotent: dates already present are skipped while the
  /// cursor still advances past them, so running twice plans nothing the second time and leaves
  /// `nextDueDateKey` in the same place either way.
  MaterialisationPlan planMaterialisation({
    required RecurringTemplate template,
    required DateKey asOf,
    Iterable<DateKey> alreadyMaterialised = const [],
  }) {
    final existing = alreadyMaterialised.map((d) => d.value).toSet();
    final planned = <PlannedOccurrence>[];
    var cursor = template.nextDueDateKey;
    var guard = 0;
    var hitBound = false;

    while (!cursor.isAfter(asOf)) {
      if (guard >= maxOccurrencesPerPass) {
        hitBound = true;
        break;
      }
      guard++;

      final end = template.endDateKey;
      if (end != null && cursor.isAfter(end)) break;

      if (!existing.contains(cursor.value)) {
        planned.add(
          PlannedOccurrence(templateId: template.id, dueDateKey: cursor),
        );
      }
      cursor = nextDue(from: cursor, template: template);
    }

    return MaterialisationPlan(
      templateId: template.id,
      occurrences: planned,
      nextDueDateKey: cursor,
      stoppedAtSafetyBound: hitBound,
    );
  }

  /// Whether [template] should be materialising at all as of [asOf].
  bool isActive({required RecurringTemplate template, required DateKey asOf}) =>
      template.isActiveAsOf(asOf);

  /// What settling [occurrence] implies, without writing anything.
  ///
  /// [template]'s `direction` decides the kind: an outflow settles by taking money out, an inflow by
  /// putting it in. That single field is what lets salary share the recurring system with bills
  /// rather than needing a second, parallel one (anomaly A27).
  ///
  /// [amount] is the amount **actually** paid and is recorded on the occurrence by the caller. The
  /// template's default is never touched — paying ₹520 against a ₹499 subscription records ₹520 and
  /// leaves ₹499 as the expectation, so analytics uses actuals without corrupting the schedule
  /// (anomaly A29).
  Result<SettlementIntent, Failure> planSettlement({
    required RecurringTemplate template,
    required RecurringOccurrence occurrence,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
  }) {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The amount paid must be greater than zero.',
          field: 'amount',
        ),
      );
    }
    if (occurrence.status != RecurringOccurrenceStatus.due) {
      return Result.failure(
        BusinessRuleFailure(
          'This occurrence is already ${occurrence.status.name}.',
          rule: 'occurrenceNotDue',
        ),
      );
    }
    if (occurrence.templateId != template.id) {
      return const Result.failure(
        ValidationFailure(
          'That occurrence belongs to a different template.',
          field: 'occurrence',
        ),
      );
    }
    if (amount.currencyCode != template.defaultAmount.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting another would store the number against the wrong
      // code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${template.defaultAmount.currencyCode}, so the payment cannot be '
          'in ${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    final isOutflow = template.direction == RecurringDirection.outflow;
    return Result.ok(
      SettlementIntent(
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow
            ? TransactionSubtype.bill
            : TransactionSubtype.salaryIn,
        amount: amount,
        dateKey: paidOn,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        templateId: template.id,
        occurrenceId: occurrence.id,
        payeeId: template.payeeId,
        tagId: template.tagId,
        note: template.name,
      ),
    );
  }

  /// Validates skipping [occurrence].
  ///
  /// A settled occurrence cannot be skipped: the money already moved, and marking it skipped would
  /// leave a transaction with nothing explaining it. Unsettle it first.
  Result<void, Failure> planSkip(RecurringOccurrence occurrence) {
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    return const Result.ok(null);
  }

  /// Whether [occurrence] is overdue as of [today].
  ///
  /// Derived, never stored — which is why `v_recurring_due` has no `is_overdue` column
  /// (ARCH_2 §12.2).
  bool isOverdue({
    required RecurringOccurrence occurrence,
    required DateKey today,
  }) => occurrence.isOverdue(today);
}
