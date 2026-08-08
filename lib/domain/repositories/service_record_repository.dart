import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/service_record.dart';

/// Reads and writes service records.
abstract interface class ServiceRecordRepository {
  /// Emits the records for [assetId], most recent first — the service timeline.
  Stream<List<ServiceRecord>> watchForAsset(String assetId);

  /// Emits the records of [type] for [assetId] — e.g. only salary payments, which is the payment log
  /// for a service provider.
  Stream<List<ServiceRecord>> watchForAssetByType({
    required String assetId,
    required ServiceRecordType type,
  });

  /// Emits records whose scheduled next service falls within `[from, to]`.
  Stream<List<ServiceRecord>> watchWithNextDueInRange({
    required DateKey from,
    required DateKey to,
  });

  /// Reads one record by id.
  Future<ServiceRecord?> byId(String id);

  /// Reads the most recent record for [assetId], for the "last serviced" line.
  Future<ServiceRecord?> mostRecentForAsset(String assetId);

  /// Totals lifetime service cost for [assetId], **per currency** (ARCH_3 §5.1 query 19).
  ///
  /// A map rather than one figure: cost currency is per record, so an asset serviced in two
  /// countries has costs in two currencies and adding them would be anomaly A34.
  Future<Map<String, Money>> lifetimeCostByCurrency(String assetId);

  /// Creates or updates a record.
  ///
  /// When [alsoRecordAsExpense] is true and the record has a cost, a matching withdrawal is created
  /// and linked in the same transaction, so the service history and the expense cannot disagree
  /// about whether the money moved.
  /// [paymentMethodId] is carried to the expense, never onto the record.
  ///
  /// How a service was paid for is a property of the payment, not of the work done — the same boiler
  /// service settled in cash one year and by card the next is one kind of service. Putting it on
  /// `ServiceRecord` would duplicate a column `transactions` already owns, and the two would drift.
  /// Optional throughout: an account says where the money came from and is required for an expense; a
  /// method says how, and plenty of people never record it.
  Future<Result<ServiceRecord, Failure>> save(
    ServiceRecord record, {
    bool alsoRecordAsExpense,
    String? accountId,
    String? paymentMethodId,
  });

  /// Clears the link to a deleted transaction, leaving the record itself intact — the repair happened
  /// whether or not the expense row survives.
  Future<Result<void, Failure>> unlinkDeletedTransaction(String id);

  /// Soft-deletes a record.
  Future<Result<void, Failure>> delete(String id);
}
