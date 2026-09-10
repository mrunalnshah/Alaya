/// View-model state for the service record editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/service/providers/asset_editor_providers.dart';
import 'package:alaya/features/service/state/service_editor_state.dart';

/// Which record an editor is pointed at. A record, so the family argument has structural equality.
typedef ServiceEditorArgs = ({String assetId, String? recordId});

/// Payment methods the expense may record, when the user cares to say.
final servicePaymentMethodsProvider =
    StreamProvider.autoDispose<List<PaymentMethod>>(
      (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
    );

/// Accounts an expense may come from.
final serviceAccountsProvider = StreamProvider.autoDispose<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// The app-wide default account, so the expense toggle rarely has to ask.
final serviceDefaultAccountProvider = FutureProvider.autoDispose<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readDefaultAccountId(),
);

/// The editor for one service record, or for a new one when `recordId` is null.
final serviceEditorProvider = NotifierProvider.autoDispose
    .family<
      ServiceEditorNotifier,
      AsyncValue<ServiceEditorState>,
      ServiceEditorArgs
    >(
      ServiceEditorNotifier.new,
    );

/// Loads, edits and saves one service record.
class ServiceEditorNotifier
    extends
        AutoDisposeFamilyNotifier<
          AsyncValue<ServiceEditorState>,
          ServiceEditorArgs
        > {
  @override
  AsyncValue<ServiceEditorState> build(ServiceEditorArgs arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(ServiceEditorArgs arg) async {
    try {
      final code =
          await ref.read(settingsRepositoryProvider).readHomeCurrencyCode() ??
          'INR';
      final recordId = arg.recordId;
      if (recordId != null) {
        final record = await ref
            .read(serviceRecordRepositoryProvider)
            .byId(recordId);
        if (record == null) {
          state = AsyncValue.error(
            StateError('Service record $recordId not found.'),
            StackTrace.current,
          );
          return;
        }
        state = AsyncValue.data(ServiceEditorState.fromRecord(record, code));
        return;
      }
      final asset = await ref.read(assetRepositoryProvider).byId(arg.assetId);
      if (asset == null) {
        state = AsyncValue.error(
          StateError('Asset ${arg.assetId} not found.'),
          StackTrace.current,
        );
        return;
      }
      state = AsyncValue.data(
        ServiceEditorState(
          assetId: arg.assetId,
          currencyCode: code,
          serviceDateKey: ref.read(clockProvider).today(),
          // A person's record is a salary payment by default, and a thing's is a service. Making the
          // user correct the obvious is how the maid case ends up filed as "inspection".
          type: asset.isServiceProvider
              ? ServiceRecordType.salaryPaid
              : ServiceRecordType.service,
          providerName: asset.primaryContactName,
          providerPhone: asset.primaryContactPhone,
          // Seeded from the asset's own interval, so recording a service also proposes the next one.
          nextDueDateKey: asset.serviceIntervalDays == null
              ? null
              : ref
                    .read(clockProvider)
                    .today()
                    .addDays(asset.serviceIntervalDays!),
          accountId: await _resolveAccount(),
          // **On by default for a new record.** A cost typed here is money that left the house, so the
          // ledger should show it without a second decision — and the account is already resolved, so
          // the common path is no extra taps at all. It stays visible and switchable, because a service
          // paid by someone else (a warranty repair, a landlord's plumber) is a real case.
          //
          // This is not anomaly A14. A14 forbids *materialisation* creating money on its own; here the
          // user typed a figure and pressed save, which is as explicit as an act gets.
          alsoRecordAsExpense: true,
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  /// The account an expense should come from when the user has not chosen one.
  ///
  /// **Two fallbacks, because one was not enough.** `readDefaultAccountId()` is null until somebody sets
  /// a default in Settings, and a null account makes `save` refuse the whole record — so a service with a
  /// cost silently could not be recorded at all. A sole selectable account is the obvious answer when
  /// there is only one, and it is information the user already gave (Law U23).
  Future<String?> _resolveAccount() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readDefaultAccountId();
    if (stored != null) return stored;
    final accounts = await ref
        .read(accountRepositoryProvider)
        .watchSelectable()
        .first;
    return accounts.length == 1 ? accounts.single.id : null;
  }

  /// Applies [change], clearing the last rejection unless told to keep it.
  ///
  /// **A rejection is shown until the user acts, then it goes.** The message is rendered as a card in the
  /// form rather than only as a snack, because a snack lasts 2.5 seconds and a refused save is worth
  /// longer than that — but a card that survives the edit which fixes it is a stale error the user has to
  /// dismiss by hand. Every setter clears it; only `save` keeps it.
  void _edit(
    ServiceEditorState Function(ServiceEditorState) change, {
    bool keepIssue = false,
  }) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = change(current);
    state = AsyncValue.data(keepIssue ? next : next.copyWith(clearIssue: true));
  }

  /// Sets what happened.
  void setType(ServiceRecordType type) => _edit((s) => s.copyWith(type: type));

  /// Sets when.
  void setServiceDate(DateKey? date) =>
      _edit((s) => date == null ? s : s.copyWith(serviceDateKey: date));

  /// Sets who did it, or who was paid.
  void setProviderName(String value) =>
      _edit((s) => s.copyWith(providerName: value));

  /// Sets their number.
  void setProviderPhone(String value) =>
      _edit((s) => s.copyWith(providerPhone: value));

  /// Sets what it cost.
  void setCost(Money? cost) => _edit(
    (s) => cost == null
        ? s.copyWith(clearCost: true, clearIssue: true)
        : s.copyWith(cost: cost, clearIssue: true),
  );

  /// Sets when the next one is due.
  void setNextDue(DateKey? date) => _edit(
    (s) => date == null
        ? s.copyWith(clearNextDue: true)
        : s.copyWith(nextDueDateKey: date),
  );

  /// Sets the free notes.
  void setNotes(String value) => _edit((s) => s.copyWith(notes: value));

  /// Turns the expense toggle on or off.
  void toggleExpense() => _edit(
    (s) => s.copyWith(
      alsoRecordAsExpense: !s.alsoRecordAsExpense,
      clearIssue: true,
    ),
  );

  /// Sets which account the expense comes from.
  void setAccount(String? accountId) =>
      _edit((s) => s.copyWith(accountId: accountId, clearIssue: true));

  /// Sets how it was paid. Never required.
  void setPaymentMethod(String? methodId) =>
      _edit((s) => s.copyWith(paymentMethodId: methodId));

  /// Saves the record, returning its id on success and null on rejection or failure.
  ///
  /// **The expense is written by the repository, in the same call.** `save(record,
  /// alsoRecordAsExpense: true, accountId: …)` writes the record and the withdrawal; nothing here does
  /// it by hand. The sequence is not atomic across aggregates, so it is ordered and idempotent instead
  /// (ARCH_4 R21) — and it is one write path, not two (Law U22).
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.alsoRecordAsExpense && !(current.cost?.isPositive ?? false)) {
      _edit(
        (s) => s.copyWith(
          issue: ServiceSaveIssue.costMissingForExpense,
          shakeTrigger: s.shakeTrigger + 1,
        ),
        keepIssue: true,
      );
      return null;
    }
    if (current.alsoRecordAsExpense && current.accountId == null) {
      _edit(
        (s) => s.copyWith(issue: ServiceSaveIssue.accountMissingForExpense),
        keepIssue: true,
      );
      return null;
    }

    _edit(
      (s) => s.copyWith(submitting: true, clearIssue: true),
      keepIssue: true,
    );
    try {
      final repository = ref.read(serviceRecordRepositoryProvider);
      final id = current.id ?? ref.read(uidGeneratorProvider).generate();
      final existing = current.isEditing ? await repository.byId(id) : null;
      final saved = await repository.save(
        current.toRecord(newId: id, existing: existing),
        alsoRecordAsExpense: current.alsoRecordAsExpense,
        accountId: current.accountId,
        paymentMethodId: current.paymentMethodId,
      );
      final failure = saved.failureOrNull;
      if (failure != null) {
        _edit(
          (s) => s.copyWith(
            issue: ServiceSaveIssue.rejected,
            rejection: failure.message,
          ),
          keepIssue: true,
        );
        return null;
      }
      _edit((s) => s.copyWith(dirty: false));
      return id;
    } on Object catch (error, stack) {
      ref
          .read(loggerProvider)
          .log(
            'Service record save failed',
            level: LogLevel.error,
            tag: 'service.recordEditor',
            error: error,
            stackTrace: stack,
          );
      _edit(
        (s) => s.copyWith(
          issue: ServiceSaveIssue.rejected,
          rejection: error.toString(),
        ),
        keepIssue: true,
      );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false), keepIssue: true);
    }
  }
}
