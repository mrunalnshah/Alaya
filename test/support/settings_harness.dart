/// Shared scaffolding for the 8A widget tests.
///
/// **The three fakes here are why `AppLock`, `BiometricGate` and `DataTransferPort` exist.** `PinService` and
/// `BackupService` are `final class`, so neither can be implemented outside its own library — and
/// `flutter_secure_storage` and `local_auth` both need a platform channel. Without the contracts, not one test
/// in this phase could have been written, which is a stronger argument for them than any layering diagram.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/app/theme/alaya_theme.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/domain/services/lock/biometric_gate.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

import 'fake_settings_repository.dart';

/// The narrowest width this app supports, with a phone-height viewport (Law U15).
const Size kNarrowPhone = Size(320, 640);

/// A clock fixed so every derived date is identical on every machine.
final Clock kSettingsClock = FixedClock(DateTime(2026, 8, 10, 9, 30));

/// Today, according to [kSettingsClock].
const DateKey kSettingsToday = DateKey(20260810);

/// A future that never completes, for a `FutureProvider`'s loading branch.
Future<T> pendingFuture<T>() => Completer<T>().future;

/// A stream that never emits and never closes, for a `StreamProvider`'s loading branch.
Stream<T> pendingStream<T>() => StreamController<T>().stream;

/// An `AppLock` that answers from fields a test sets, rather than from secure storage.
class FakeAppLock implements AppLock {
  /// Creates the fake.
  FakeAppLock({
    this.enabled = false,
    this.pinLength = 4,
    this.failedCount = 0,
    this.lockout,
    this.correctPin = '1234',
    this.enableFails = false,
  });

  /// Whether a lock is configured.
  bool enabled;

  /// How many digits the configured PIN has.
  int pinLength;

  /// Consecutive failures recorded.
  int failedCount;

  /// The delay in force, or null.
  Duration? lockout;

  /// The PIN [verifyPin] accepts.
  String correctPin;

  /// Whether [enable] reports a failure, for the error branch of PIN setup.
  bool enableFails;

  /// The recovery code [enable] hands back.
  static const String recoveryCode = 'ABCDE-FGHJK';

  @override
  Future<bool> get isEnabled async => enabled;

  @override
  Future<int> readPinLength() async => pinLength;

  @override
  Future<int> readFailedCount() async => failedCount;

  @override
  Future<Duration?> remainingLockout() async => lockout;

  @override
  Future<UnlockOutcome> verifyPin(String pin) async {
    if (lockout != null) {
      return UnlockOutcome(
        unlocked: false,
        refusal: UnlockRefusal.throttled,
        failedCount: failedCount,
        retryAfter: lockout,
      );
    }
    if (pin == correctPin) return const UnlockOutcome.success();
    failedCount += 1;
    return UnlockOutcome(
      unlocked: false,
      refusal: UnlockRefusal.wrongPin,
      failedCount: failedCount,
    );
  }

  @override
  Future<Result<String, Failure>> enable({required String pin}) async {
    if (enableFails) {
      return const Result.failure(
        UnexpectedFailure('Secure storage is unavailable on this device.'),
      );
    }
    enabled = true;
    correctPin = pin;
    pinLength = pin.length;
    return const Result.ok(recoveryCode);
  }

  @override
  Future<Result<void, Failure>> changePin({
    required String currentPin,
    required String newPin,
  }) async => const Result.ok(null);

  @override
  Future<Result<void, Failure>> disable({required String pin}) async {
    enabled = false;
    return const Result.ok(null);
  }

  @override
  Future<Result<void, Failure>> resetWithRecoveryCode({
    required String code,
    required String newPin,
  }) async {
    if (code.replaceAll('-', '').toUpperCase() !=
        recoveryCode.replaceAll('-', '')) {
      return const Result.failure(
        ValidationFailure('That recovery code is not right.', field: 'code'),
      );
    }
    correctPin = newPin;
    return const Result.ok(null);
  }
}

/// A `BiometricGate` that neither needs a sensor nor a platform channel.
class FakeBiometricGate implements BiometricGate {
  /// Creates the fake.
  FakeBiometricGate({this.available = false, this.succeeds = true});

  /// Whether the shortcut is offered at all.
  bool available;

  /// Whether [authenticate] succeeds.
  bool succeeds;

  @override
  Future<bool> get isAvailable async => available;

  @override
  Future<Result<void, Failure>> authenticate({required String reason}) async =>
      succeeds
      ? const Result.ok(null)
      : const Result.failure(
          BusinessRuleFailure('Not recognised.', rule: 'biometricRejected'),
        );
}

/// A `DataTransferPort` that records what it was asked to do.
class FakeDataTransfer implements DataTransferPort {
  /// Creates the fake.
  FakeDataTransfer({this.exportFails = false, this.eraseFails = false});

  /// Whether the export reports a failure.
  bool exportFails;

  /// Whether the erase reports a failure.
  bool eraseFails;

  /// How many exports were requested.
  int exports = 0;

  /// How many erases were requested.
  int erases = 0;

  @override
  Future<Result<BackupArtefact, Failure>> exportAndShare() async {
    exports += 1;
    if (exportFails) {
      return const Result.failure(
        UnexpectedFailure('No room left on this device.'),
      );
    }
    return const Result.ok(
      (
        path: '/cache/alaya.db',
        sizeBytes: 4096,
        isZipped: false,
        fileName: 'alaya-backup.db',
      ),
    );
  }

  // Phase 8B extended `DataTransferPort` with SAF export, history and restore, so this fake stopped satisfying
  // it. Answering flatly is right here: 8A's tests are about the lock and the settings tree, and a fake that
  // pretended to restore would invite an 8A test to assert on 8B's behaviour.
  @override
  Future<Result<BackupArtefact?, Failure>> exportToLocation() async =>
      const Result.ok(null);

  @override
  Stream<List<BackupRecord>> watchHistory() => Stream.value(const []);

  @override
  Future<Result<void, Failure>> forgetHistoryEntry(String id) async =>
      const Result.ok(null);

  @override
  Future<Result<String?, Failure>> pickBackupFile() async =>
      const Result.ok(null);

  @override
  Future<Result<int, Failure>> readBackupVersion(String path) async =>
      const Result.ok(1);

  @override
  bool get canSaveToLocation => false;

  @override
  int get appSchemaVersion => 1;

  @override
  Future<Result<RestoreOutcome, Failure>> merge(String path) async =>
      const Result.ok(
        (
          mode: RestoreMode.merge,
          tablesMerged: 0,
          backupSchemaVersion: 1,
          rollbackAvailable: false,
        ),
      );

  @override
  Future<Result<RestoreOutcome, Failure>> replace(String path) async =>
      const Result.ok(
        (
          mode: RestoreMode.replace,
          tablesMerged: 0,
          backupSchemaVersion: 1,
          rollbackAvailable: false,
        ),
      );

  @override
  Future<Result<void, Failure>> rollback() async => const Result.ok(null);

  @override
  Future<bool> hasRollback() async => false;

  @override
  Future<Result<void, Failure>> eraseEverything() async {
    erases += 1;
    return eraseFails
        ? const Result.failure(
            UnexpectedFailure('The data could not be deleted.'),
          )
        : const Result.ok(null);
  }
}

/// One account, for the lists and the editor.
Account account({
  String id = 'ac-1',
  String name = 'Cash',
  AccountKind kind = AccountKind.cash,
  bool isArchived = false,
  bool includeInNetWorth = true,
}) => Account(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  kind: kind,
  currencyCode: 'INR',
  openingBalance: const Money(250000, 'INR'),
  openingBalanceDateKey: kSettingsToday,
  isArchived: isArchived,
  includeInNetWorth: includeInNetWorth,
  sortOrder: 0,
);

/// One tag, scoped where the caller says.
Tag tag({
  String id = 'tg-1',
  String name = 'Kitchen',
  Set<TagScope> scopes = const {TagScope.inventory},
  String? parentTagId,
  bool isSystem = false,
}) => Tag(
  id: id,
  name: name,
  normalizedName: name.toLowerCase(),
  allowedScopes: scopes,
  isSystem: isSystem,
  sortOrder: 0,
  isDeleted: false,
  parentTagId: parentTagId,
);

/// One unit.
Unit unit({
  String code = 'kg',
  String displayName = 'Kilogram',
  UnitCategory category = UnitCategory.weight,
  int factorToBaseMilli = 1000000,
  bool isSystem = true,
}) => Unit(
  code: code,
  category: category,
  factorToBaseMilli: factorToBaseMilli,
  displayName: displayName,
  isSystem: isSystem,
  sortOrder: 0,
);

/// One payment method.
PaymentMethod paymentMethod({
  String id = 'pm-1',
  String name = 'Cash',
  bool isSystem = false,
}) => PaymentMethod(
  id: id,
  name: name,
  kind: PaymentMethodKind.cash,
  isSystem: isSystem,
  sortOrder: 0,
);

/// One payee.
Payee payee({String id = 'py-1', String name = 'Corner Shop', String? phone}) =>
    Payee(
      id: id,
      name: name,
      normalizedName: name.toLowerCase(),
      kind: PayeeKind.merchant,
      phone: phone,
    );

/// One currency.
Currency currency({String code = 'INR', bool isEnabled = true}) => Currency(
  code: code,
  name: code,
  symbol: code == 'INR' ? '₹' : '¥',
  decimalDigits: code == 'JPY' ? 0 : 2,
  isEnabled: isEnabled,
  sortOrder: 0,
);

/// Overrides every provider 8A's screens reach.
///
/// **Fixed length, always.** A conditional entry changes the override count between scopes and Riverpod refuses
/// it outright — and two `pumpWidget` calls in one test silently reuse the first scope, so a varying list fails
/// in both directions (ARCH_6 P5). Every provider is overridden even where a test does not care, because an
/// un-overridden repository reaches a real database, which a widget test has no business opening.
List<Override> settingsOverrides({
  FakeAppLock? lock,
  FakeBiometricGate? biometric,
  FakeDataTransfer? transfer,
  AsyncValue<List<Account>>? accounts,
  AsyncValue<List<Tag>>? tags,
  AsyncValue<List<Unit>>? units,
  AsyncValue<List<PaymentMethod>>? paymentMethods,
  AsyncValue<List<Payee>>? payees,
  AsyncValue<List<Currency>>? currencies,
}) => [
  clockProvider.overrideWithValue(kSettingsClock),
  // `lockConfiguredAtStartupProvider` throws when un-overridden, by design — `bootstrap()` is the only place
  // that resolves it. A widget test never has a lock, so false.
  lockConfiguredAtStartupProvider.overrideWithValue(false),
  // True, so no widget test is ever redirected into the first-run flow.
  onboardingDoneAtStartupProvider.overrideWithValue(true),
  settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
  pinServiceProvider.overrideWithValue(lock ?? FakeAppLock()),
  biometricGateProvider.overrideWithValue(biometric ?? FakeBiometricGate()),
  dataTransferPortProvider.overrideWithValue(transfer ?? FakeDataTransfer()),
  accountsSettingsProvider.overrideWith(
    (ref) => _stream(accounts ?? AsyncValue.data([account()])),
  ),
  tagsSettingsProvider.overrideWith(
    (ref) => _stream(tags ?? AsyncValue.data([tag()])),
  ),
  unitsSettingsProvider.overrideWith(
    (ref) => _stream(units ?? AsyncValue.data([unit()])),
  ),
  paymentMethodsSettingsProvider.overrideWith(
    (ref) => _stream(paymentMethods ?? AsyncValue.data([paymentMethod()])),
  ),
  payeesSettingsProvider.overrideWith(
    (ref) => _stream(payees ?? AsyncValue.data([payee()])),
  ),
  currenciesSettingsProvider.overrideWith(
    (ref) => _stream(currencies ?? AsyncValue.data([currency()])),
  ),
  homeCurrencyCodeProvider.overrideWith((ref) async => 'INR'),
  accountsHomeCurrencyProvider.overrideWith((ref) async => 'INR'),
  onboardingCurrenciesProvider.overrideWith(
    (ref) => Stream.value([currency(), currency(code: 'JPY')]),
  ),
  onboardingCurrencyDigitsProvider.overrideWith(
    (ref, code) async => code == 'JPY' ? 0 : 2,
  ),
  settingsAccountCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsPaymentMethodCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsPayeeCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsTagCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsUnitCountProvider.overrideWith((ref) => Stream.value(1)),
  settingsCurrencyCountProvider.overrideWith(
    (ref) => Stream.value((enabled: 1, total: 2)),
  ),
];

Stream<T> _stream<T>(AsyncValue<T> value) => value.when(
  data: Stream.value,
  loading: pendingStream<T>,
  error: (error, stack) => Stream<T>.error(error, stack),
);

/// Pumps [child] inside the app's theme and localisations at a fixed size and text scale.
///
/// The text scaler goes through `MaterialApp.builder`, not a `MediaQuery` above the app: `WidgetsApp`
/// re-establishes `MediaQuery` from the view, so an override placed above it never arrives (ARCH_5 §10).
///
/// [wrapInShell] supplies a `Scaffold`, because `MaterialApp` provides no `Material` ancestor and a shell
/// destination declares none of its own — without it, every `ChoiceChip` and `InkWell` asserts.
Future<void> pumpSettings(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  Size size = kNarrowPhone,
  double textScale = 1,
  bool dark = false,
  bool wrapInShell = false,
}) async {
  tester.view.physicalSize = size * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark
            ? AlayaTheme.dark(AlayaPresets.activePreset)
            : AlayaTheme.light(AlayaPresets.activePreset),
        localizationsDelegates: const [
          AlayaStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AlayaStrings.supportedLocales,
        builder: (context, inner) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: inner!,
        ),
        home: wrapInShell ? Scaffold(body: child) : child,
      ),
    ),
  );
  await tester.pump();
}
