import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/recurring_occurrence.dart';
import 'package:alaya/domain/entities/recurring_template.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// A template paired with its outstanding occurrence, for the due list.
class RecurringDue {
  /// Creates a due entry.
  const RecurringDue({required this.template, this.occurrence});

  /// The template.
  final RecurringTemplate template;

  /// Its outstanding occurrence, or null when none has been materialised yet.
  final RecurringOccurrence? occurrence;

  /// True when an occurrence exists and its date has passed as of [today].
  ///
  /// Derived here rather than read from a column — `v_recurring_due` has no `is_overdue` field, and
  /// deliberately so (ARCH_2 §12.2).
  bool isOverdue(DateKey today) => occurrence?.isOverdue(today) ?? false;
}

/// Reads and writes recurring templates and their occurrences.
abstract interface class RecurringRepository {
  /// Emits every active template, paused included.
  Stream<List<RecurringTemplate>> watchAllTemplates();

  /// Emits active templates in [direction] — the split that lets salary share the system with bills
  /// (anomaly A27).
  Stream<List<RecurringTemplate>> watchTemplatesByDirection(RecurringDirection direction);

  /// Emits the due list: unpaused templates with their outstanding occurrence.
  Stream<List<RecurringDue>> watchDue();

  /// Reads one template by id, soft-deleted ones included.
  Future<RecurringTemplate?> templateById(String id);

  /// Emits templates linked to [assetId] — the service-provider salary case.
  Stream<List<RecurringTemplate>> watchTemplatesForAsset(String assetId);

  /// Creates or updates a template.
  ///
  /// Fails with a [ValidationFailure] when the interval or anchor is incoherent — a monthly template
  /// needs a day-of-month, a weekly one a weekday. Never rewrites the anchor to a clamped value:
  /// a bill anchored on the 31st must stay anchored on the 31st (anomaly A13).
  Future<Result<RecurringTemplate, Failure>> saveTemplate(RecurringTemplate template);

  /// Pauses or resumes a template.
  Future<Result<void, Failure>> setTemplatePaused({
    required String id,
    required bool isPaused,
  });

  /// Soft-deletes a template. Settled occurrences and their transactions survive (ARCH_3 §4.1).
  Future<Result<void, Failure>> deleteTemplate(String id);

  /// Emits the occurrences of [templateId], newest due date first — the payment history.
  Stream<List<RecurringOccurrence>> watchOccurrences(String templateId);

  /// Emits occurrences due within `[from, to]`, for the calendar.
  Stream<List<RecurringOccurrence>> watchOccurrencesInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Materialises every occurrence now due up to [asOf], and returns how many were created.
  ///
  /// **Creates no money.** Every materialised occurrence is `due`; only [payOccurrence] settles one,
  /// and only from an explicit user tap. An app unopened for three months produces three due rows
  /// and zero transactions (anomaly A14). Idempotent — running it twice creates nothing the second
  /// time.
  Future<Result<int, Failure>> materialiseUpTo(DateKey asOf);

  /// Settles [occurrenceId] by creating the matching transaction.
  ///
  /// [amount] may differ from the template's default; the actual figure is recorded on the
  /// occurrence and the template's expectation is left alone (anomaly A29). [direction] decides
  /// whether a withdrawal or a deposit is created.
  Future<Result<Transaction, Failure>> payOccurrence({
    required String occurrenceId,
    required Money amount,
    required DateKey paidOn,
    required String accountId,
    String? paymentMethodId,
  });

  /// Marks [occurrenceId] deliberately skipped.
  Future<Result<void, Failure>> skipOccurrence({
    required String occurrenceId,
    String? note,
  });

  /// Returns [occurrenceId] to due when the transaction that settled it is deleted, so the
  /// obligation reappears rather than staying silently marked paid.
  Future<Result<void, Failure>> unsettleOccurrence(String occurrenceId);
}