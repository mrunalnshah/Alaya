import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/converted_money.dart';
import 'package:alaya/domain/services/currency_rate_service.dart';

/// One account's balance plus whether it counts toward net worth.
///
/// A narrow input type rather than the full `Account` entity: net worth needs three facts, and
/// asking for twenty-six would couple this service to every unrelated change to an account.
class AccountBalanceInput {
  /// Creates an input row.
  const AccountBalanceInput({
    required this.accountId,
    required this.balance,
    required this.includeInNetWorth,
  });

  /// The account.
  final String accountId;

  /// Its balance, in its own currency.
  final Money balance;

  /// Whether the user wants this account counted in the headline.
  final bool includeInNetWorth;
}

/// A converted headline total, and how many balances could not be converted into it.
///
/// The count is carried rather than discarded because a missing rate must exclude an amount, not
/// count it as zero (ARCH_3 §1.3.4). A total presented without it would be quietly wrong; presented
/// with it, the UI can show `+2 unconverted` and the number stops being a lie.
class NetWorth {
  /// Creates a headline.
  const NetWorth({
    required this.total,
    required this.unconvertedCount,
    required this.isApproximate,
  });

  /// The sum of every convertible, included balance, in the home currency.
  final Money total;

  /// How many included balances had no usable rate and were left out of [total].
  final int unconvertedCount;

  /// True when at least one contributing rate had to fall back to a date outside the requested one,
  /// so the figure is indicative rather than exact (`RateQuality.approximate`).
  final bool isApproximate;

  /// True when every included balance converted cleanly.
  bool get isComplete => unconvertedCount == 0;
}

/// Computes per-account and aggregate balances.
///
/// Owns the net-worth rule so there is exactly one definition of it. `AccountRepository` supplies
/// the raw per-account balances — which come from `v_account_balances`, where a self-transfer nets to
/// zero by construction — and this service decides what counts and converts what remains.
final class BalanceService {
  /// Creates the service.
  const BalanceService();

  /// Sums [balances] into [homeCurrencyCode] using [table], as of [asOf].
  ///
  /// Pure and synchronous: given a rate table it performs no I/O, which is why the whole net-worth
  /// rule is testable from literals. Callers converting a long list should load the table once and
  /// call this, rather than converting amount by amount.
  ///
  /// **Which accounts count.** Only `includeInNetWorth`. An **archived** account still counts —
  /// ARCH_3 §4's table is explicit that archive keeps money in your net worth and only delete
  /// removes it, because a closed bank account with a remaining balance is retired, not gone. So
  /// archived-ness is deliberately not a filter here, and `AccountRepository.watchAllIncludingArchived`
  /// is the right source to feed this.
  ///
  /// **Which balances convert.** One already in [homeCurrencyCode] passes through untouched — no
  /// rate is consulted, so an all-single-currency user never sees an `unconvertedCount` above zero
  /// even with an empty rate cache.
  NetWorth totalFrom({
    required Iterable<AccountBalanceInput> balances,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    var total = Money.zero(homeCurrencyCode);
    var unconverted = 0;
    var approximate = false;

    for (final input in balances) {
      if (!input.includeInNetWorth) continue;

      final converted = table.convert(
        amount: input.balance,
        toCurrencyCode: homeCurrencyCode,
        on: asOf,
      );
      if (converted.isExcludedFromTotals) {
        unconverted++;
        continue;
      }
      if (converted.quality == RateQuality.approximate) approximate = true;

      // `converted.converted` is in homeCurrencyCode, matching `total`, so this cannot throw a
      // currency mismatch however many source currencies were involved.
      total = total + converted.converted!;
    }

    return NetWorth(
      total: total,
      unconvertedCount: unconverted,
      isApproximate: approximate,
    );
  }

  /// Loads the rate table and sums [balances] — the convenience form of [totalFrom].
  Future<NetWorth> totalInHome({
    required Iterable<AccountBalanceInput> balances,
    required CurrencyRateService rates,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) async {
    final table = await rates.table();
    return totalFrom(
      balances: balances,
      table: table,
      homeCurrencyCode: homeCurrencyCode,
      asOf: asOf,
    );
  }

  /// Converts one balance, for a per-account row that shows both its own currency and the home one.
  ConvertedMoney convertOne({
    required Money balance,
    required RateTable table,
    required String homeCurrencyCode,
    required DateKey asOf,
  }) {
    return table.convert(amount: balance, toCurrencyCode: homeCurrencyCode, on: asOf);
  }

  /// Totals [balances] per currency without converting anything.
  ///
  /// The honest answer when no rate is available at all: `₹4,000 + $50` rather than a single number
  /// that silently dropped the dollars. Also what a currency-breakdown panel needs.
  Map<String, Money> totalsByCurrency(Iterable<AccountBalanceInput> balances) {
    final byCode = <String, int>{};
    for (final input in balances) {
      if (!input.includeInNetWorth) continue;
      byCode.update(
        input.balance.currencyCode,
            (running) => running + input.balance.minor,
        ifAbsent: () => input.balance.minor,
      );
    }
    return {
      for (final entry in byCode.entries) entry.key: Money(entry.value, entry.key),
    };
  }
}