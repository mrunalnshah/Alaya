import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/daos/recurring_occurrence_dao.dart';
import 'package:alaya/data/daos/recurring_template_dao.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/repositories/mappers/schedule_mappers.dart';
import 'package:alaya/data/repositories/write_timestamps.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/repositories/recurring_repository.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';
import 'package:alaya/domain/services/recurring_engine.dart';

/// `RecurringRepository` backed by `RecurringTemplateDao` and `RecurringOccurrenceDao`.
///
/// Depends on `TransactionRepository` — the domain interface — so [payOccurrence] reuses its shape
/// validation and `monthKey` derivation rather than reimplementing them.
final class RecurringRepositoryImpl implements RecurringRepository {
  /// Creates the repository.
  const RecurringRepositoryImpl(
    this._templateDao,
    this._occurrenceDao,
    this._transactions,
    this._uids,
    this._clock,
  );

  final RecurringTemplateDao _templateDao;
  final RecurringOccurrenceDao _occurrenceDao;
  final TransactionRepository _transactions;
  final UidGenerator _uids;
  final Clock _clock;

  /// Owns the interval arithmetic, the month-end clamp and the materialisation bound.
  static const RecurringEngine _engine = RecurringEngine();

  // ── templates ─────────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringTemplate>> watchAllTemplates() => _templateDao
      .watchAll()
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(
    RecurringDirection direction,
  ) => _templateDao
      .watchByDirection(direction)
      .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId) =>
      _templateDao
          .watchForAsset(assetId)
          .map((rows) => rows.map((r) => r.toEntity()).toList());

  @override
  Future<RecurringTemplate?> templateById(String id) async =>
      (await _templateDao.byIdIncludingDeleted(id))?.toEntity();

  /// Emits the due list: unpaused templates paired with their outstanding occurrence.
  ///
  /// Built from two typed queries rather than from `v_recurring_due`, deliberately. That view is a
  /// presentation-shaped projection of 18 columns; a full `RecurringTemplate` needs nine more
  /// (`normalizedName`, `startDateKey`, `isPaused`, the three anchors, `endDateKey`,
  /// `linkedAssetId`, `note`) and a full `RecurringOccurrence` four more (`paidTransactionId`,
  /// `paidAmount`, `paidDateKey`, `note`). Widening the view to carry all thirteen — with `note`
  /// needing an alias on both sides — would leave it a bare join whose only remaining value is a
  /// filter these two queries already express. Two queries, no per-template round trip.
  ///
  /// `RecurringTemplateDao.watchDue()` still reads the view and is the right call for a caller
  /// that only needs the projection, such as a dashboard count.
  @override
  Stream<List<RecurringDue>> watchDue() {
    return _templateDao.watchAll().asyncMap((templateRows) async {
      final today = _clock.today();
      // Materialisation never runs ahead of today, so every `due` occurrence has a due date on or
      // before it — this is the whole outstanding set, in one query rather than one per template.
      final outstanding = await _occurrenceDao.outstandingAsOf(today);
      final byTemplate = <String, RecurringOccurrenceRow>{};
      for (final row in outstanding) {
        final existing = byTemplate[row.templateId];
        // Oldest outstanding occurrence wins: that is the one the user owes next.
        if (existing == null || row.dueDateKey < existing.dueDateKey) {
          byTemplate[row.templateId] = row;
        }
      }

      final due = <RecurringDue>[];
      for (final templateRow in templateRows) {
        if (templateRow.isPaused) continue;
        final template = templateRow.toEntity();
        if (template.hasEnded(today)) continue;
        final occurrenceRow = byTemplate[templateRow.id];
        due.add(
          RecurringDue(
            template: template,
            occurrence: occurrenceRow?.toEntity(templateRow.currencyCode),
          ),
        );
      }
      due.sort(
        (a, b) => DateKey.compare(
          a.template.nextDueDateKey,
          b.template.nextDueDateKey,
        ),
      );
      return due;
    });
  }

  @override
  Future<Result<RecurringTemplate, Failure>> saveTemplate(
    RecurringTemplate template,
  ) async {
    final validation = _validateTemplate(template);
    if (validation != null) return Result.failure(validation);

    final existing = await _templateDao.byIdIncludingDeleted(template.id);
    if (existing == null) {
      final duplicate = await _templateDao.byNormalizedName(
        template.normalizedName,
      );
      if (duplicate != null) {
        return Result.failure(
          ConflictFailure(
            'A recurring template named "${template.name}" already exists.',
          ),
        );
      }
    }

    final stamps = WriteTimestamps.resolve(
      existingCreatedAt: existing?.createdAt,
      clock: _clock,
    );
    await _templateDao.upsert(
      recurringTemplateToCompanion(
        template,
        createdAt: stamps.createdAt,
        updatedAt: stamps.updatedAt,
      ),
    );
    return Result.ok(template);
  }

  @override
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  }) async {
    final existing = await _templateDao.byIdIncludingDeleted(id);
    if (existing == null || existing.deletedAt != null) {
      return Result.failure(
        NotFoundFailure('Recurring template not found.', id: id),
      );
    }
    await _templateDao.setPaused(
      id: id,
      isPaused: isPaused,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> deleteTemplate(String id) async {
    // Soft, and it cascades to nothing. Paid occurrences and the transactions they created survive
    // untouched (ARCH_3 §4.1): deleting a subscription does not un-pay last month's bill, and the
    // money that left the account really left it.
    await _templateDao.softDelete(id: id, nowUtcMillis: _clock.nowUtcMillis());
    return const Result.ok(null);
  }

  // ── occurrences ───────────────────────────────────────────────────────────────────────

  @override
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId) {
    return _occurrenceDao.watchForTemplate(templateId).asyncMap((rows) async {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template == null) return const <RecurringOccurrence>[];
      return rows.map((r) => r.toEntity(template.currencyCode)).toList();
    });
  }

  @override
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  }) {
    return _occurrenceDao
        .watchDueInRange(from: from, to: to)
        .asyncMap(_mapWithTemplateCurrency);
  }

  @override
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf) async {
    final templates = await _templateDao.needingMaterialisation(asOf);
    final now = _clock.nowUtcMillis();
    var created = 0;

    for (final row in templates) {
      final template = row.toEntity();
      var cursor = template.nextDueDateKey;
      var guard = 0;

      while (!cursor.isAfter(asOf) &&
          guard < RecurringEngine.maxOccurrencesPerPass) {
        guard++;
        final end = template.endDateKey;
        if (end != null && cursor.isAfter(end)) break;

        // Idempotent: the DAO reads before inserting, because `idx_recurring_occ` is a partial
        // unique index and SQLite rejects a partial index as an ON CONFLICT target. Running this
        // twice creates nothing the second time.
        await _occurrenceDao.upsertForDue(
          id: _uids.generate(),
          templateId: template.id,
          dueDateKey: cursor,
          nowUtcMillis: now,
        );
        created++;
        cursor = _advance(cursor, template);
      }

      if (cursor != template.nextDueDateKey) {
        await _templateDao.advanceNextDue(
          id: template.id,
          nextDueDateKey: cursor,
          nowUtcMillis: now,
        );
      }
    }
    // Every occurrence created here is `due`. Nothing is paid, and no transaction exists — money is
    // only ever created by an explicit user tap (anomaly A14). An app unopened for three months
    // produces three due rows and zero transactions.
    return Result.ok(created);
  }

  @override
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  }) async {
    if (!amount.isPositive) {
      return const Result.failure(
        ValidationFailure(
          'The amount paid must be greater than zero.',
          field: 'amount',
        ),
      );
    }

    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
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

    final templateRow = await _templateDao.byIdIncludingDeleted(
      occurrence.templateId,
    );
    if (templateRow == null) {
      return Result.failure(
        NotFoundFailure(
          'The template this occurrence belongs to does not exist.',
          id: occurrence.templateId,
        ),
      );
    }
    if (amount.currencyCode != templateRow.currencyCode) {
      // `recurring_occurrences` has no currency column: a paid amount is denominated in its
      // template's currency (ARCH_2 §7). Accepting a different one would store the number against
      // the wrong code on read — Law L1's pairing rule, broken silently.
      return Result.failure(
        ValidationFailure(
          'This template is in ${templateRow.currencyCode}, so the payment cannot be in '
          '${amount.currencyCode}.',
          field: 'amount',
        ),
      );
    }

    // `direction` decides the kind: an outflow settles by taking money out, an inflow by putting it
    // in. This is what lets salary share the recurring system with bills instead of needing a
    // second, parallel one (anomaly A27).
    final isOutflow = templateRow.direction == RecurringDirection.outflow;
    final created = await _transactions.create(
      transaction: Transaction(
        id: _uids.generate(),
        kind: isOutflow ? TransactionKind.withdrawal : TransactionKind.deposit,
        subtype: isOutflow
            ? TransactionSubtype.bill
            : TransactionSubtype.salaryIn,
        // **Now when the date is today, midnight only when it is not.**
        //
        // The ledger orders by `dateKey DESC, occurredAt DESC`. Stamping midnight unconditionally sent
        // every same-day entry to the *bottom* of today's group, behind hand-entered expenses stamped
        // with the real clock — so two records made seconds apart appeared in an order with no
        // relationship to anything the user did.
        //
        // Midnight stays right for a back-dated payment: nobody knows what time last Tuesday's plumber
        // came, and inventing one would be a worse lie than admitting the day is all we have.
        occurredAtUtc: paidOn == _clock.today()
            ? _clock.now().toUtc()
            : paidOn.toUtcMidnight(),
        dateKey: paidOn,
        originalAmount: amount,
        needsReview: false,
        fromAccountId: isOutflow ? accountId : null,
        toAccountId: isOutflow ? null : accountId,
        paymentMethodId: paymentMethodId,
        payeeId: templateRow.payeeId,
        note: templateRow.name,
        recurringTemplateId: templateRow.id,
        recurringOccurrenceId: occurrenceId,
      ),
      tagIds: templateRow.tagId == null ? const [] : [templateRow.tagId!],
    );
    if (created.isFailure) return Result.failure(created.failureOrNull!);
    final transaction = created.valueOrNull!;

    // The ACTUAL amount is recorded on the occurrence. The template's `defaultAmountMinor` is not
    // touched — paying ₹520 against a ₹499 subscription records ₹520 here and leaves ₹499 as the
    // template's expectation, so analytics uses actuals without corrupting the schedule
    // (anomaly A29).
    await _occurrenceDao.markPaid(
      id: occurrenceId,
      transactionId: transaction.id,
      paidAmountMinor: amount.minor,
      paidDateKey: paidOn,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return Result.ok(transaction);
  }

  @override
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  }) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
      );
    }
    if (occurrence.status == RecurringOccurrenceStatus.paid) {
      return const Result.failure(
        BusinessRuleFailure(
          'A settled occurrence cannot be skipped — unsettle it first.',
          rule: 'cannotSkipPaid',
        ),
      );
    }
    await _occurrenceDao.markSkipped(
      id: occurrenceId,
      note: note,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId) async {
    final occurrence = await _occurrenceDao.byId(occurrenceId);
    if (occurrence == null) {
      return Result.failure(
        NotFoundFailure('Occurrence not found.', id: occurrenceId),
      );
    }
    // Returns it to `due` and clears the settlement fields, so the obligation reappears rather than
    // staying silently marked paid after the transaction behind it is gone. The transaction itself
    // is not touched — this is called *because* it was deleted.
    await _occurrenceDao.unlinkDeletedTransaction(
      id: occurrenceId,
      nowUtcMillis: _clock.nowUtcMillis(),
    );
    return const Result.ok(null);
  }

  // ── interval arithmetic ───────────────────────────────────────────────────────────────

  /// Delegates to [RecurringEngine.nextDue].
  ///
  /// The interval arithmetic and the month-end anchor clamp used to live here. Phase 4B moved them
  /// into the engine so the clamp has one definition — anomaly A13 is exactly the kind of rule that
  /// must not exist twice, because the second copy is the one that walks a bill backwards.
  DateKey _advance(DateKey from, RecurringTemplate template) =>
      _engine.nextDue(from: from, template: template);

  /// Validates a template's interval and anchor coherence.
  Failure? _validateTemplate(RecurringTemplate template) {
    if (template.name.trim().isEmpty) {
      return const ValidationFailure(
        'A recurring template needs a name.',
        field: 'name',
      );
    }
    if (!template.defaultAmount.isPositive) {
      return const ValidationFailure(
        'A recurring template needs a positive default amount.',
        field: 'defaultAmount',
      );
    }
    if (template.intervalCount < 1) {
      return const ValidationFailure(
        'The interval must be at least 1.',
        field: 'intervalCount',
      );
    }
    final end = template.endDateKey;
    if (end != null && end.isBefore(template.startDateKey)) {
      return const ValidationFailure(
        'The end date cannot be before the start date.',
        field: 'endDateKey',
      );
    }

    final anchorDay = template.anchorDayOfMonth;
    if (anchorDay != null && (anchorDay < 1 || anchorDay > 31)) {
      return const ValidationFailure(
        'The day of the month must be between 1 and 31.',
        field: 'anchorDayOfMonth',
      );
    }
    final anchorWeekday = template.anchorWeekday;
    if (anchorWeekday != null && (anchorWeekday < 1 || anchorWeekday > 7)) {
      return const ValidationFailure(
        'The weekday must be between 1 (Monday) and 7 (Sunday).',
        field: 'anchorWeekday',
      );
    }
    final anchorMonth = template.anchorMonth;
    if (anchorMonth != null && (anchorMonth < 1 || anchorMonth > 12)) {
      return const ValidationFailure(
        'The month must be between 1 and 12.',
        field: 'anchorMonth',
      );
    }

    // A monthly or yearly template with no day anchor would advance from whatever day it happened
    // to land on, so a February settlement would pull every later occurrence back to the 28th
    // permanently (anomaly A13). Requiring the anchor is what makes that impossible.
    final needsDayAnchor =
        template.intervalUnit == RecurringIntervalUnit.month ||
        template.intervalUnit == RecurringIntervalUnit.year;
    if (needsDayAnchor && anchorDay == null) {
      return const ValidationFailure(
        'A monthly or yearly template needs a day of the month to anchor to.',
        field: 'anchorDayOfMonth',
      );
    }
    return null;
  }

  Future<List<RecurringOccurrence>> _mapWithTemplateCurrency(
    List<RecurringOccurrenceRow> rows,
  ) async {
    final currencies = <String, String>{};
    for (final templateId in rows.map((r) => r.templateId).toSet()) {
      final template = await _templateDao.byIdIncludingDeleted(templateId);
      if (template != null) currencies[templateId] = template.currencyCode;
    }
    return rows
        .where((r) => currencies.containsKey(r.templateId))
        .map((r) => r.toEntity(currencies[r.templateId]!))
        .toList();
  }
}
