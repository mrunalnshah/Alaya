/// View-model state for the first-run flow (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** `accountRepositoryProvider`,
/// `settingsRepositoryProvider` and the rest live in `lib/app/providers/` and are watched from here
/// (Law U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';

/// Whether the first-run flow still has to happen.
enum OnboardingPhase {
  /// Still asking `app_settings`.
  ///
  /// Distinct from `needed`, so the router does not push a brand-new user into onboarding and then pull
  /// them out again a frame later when the answer arrives.
  unknown,

  /// Not finished and not skipped.
  needed,

  /// Finished, or skipped deliberately.
  done,
}

/// Whether onboarding had already been finished when the app started.
///
/// **Overridden by `bootstrap()` with an awaited answer**, for the same reason the lock has one — and after the
/// same bug. A `Notifier` that starts at [OnboardingPhase.unknown] and resolves a frame later leaves the router's
/// first decision wrong, and worse, it can miss its own correction: if `_restore()` completes before `GoRouter`
/// attaches its `refreshListenable`, the notification lands on nobody and the redirect does not re-run until the
/// next navigation. The symptom is a first-run flow that appears when the user opens Settings.
///
/// One awaited settings read before `runApp` removes both halves.
final onboardingDoneAtStartupProvider = Provider<bool>((ref) {
  throw StateError(
    'onboardingDoneAtStartupProvider was not overridden. bootstrap() must supply it — see '
    'lib/app/bootstrap.dart. A widget test supplies true, so no test is redirected into onboarding.',
  );
});

/// Whether onboarding is still owed, and the one place that changes.
final onboardingPhaseProvider =
    NotifierProvider<OnboardingPhaseNotifier, OnboardingPhase>(
      OnboardingPhaseNotifier.new,
    );

/// Reads and records whether onboarding is finished.
class OnboardingPhaseNotifier extends Notifier<OnboardingPhase> {
  @override
  OnboardingPhase build() {
    // Synchronous, from a value `bootstrap()` already awaited — so the router's first decision is correct and
    // does not depend on a notification arriving after a listener exists.
    return ref.read(onboardingDoneAtStartupProvider)
        ? OnboardingPhase.done
        : OnboardingPhase.needed;
  }

  /// Records that onboarding is over, whether finished or skipped.
  ///
  /// The write is awaited, unlike the theme and range preferences: this is the flag that stops the
  /// router sending the user back, and losing it would restart the flow on the next launch.
  Future<void> complete() async {
    await ref
        .read(settingsRepositoryProvider)
        .writeValue(
          key: OnboardingKeys.done,
          value: 'true',
          valueType: 'string',
        );
    state = OnboardingPhase.done;
  }
}

/// Whether the router should redirect to the first-run flow.
///
/// There is no guess left to make: the phase is resolved before the first frame, so `unknown` never reaches the
/// router. It remains on the enum only for a scope that has not been given a startup value — which now throws
/// rather than defaulting, because a silent default is what produced the bug this replaced.
final needsOnboardingProvider = Provider<bool>(
  (ref) => ref.watch(onboardingPhaseProvider) == OnboardingPhase.needed,
);

/// The currencies the picker offers.
///
/// **Declared here rather than reusing 6A's `enabledCurrenciesProvider`, which lives inside
/// `quick_add_sheet.dart`.** Importing a sheet to obtain a provider is worse coupling than a second
/// stream over `currencies` — a five-row seeded table — and 7B's rule about not duplicating a stream was
/// about `accounts`, which grows. Consolidating the two belongs in Phase 9's sweep, along with moving
/// that provider out of a screen file.
final onboardingCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// One currency's minor-unit precision, so an amount field shows the right number of decimals.
///
/// JPY has none, and an opening balance typed as `1200` becoming `¥1,200.00` is the bug this prevents.
final onboardingCurrencyDigitsProvider = FutureProvider.family<int, String>((
  ref,
  code,
) async {
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The first-run flow's draft and every transition it has.
final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );

/// Holds the draft, loads what the seeder already created, and commits.
class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() {
    unawaited(_load());
    return const OnboardingDraft(
      step: OnboardingStep.currency,
      homeCurrencyCode: fallbackHomeCurrencyCode,
      accounts: <DraftAccount>[],
    );
  }

  /// The currency assumed until `app_settings` answers.
  ///
  /// Matches Phase 1C's seeder default so the first frame agrees with the database rather than flicking
  /// from one code to another.
  static const String fallbackHomeCurrencyCode = 'INR';

  /// Loads the seeded accounts and the stored step.
  ///
  /// **The flow edits as much as it creates.** Phase 1C's seeder already inserts two accounts and a
  /// `homeCurrencyCode`, so starting from an empty list would either duplicate them or quietly ignore
  /// them — and a first-run screen that shows none of the accounts the app already has reads as broken.
  Future<void> _load() async {
    final settings = ref.read(settingsRepositoryProvider);
    final home =
        await settings.readHomeCurrencyCode() ?? fallbackHomeCurrencyCode;
    final storedStep = await settings.readValue(OnboardingKeys.step);
    final existing = await ref
        .read(accountRepositoryProvider)
        .watchSelectable()
        .first;

    state = state.copyWith(
      step: OnboardingKeys.parseStep(storedStep),
      homeCurrencyCode: home,
      accounts: [for (final account in existing) DraftAccount.from(account)],
      isLoaded: true,
    );
  }

  /// Sets the currency totals are shown in, carrying untouched accounts with it.
  ///
  /// **Untouched accounts follow; chosen ones do not.** Somebody selecting yen on step one does not want
  /// two rupee accounts they never asked for, and equally does not want an account they deliberately set
  /// to rupees rewritten behind them. `DraftAccount.currencyTouched` is what separates the two.
  void setHomeCurrency(String code) {
    state = state.copyWith(
      homeCurrencyCode: code,
      accounts: [
        for (final account in state.accounts)
          account.currencyTouched
              ? account
              : account.copyWith(currencyCode: code),
      ],
      clearFailure: true,
    );
  }

  /// Adds an empty account row, in the home currency and dated today.
  void addAccount() {
    state = state.copyWith(
      accounts: [
        ...state.accounts,
        DraftAccount(
          name: '',
          kind: AccountKind.cash,
          currencyCode: state.homeCurrencyCode,
          openingMinor: 0,
          openingDate: ref.read(clockProvider).today(),
        ),
      ],
      clearFailure: true,
    );
  }

  /// Replaces the row at [index].
  void updateAccount(int index, DraftAccount account) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..[index] = account;
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Marks the row at [index] as having a currency the user chose.
  void setAccountCurrency(int index, String code) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]
      ..[index] = state.accounts[index].copyWith(
        currencyCode: code,
        currencyTouched: true,
      );
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Removes the row at [index].
  ///
  /// A row that already exists in the database is **not** deleted here — removing it from the draft
  /// only stops this flow writing to it. Deleting an account is a destructive action with its own tier
  /// in ARCH_5 §5.5, and burying it in a first-run screen would be the wrong place for it.
  void removeAccount(int index) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..removeAt(index);
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Moves to [step] and remembers it, so a restart resumes here.
  Future<void> goTo(OnboardingStep step) async {
    state = state.copyWith(step: step, clearFailure: true);
    await ref
        .read(settingsRepositoryProvider)
        .writeValue(
          key: OnboardingKeys.step,
          value: step.name,
          valueType: 'string',
        );
  }

  /// Writes the home currency, then moves to the accounts step.
  ///
  /// Through `writeHomeCurrencyCode` rather than `writeValue` with a key: the key lives in `data/`, which
  /// a feature may not import, and a literal here would write to a dead key the moment `data/` renamed it.
  Future<bool> commitCurrency() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref
        .read(settingsRepositoryProvider)
        .writeHomeCurrencyCode(state.homeCurrencyCode);
    if (result.isFailure) {
      state = state.copyWith(
        isSaving: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(isSaving: false);
    await goTo(OnboardingStep.accounts);
    return true;
  }

  /// Saves every account, then moves to the security step.
  ///
  /// **Stops at the first failure rather than continuing.** Half-written accounts with the other half
  /// reported as an error is a worse state to leave someone in than nothing written, and Law L14's
  /// all-or-nothing reasoning applies to a loop of writes as much as to a transaction.
  Future<bool> commitAccounts() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final repository = ref.read(accountRepositoryProvider);
    final normalizer = ref.read(normalizerProvider);
    final uids = ref.read(uidGeneratorProvider);

    for (var i = 0; i < state.accounts.length; i++) {
      final draft = state.accounts[i];
      final account = Account(
        id: draft.id ?? uids.generate(),
        name: draft.name.trim(),
        normalizedName: normalizer.normalize(draft.name),
        kind: draft.kind,
        currencyCode: draft.currencyCode,
        openingBalance: Money(draft.openingMinor, draft.currencyCode),
        openingBalanceDateKey: draft.openingDate,
        isArchived: false,
        includeInNetWorth: draft.includeInNetWorth,
        sortOrder: i,
      );
      final result = await repository.save(account);
      if (result.isFailure) {
        state = state.copyWith(
          isSaving: false,
          failureMessage: result.failureOrNull?.message,
        );
        return false;
      }
    }

    state = state.copyWith(isSaving: false);
    // **Straight to finished. There is no security step any more.**
    //
    // Asking a first-time user to choose a PIN before they have entered a single transaction put the most
    // abandonable question in the flow at the point they had least reason to answer it — and it was the step that
    // needed a redirect exemption, an embedded widget and a post-frame callback to report upward. Settings ›
    // Security offers the same thing later, when there is something worth locking.
    await finish();
    return true;
  }

  /// Ends the flow, whether the user finished it or skipped.
  Future<void> finish() async {
    await goTo(OnboardingStep.done);
    await ref.read(onboardingPhaseProvider.notifier).complete();
  }
}
