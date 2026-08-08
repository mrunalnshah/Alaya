import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';

/// Which step of the first-run flow the user is on.
///
/// Stored by name, so resuming survives a restart and a reorder of this enum does not silently move
/// somebody to a different step (Law L13's reasoning, applied to a settings row rather than a column).
enum OnboardingStep {
  /// Which currency totals are shown in.
  currency,

  /// The accounts, and what was in them when the user started.
  accounts,

  /// Finished or skipped.
  done,
}

/// How the first-run flow is stored.
abstract final class OnboardingKeys {
  /// The `app_settings` key holding whether onboarding is finished or was skipped.
  static const String done = 'onboarding.done';

  /// The `app_settings` key holding the furthest step reached.
  ///
  /// **Written on every step change, which is what "resumable" costs.** A flow that only records
  /// completion would restart from the beginning after a phone call at step two, and re-asking someone
  /// for their opening balances is the fastest way to have them skip the flow entirely.
  static const String step = 'onboarding.step';

  /// Parses a stored step name, falling back to the first step.
  static OnboardingStep parseStep(String? stored) {
    for (final step in OnboardingStep.values) {
      if (step.name == stored) return step;
    }
    return OnboardingStep.currency;
  }
}

/// One account being set up, before it is saved.
///
/// A draft rather than an `Account`, because an `Account` requires a `normalizedName` and a `sortOrder`
/// that the user never sees and should not have to think about, and because half of these rows already
/// exist in the database — Phase 1C's seeder creates two — so the flow is editing as much as creating.
class DraftAccount {
  /// Creates a draft.
  const DraftAccount({
    required this.name,
    required this.kind,
    required this.currencyCode,
    required this.openingMinor,
    required this.openingDate,
    this.id,
    this.includeInNetWorth = true,
    this.currencyTouched = false,
  });

  /// A draft of an account that already exists, keeping every value it has.
  factory DraftAccount.from(Account account) => DraftAccount(
    id: account.id,
    name: account.name,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingMinor: account.openingBalance.minor,
    openingDate: account.openingBalanceDateKey,
    includeInNetWorth: account.includeInNetWorth,
  );

  /// The existing account's id, or null for one being added.
  final String? id;

  /// What the user calls it.
  final String name;

  /// Cash, bank, wallet, card or other.
  final AccountKind kind;

  /// The currency the balance is held in.
  ///
  /// Its own field and not derived from the home currency, because Law L9 makes the home currency a
  /// display choice: an account in yen stays in yen however the user chooses to see totals.
  final String currencyCode;

  /// What was in it on [openingDate], in minor units.
  final int openingMinor;

  /// The date the balance was true on.
  ///
  /// **This is the half of the pair that gets forgotten** (anomaly A03). A balance without a date
  /// cannot be placed in a ledger, so every transaction before it would be silently unaccounted for.
  final DateKey openingDate;

  /// Whether it counts toward net worth.
  final bool includeInNetWorth;

  /// Whether the user has chosen this account's currency themselves.
  ///
  /// **Why a flag and not a comparison.** Changing the home currency on step one should carry the
  /// seeded accounts with it — nobody choosing yen wants two rupee accounts they did not ask for — but
  /// it must not overwrite a currency the user set deliberately. Comparing against the old home
  /// currency cannot tell those apart when they happen to match.
  final bool currencyTouched;

  /// The balance as a `Money`.
  Money get openingBalance => Money(openingMinor, currencyCode);

  /// Whether this draft is complete enough to save.
  bool get isValid => name.trim().isNotEmpty && currencyCode.isNotEmpty;

  /// A copy with the given fields replaced.
  DraftAccount copyWith({
    String? name,
    AccountKind? kind,
    String? currencyCode,
    int? openingMinor,
    DateKey? openingDate,
    bool? includeInNetWorth,
    bool? currencyTouched,
  }) => DraftAccount(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    currencyCode: currencyCode ?? this.currencyCode,
    openingMinor: openingMinor ?? this.openingMinor,
    openingDate: openingDate ?? this.openingDate,
    includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
    currencyTouched: currencyTouched ?? this.currencyTouched,
  );
}

/// Everything the first-run flow is holding.
class OnboardingDraft {
  /// Creates a draft.
  const OnboardingDraft({
    required this.step,
    required this.homeCurrencyCode,
    required this.accounts,
    this.isLoaded = false,
    this.isSaving = false,
    this.failureMessage,
  });

  /// The step being shown.
  final OnboardingStep step;

  /// The currency totals are aggregated into (Law L9).
  final String homeCurrencyCode;

  /// The accounts being set up, seeded ones included.
  final List<DraftAccount> accounts;

  /// Whether the existing accounts and settings have been read yet.
  final bool isLoaded;

  /// Whether a save is in flight.
  final bool isSaving;

  /// The repository's own message from the last failed write (Law U9).
  final String? failureMessage;

  /// Whether every account is complete enough to save.
  bool get accountsAreValid =>
      accounts.isNotEmpty && accounts.every((account) => account.isValid);

  /// A copy with the given fields replaced.
  ///
  /// [failureMessage] is cleared by passing [clearFailure], because `null` cannot distinguish "leave it"
  /// from "clear it" in a `copyWith` — and a stale error under a field the user has since fixed is worse
  /// than no error at all.
  OnboardingDraft copyWith({
    OnboardingStep? step,
    String? homeCurrencyCode,
    List<DraftAccount>? accounts,
    bool? isLoaded,
    bool? isSaving,
    String? failureMessage,
    bool clearFailure = false,
  }) => OnboardingDraft(
    step: step ?? this.step,
    homeCurrencyCode: homeCurrencyCode ?? this.homeCurrencyCode,
    accounts: accounts ?? this.accounts,
    isLoaded: isLoaded ?? this.isLoaded,
    isSaving: isSaving ?? this.isSaving,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}
