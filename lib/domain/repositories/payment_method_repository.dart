import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/domain/entities/payment_method.dart';

/// Reads and writes payment methods.
abstract interface class PaymentMethodRepository {
  /// Emits every active payment method in display order.
  Stream<List<PaymentMethod>> watchAll();

  /// Reads one by id, soft-deleted ones included, so history can render a name.
  Future<PaymentMethod?> byId(String id);

  /// Creates or updates a payment method.
  Future<Result<PaymentMethod, Failure>> save(PaymentMethod method);

  /// Deletes a user-created payment method. Fails for a system one, or when a live transaction
  /// still references it.
  Future<Result<void, Failure>> delete(String id);
}