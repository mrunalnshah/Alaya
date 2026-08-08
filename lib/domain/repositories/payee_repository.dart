import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/payee.dart';

/// Reads and writes payees.
abstract interface class PayeeRepository {
  /// Emits every active payee, alphabetically.
  Stream<List<Payee>> watchAll();

  /// Emits active payees whose name matches [term], for the picker's search field.
  Stream<List<Payee>> watchMatching(String term);

  /// Reads one by id, soft-deleted ones included, so history can render a name.
  Future<Payee?> byId(String id);

  /// Reads the active payee with this normalized name, for the merge-or-create decision.
  Future<Payee?> byNormalizedName(String normalizedName);

  /// Creates or updates a payee.
  ///
  /// Fails with a [ConflictFailure] when another active payee already has the same normalized
  /// name.
  Future<Result<Payee, Failure>> save(Payee payee);

  /// Soft-deletes a payee. Existing transactions keep their link so history stays readable.
  Future<Result<void, Failure>> delete(String id);
}