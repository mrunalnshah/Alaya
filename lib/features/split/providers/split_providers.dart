/// View-model state for the Split module (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/currency_providers.dart'
    show homeDecimalDigitsProvider;
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/domain/services/split/split_balance_service.dart';

/// Every outstanding balance, worst first.
///
/// **Only counterparties with something outstanding**, so an empty list means settled up with
/// everybody rather than "nobody is configured" — which is what lets the home screen tell those two
/// apart instead of showing a success message for a setup step nobody has done.
final splitBalancesProvider = StreamProvider<List<SplitBalance>>(
  (ref) => ref.watch(splitBalanceServiceProvider).watchBalances(),
);

/// What is owed to the user and by the user, per currency.
///
/// Two figures rather than one net total. *"You are owed ₹4,000 and you owe ₹3,900"* is not the same
/// story as *"you are up ₹100"*, and per the module's first decision neither figure is spendable
/// until it arrives.
final splitTotalsProvider = FutureProvider<Map<String, ({Money owedToMe, Money iOwe})>>((
  ref,
) {
  // Rebuilt whenever a balance changes. `totals()` reads the stream once, so without this watch it
  // would hold whatever the figures were when this provider happened to be first read — a stale
  // total on a card is worse than none, because nothing on screen says it is stale.
  ref.watch(splitBalancesProvider);
  return ref.watch(splitBalanceServiceProvider).totals();
});

/// Debts old enough to be worth mentioning, oldest first.
///
/// **The nudge nobody else sends.** A due-date reminder needs a date somebody remembered to set; this
/// needs nothing, because `v_split_balances` already carries the oldest contributing expense. The day
/// count is computed against the injected `Clock` rather than in SQL — ARCH_2 §12.2 forbids a view
/// from consulting the current time, and one that did could not be asserted against a `FixedClock`.
final splitAgeingProvider = FutureProvider<List<AgeingDebt>>((ref) {
  ref.watch(splitBalancesProvider);
  return ref.watch(splitBalanceServiceProvider).ageingDebts();
});

/// Every group, archived ones included, for the groups screen.
final splitAllGroupsProvider = StreamProvider<List<SplitGroup>>(
  (ref) => ref.watch(splitGroupRepositoryProvider).watchAll(),
);

/// One group with its members, for the detail screen and the editor.
final splitGroupProvider = StreamProvider.family<SplitGroup?, String>(
  (ref, id) => ref.watch(splitGroupRepositoryProvider).watchById(id),
);

/// Who owes what within one group.
///
/// **Straight to the repository, not through `SplitBalanceService`.** That service exists for the two
/// things a view cannot do — comparing against the current date, and running the simplifier — and this
/// is neither. A method that only forwards is the indirection ARCH_1 §6 warns makes a call chain
/// unreadable for nothing.
final splitGroupBalancesProvider =
    StreamProvider.family<List<SplitBalance>, String>(
      (ref, groupId) =>
          ref.watch(splitLedgerRepositoryProvider).watchGroupBalances(groupId),
    );

/// What has happened in one group, newest first.
///
/// **`limit` is required by the contract and supplied here.** The feed is a `UNION ALL` over two
/// growing tables with no date bound — the one read in this module that gets slower every month a
/// person keeps using it — so a screen has to name a page size.
final splitGroupActivityProvider =
    StreamProvider.family<List<SplitActivityEntry>, String>(
      (ref, groupId) => ref
          .watch(splitLedgerRepositoryProvider)
          .watchActivity(groupId: groupId, limit: 50),
    );

/// The fewest payments that settle a group, one plan per currency.
///
/// **A `FutureProvider`, not a stream, and that is the honest shape.** A plan is a snapshot of a
/// question asked once — *"what is the shortest way out of this right now"* — and a live-updating plan
/// would rewrite the suggestions under a user's thumb as they act on them. Recording one settlement
/// invalidates it, which is what the screen wants: reopen and the plan reflects what is left.
final splitSettlePlansProvider =
    FutureProvider.family<List<CurrencyPlan>, String>((ref, groupId) {
      ref.watch(splitGroupBalancesProvider(groupId));
      return ref.watch(splitBalanceServiceProvider).settleUpPlans(groupId);
    });

/// Everybody who can be **chosen** for a split.
///
/// **[PayeeKind.person] only, and the exclusion of [PayeeKind.splitPlaceholder] is deliberate.** A
/// placeholder is a row this app created because a split had to name somebody; offering it as a
/// participant on the *next* split would attach two unrelated dinners to the same stranger. It is a
/// record, not a contact.
///
/// Merchants, employers and utilities are excluded for the older reason: `payees` holds shops too, and
/// offering the electricity board as somebody who owes you for dinner is how a picker teaches people
/// to distrust it.
final splitPeopleProvider = StreamProvider<List<Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map(
        (all) => [
          for (final payee in all)
            if (payee.kind == PayeeKind.person) payee,
        ],
      ),
);

/// Everybody who can **appear** on a split — real people and placeholders alike.
///
/// **The opposite filter to [splitPeopleProvider], and getting them the wrong way round is the trap.**
/// A balance row holds a payee id and needs a name for it; if that lookup used the pickers list, every
/// placeholder balance would resolve to null, render as "Someone", and offer no way to fix itself —
/// the exact row the rename affordance exists for.
///
/// Same source, opposite purposes: one answers *"who may I add?"*, this answers *"who is this?"*.
final splitParticipantsProvider = StreamProvider<List<Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map(
        (all) => [
          for (final payee in all)
            if (payee.kind == PayeeKind.person ||
                payee.kind == PayeeKind.splitPlaceholder)
              payee,
        ],
      ),
);

/// The payee the user has claimed as themselves, or null when unset.
///
/// **Null means "not configured", never "nobody".** Without it nothing can say which side of a debt
/// the user is on, so every balance would be a guess.
final splitSelfProvider = FutureProvider<String?>(
  (ref) => ref.watch(splitGroupRepositoryProvider).selfPayeeId(),
);

/// The whole payee behind an id, for a row that needs more than a name.
///
/// Reads [splitParticipantsProvider], so a placeholder resolves — see that provider's note.
final splitPayeeProvider = Provider.family<Payee?, String>((ref, payeeId) {
  final people = ref.watch(splitParticipantsProvider).valueOrNull;
  if (people == null) return null;
  for (final payee in people) {
    if (payee.id == payeeId) return payee;
  }
  return null;
});

/// Resolves a payee id to a display name, for rows that only hold ids.
///
/// Returns null for an unknown id rather than a placeholder string, so each caller decides what to
/// show — a row can fall back to a generic label while a sheet might omit the line entirely.
final splitPayeeNameProvider = Provider.family<String?, String>(
  (ref, payeeId) => ref.watch(splitPayeeProvider(payeeId))?.name,
);

/// The accounts a settlement or an expense can move through.
///
/// `watchSelectable`, not `watchAllIncludingArchived`: an archived account is one the user has
/// retired, and offering it as somewhere money just arrived would put a live balance back into a place
/// they closed.
final splitAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// How a settlement travelled — UPI, cash, bank transfer.
final splitPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// The home currency's decimal precision, so no amount hardcodes 2 (ARCH_1 §4.1).
///
/// Re-exported from `app/providers/currency_providers.dart` rather than reimplemented: two providers
/// reading the same setting is the duplication ARCH_M §6 forbids.
final splitDecimalDigitsProvider = homeDecimalDigitsProvider;

/// Today, for a date field's initial value.
///
/// Through `clockProvider` rather than `DateTime.now()`, so a widget test that pins the clock gets a
/// reproducible default.
final splitTodayProvider = Provider<DateKey>(
  (ref) => ref.watch(clockProvider).today(),
);
