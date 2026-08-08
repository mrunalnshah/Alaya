import 'package:drift/drift.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';

/// Inserts the first-launch reference data described in ARCH_2 §14.
///
/// [uids] and [clock] are injected so a test can seed a byte-identical database twice — with
/// `SequentialUidGenerator` and `FixedClock` from Phase 1A the whole seed becomes deterministic,
/// which is what makes `seed_test.dart` able to assert on exact rows.
///
/// [homeCurrencyCode] is passed in rather than detected here: locale is a presentation concern,
/// and reaching for `dart:ui` inside `data/` to find it would drag platform bindings into a layer
/// that has no business knowing about them. `bootstrap.dart` supplies it in Phase 5.
final class SeedData {
  /// Creates a seeder.
  const SeedData({
    required this.uids,
    required this.clock,
    this.homeCurrencyCode = 'INR',
  });

  /// Generates the UUIDv7 primary keys.
  final UidGenerator uids;

  /// Supplies `createdAt` / `updatedAt` and the opening-balance date.
  final Clock clock;

  /// Currency for the two seeded accounts and the `homeCurrencyCode` setting.
  final String homeCurrencyCode;

  /// Inserts everything, in one transaction so a partial seed is impossible (Law L14).
  Future<void> insertAll(AlayaDatabase db) async {
    await db.transaction(() async {
      await _insertCurrencies(db);
      await _insertUnits(db);
      await _insertPaymentMethods(db);
      final tagIds = await _insertTags(db);
      final accountIds = await _insertAccounts(db);
      await _insertShoppingList(db);
      await _insertSettings(db, defaultAccountId: accountIds.first);
      assert(tagIds.length == 18, 'ARCH_2 §14 specifies exactly 18 system tags');
    });
  }

  int get _now => clock.nowUtcMillis();

  Future<void> _insertCurrencies(AlayaDatabase db) async {
    // `decimalDigits` is the reason nothing in the app hardcodes 100 (ARCH_1 §4.1). JPY is 0.
    const rows = [
      ('INR', 'Indian Rupee', '\u20B9', 2),
      ('USD', 'US Dollar', '\u0024', 2),
      ('EUR', 'Euro', '\u20AC', 2),
      ('JPY', 'Japanese Yen', '\u00A5', 0),
      ('CNY', 'Chinese Yuan', 'CN\u00A5', 2),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (code, name, symbol, decimalDigits) = rows[i];
      await db.into(db.currencies).insert(
        CurrenciesCompanion.insert(
          code: code,
          name: name,
          symbol: symbol,
          decimalDigits: decimalDigits,
          isEnabled: true,
          sortOrder: i,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
  }

  Future<void> _insertUnits(AlayaDatabase db) async {
    // factorToBaseMilli is exact integer milli-base-units per one of this unit (Law L2):
    // the base unit itself is 1000, so `kg` is 1000 x 1000 and `mg` is one thousandth of `g`.
    const rows = [
      ('mg', UnitCategory.weight, 1, 'Milligram'),
      ('g', UnitCategory.weight, 1000, 'Gram'),
      ('kg', UnitCategory.weight, 1000000, 'Kilogram'),
      ('ml', UnitCategory.volume, 1000, 'Millilitre'),
      ('l', UnitCategory.volume, 1000000, 'Litre'),
      ('pc', UnitCategory.count, 1000, 'Piece'),
      ('dozen', UnitCategory.count, 12000, 'Dozen'),
      // `pack` seeds at 1 pack = 1 pc. ARCH_1 §5.3 is explicit that a unit needs a statable
      // factor, and "one packet" only has one if you treat the packet as the countable thing —
      // which is the common case ("3 packs of noodles"). A user who means "1 pack = 8 pieces"
      // edits the factor; a user who cannot state any factor should create a separate Item.
      ('pack', UnitCategory.count, 1000, 'Pack'),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (code, category, factor, displayName) = rows[i];
      await db.into(db.units).insert(
        UnitsCompanion.insert(
          code: code,
          category: category,
          factorToBaseMilli: factor,
          displayName: displayName,
          isSystem: true,
          sortOrder: i,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
  }

  Future<void> _insertPaymentMethods(AlayaDatabase db) async {
    const rows = [
      ('Cash', PaymentMethodKind.cash),
      ('UPI', PaymentMethodKind.upi),
      ('Bank Transfer', PaymentMethodKind.bankTransfer),
      ('Card', PaymentMethodKind.card),
      ('Cheque', PaymentMethodKind.cheque),
    ];
    for (var i = 0; i < rows.length; i++) {
      final (name, kind) = rows[i];
      await db.into(db.paymentMethods).insert(
        PaymentMethodsCompanion.insert(
          id: uids.generate(),
          name: name,
          kind: kind,
          isSystem: true,
          sortOrder: i,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
  }

  /// Inserts the 18 system tags with the exact `allowedIn*` matrix from ARCH_2 §14.
  ///
  /// This matrix is visible on first launch, so getting it wrong is immediately user-facing. The
  /// spec's own test case is `Kitchen`: inventory and shopping only, and it must **not** appear
  /// in the deposit picker.
  Future<List<String>> _insertTags(AlayaDatabase db) async {
    // (name, deposit, withdrawal, inventory, shopping, recurring, service)
    const matrix = <(String, bool, bool, bool, bool, bool, bool)>[
      ('Salary', true, false, false, false, true, false),
      ('Gift', true, true, false, false, false, false),
      ('Refund', true, false, false, false, false, false),
      ('Business', true, true, false, false, false, false),
      ('Grocery', false, true, true, true, false, false),
      ('Vegetables', false, true, true, true, false, false),
      ('Household', false, true, true, true, false, false),
      ('Kitchen', false, false, true, true, false, false),
      ('Beauty', false, true, true, true, false, false),
      ('Medicine', false, true, true, true, false, false),
      ('Electronics', false, true, true, true, false, true),
      ('Utilities', false, true, false, false, true, true),
      ('Rent', false, true, false, false, true, false),
      ('Subscription', false, true, false, false, true, true),
      ('Transport', false, true, false, false, true, false),
      ('Health', false, true, false, false, true, true),
      ('Education', false, true, false, false, true, false),
      ('Maintenance', false, true, false, false, true, true),
    ];

    final ids = <String>[];
    String? groceryId;
    for (var i = 0; i < matrix.length; i++) {
      final (name, dep, wdr, inv, shop, rec, svc) = matrix[i];
      final id = uids.generate();
      ids.add(id);
      await db.into(db.tags).insert(
        TagsCompanion.insert(
          id: id,
          name: name,
          // Matches Phase 1A's Normalizer for these names, all of which are single
          // lowercase-able words with no diacritics or punctuation.
          normalizedName: name.toLowerCase(),
          // `Vegetables` is the one nested tag in the seed, exactly one level under
          // `Grocery` (ARCH_2 §3). Depth beyond one level is rejected in the repository.
          parentTagId: Value(name == 'Vegetables' ? groceryId : null),
          allowedInDeposit: dep,
          allowedInWithdrawal: wdr,
          allowedInInventory: inv,
          allowedInShopping: shop,
          allowedInRecurring: rec,
          allowedInService: svc,
          isSystem: true,
          sortOrder: i,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
      if (name == 'Grocery') groceryId = id;
    }
    return ids;
  }

  /// Inserts `Cash` and `Bank`, both in [homeCurrencyCode] with a zero opening balance.
  ///
  /// The returned list is ordered, and the first entry (`Cash`) becomes the default account.
  /// Note there is no `isDefault` column on `accounts` — ARCH_2 §4 has none — so "the default
  /// account" lives in `app_settings` under `defaultAccountId`, which is also what lets quick-add
  /// fall back to it after the last-used account (ARCH_2 §4.1).
  Future<List<String>> _insertAccounts(AlayaDatabase db) async {
    final today = clock.today();
    const rows = [
      ('Cash', AccountKind.cash),
      ('Bank', AccountKind.bank),
    ];
    final ids = <String>[];
    for (var i = 0; i < rows.length; i++) {
      final (name, kind) = rows[i];
      final id = uids.generate();
      ids.add(id);
      await db.into(db.accounts).insert(
        AccountsCompanion.insert(
          id: id,
          name: name,
          normalizedName: name.toLowerCase(),
          kind: kind,
          currencyCode: homeCurrencyCode,
          // Zero, not unknown. Onboarding (Phase 8A) collects the user's real opening
          // balances; until then the balance is honestly zero rather than absent
          // (anomaly A03).
          openingBalanceMinor: 0,
          openingBalanceDateKey: today,
          isArchived: false,
          includeInNetWorth: true,
          sortOrder: i,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
    return ids;
  }

  Future<void> _insertShoppingList(AlayaDatabase db) async {
    await db.into(db.shoppingLists).insert(
      ShoppingListsCompanion.insert(
        id: uids.generate(),
        name: 'Shopping List',
        isDefault: true,
        isArchived: false,
        createdAt: _now,
        updatedAt: _now,
      ),
    );
  }

  Future<void> _insertSettings(
      AlayaDatabase db, {
        required String defaultAccountId,
      }) async {
    final settings = <String, (String, String)>{
      'homeCurrencyCode': (homeCurrencyCode, 'string'),
      'defaultAccountId': (defaultAccountId, 'string'),
    };
    for (final entry in settings.entries) {
      final (value, valueType) = entry.value;
      await db.into(db.appSettings).insert(
        AppSettingsCompanion.insert(
          key: entry.key,
          value: value,
          valueType: valueType,
          createdAt: _now,
          updatedAt: _now,
        ),
      );
    }
  }
}
