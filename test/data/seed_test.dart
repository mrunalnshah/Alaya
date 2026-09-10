import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/ids/uid.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/data/db/alaya_database.dart';
import 'package:alaya/data/db/seed/seed_data.dart';

void main() {
  late AlayaDatabase db;

  setUp(() async {
    final seed = SeedData(
      uids: SequentialUidGenerator(prefix: 'seed'),
      clock: FixedClock(DateTime(2026, 7, 28, 9)),
    );
    db = AlayaDatabase(NativeDatabase.memory(), seeder: seed.insertAll);
    // Force onCreate to run.
    await db.customSelect('SELECT 1').get();
  });

  tearDown(() => db.close());

  group('currencies', () {
    test('five currencies with the correct decimal digits', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.map((r) => r.code).toSet(), {
        'INR',
        'USD',
        'EUR',
        'JPY',
        'CNY',
      });
      final digits = {for (final r in rows) r.code: r.decimalDigits};
      expect(digits['INR'], 2);
      expect(digits['USD'], 2);
      expect(digits['EUR'], 2);
      expect(digits['CNY'], 2);
      expect(
        digits['JPY'],
        0,
        reason: 'yen has no minor unit — this is why nothing hardcodes 100',
      );
    });

    test('all seeded currencies are enabled', () async {
      final rows = await db.select(db.currencies).get();
      expect(rows.every((r) => r.isEnabled), isTrue);
    });
  });

  group('units', () {
    test('eleven units across the three fixed categories', () async {
      final rows = await db.select(db.units).get();
      expect(rows, hasLength(11));

      final byCategory = <UnitCategory, List<String>>{};
      for (final r in rows) {
        byCategory.putIfAbsent(r.category, () => []).add(r.code);
      }
      expect(byCategory[UnitCategory.weight]!.toSet(), {'mg', 'g', 'kg'});
      // The cooking measures are volume, not a category of their own: a tablespoon is 14.787 ml
      // for everything, and what differs between butter and flour is the item's density.
      expect(
        byCategory[UnitCategory.volume]!.toSet(),
        {'ml', 'l', 'tsp', 'tbsp', 'cup'},
      );
      expect(byCategory[UnitCategory.count]!.toSet(), {'pc', 'dozen', 'pack'});
    });

    test('factors are exact integers relative to the milli-base unit', () async {
      final rows = await db.select(db.units).get();
      final factor = {for (final r in rows) r.code: r.factorToBaseMilli};
      expect(factor['mg'], 1);
      expect(factor['g'], 1000);
      expect(factor['kg'], 1000000);
      expect(factor['ml'], 1000);
      expect(factor['l'], 1000000);
      expect(factor['pc'], 1000);
      expect(factor['dozen'], 12000, reason: 'a dozen is exactly 12 pieces');
      expect(factor['pack'], 1000);
      // Milli-millilitres. 1 tsp is 4.92892 ml, 1 tbsp is exactly 3 tsp, 1 cup is 240 ml.
      expect(factor['tsp'], 4929);
      expect(factor['tbsp'], 14787);
      expect(factor['cup'], 240000);
    });

    test('every unit is a system unit', () async {
      final rows = await db.select(db.units).get();
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('payment methods', () {
    test('the five rails from ARCH_2 §14', () async {
      final rows = await db.select(db.paymentMethods).get();
      expect(rows.map((r) => r.name).toSet(), {
        'Cash',
        'UPI',
        'Bank Transfer',
        'Card',
        'Cheque',
      });
      expect(rows.every((r) => r.isSystem), isTrue);
    });
  });

  group('tags — the ARCH_2 §14 scoping matrix, plus v5', () {
    test('twenty system tags', () async {
      final rows = await db.select(db.tags).get();
      // **20, not §14's 18, and the deviation is deliberate.** `Food` and `Other` were added when
      // `ItemKind` retired: an item's kind became a `tags` row, and those two had no tag to become.
      // `Medicine`, `Beauty` and `Household` needed none — they were already in this matrix, and
      // `idx_tags_name` would have rejected a second row with any of those names anyway.
      expect(rows, hasLength(20));
      expect(rows.every((r) => r.isSystem), isTrue);
    });

    test('THE SPEC TEST CASE: Kitchen is inventory + shopping only', () async {
      final kitchen = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Kitchen'))).getSingle();
      expect(kitchen.allowedInInventory, isTrue);
      expect(kitchen.allowedInShopping, isTrue);
      expect(
        kitchen.allowedInDeposit,
        isFalse,
        reason:
            'Kitchen must NOT appear in the deposit tag picker — visible on first launch',
      );
      expect(kitchen.allowedInWithdrawal, isFalse);
      expect(kitchen.allowedInRecurring, isFalse);
      expect(kitchen.allowedInService, isFalse);
    });

    test('every row of the matrix, exactly', () async {
      // (name, deposit, withdrawal, inventory, shopping, recurring, service)
      //
      // **`Food` and `Grocery` both exist, independently.** They overlap and that is the point: a kind is
      // whatever the user finds useful, and collapsing one into the other is the sort of tidiness that makes
      // somebody fight the app. `Food` is also where v5 sends items that carried `ItemKind.food`, so an
      // upgraded install and a fresh one land in the same place.
      //
      // `Other` is last, so `sortOrder` puts a catch-all at the bottom of the inventory list. It is the only
      // tag the app depends on by name: deleting a kind in Settings moves its items here.
      const expected = <(String, bool, bool, bool, bool, bool, bool)>[
        ('Salary', true, false, false, false, true, false),
        ('Gift', true, true, false, false, false, false),
        ('Refund', true, false, false, false, false, false),
        ('Business', true, true, false, false, false, false),
        ('Grocery', false, true, true, true, false, false),
        ('Food', false, true, true, true, false, false),
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
        ('Other', false, true, true, true, false, false),
      ];

      final rows = await db.select(db.tags).get();
      final byName = {for (final r in rows) r.name: r};
      expect(byName.keys.toSet(), expected.map((e) => e.$1).toSet());

      for (final (name, dep, wdr, inv, shop, rec, svc) in expected) {
        final tag = byName[name]!;
        expect(
          [
            tag.allowedInDeposit,
            tag.allowedInWithdrawal,
            tag.allowedInInventory,
            tag.allowedInShopping,
            tag.allowedInRecurring,
            tag.allowedInService,
          ],
          [dep, wdr, inv, shop, rec, svc],
          reason: 'scoping mismatch for "$name"',
        );
      }
    });

    test('the deposit picker shows exactly four tags', () async {
      final rows = await (db.select(
        db.tags,
      )..where((t) => t.allowedInDeposit.equals(true))).get();
      expect(rows.map((r) => r.name).toSet(), {
        'Salary',
        'Gift',
        'Refund',
        'Business',
      });
    });

    test('the inventory picker shows exactly the nine kinds', () async {
      // **The set an item's kind can be chosen from on a fresh install.** Scoping is what lets one `tags`
      // table serve six pickers, and it is why kinds needed no table of their own — a `Rent` tag can never
      // turn up as an inventory kind.
      final rows = await (db.select(
        db.tags,
      )..where((t) => t.allowedInInventory.equals(true))).get();
      expect(rows.map((r) => r.name).toSet(), {
        'Grocery',
        'Food',
        'Vegetables',
        'Household',
        'Kitchen',
        'Beauty',
        'Medicine',
        'Electronics',
        'Other',
      });
    });

    test('Vegetables is nested exactly one level under Grocery', () async {
      final grocery = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Grocery'))).getSingle();
      final vegetables = await (db.select(
        db.tags,
      )..where((t) => t.name.equals('Vegetables'))).getSingle();

      expect(vegetables.parentTagId, grocery.id);
      expect(
        grocery.parentTagId,
        isNull,
        reason: 'nesting is capped at one level',
      );

      // Still the only nested tag after v5. `Food` and `Other` are roots: the kinds a user adds are flat,
      // because "Vegetables inside Food" and "Vegetables beside Food" are different products and the second
      // is the one that was asked for.
      final nested = await (db.select(
        db.tags,
      )..where((t) => t.parentTagId.isNotNull())).get();
      expect(nested.map((r) => r.name), ['Vegetables']);
    });

    test('normalized names match what the Normalizer would produce', () async {
      final rows = await db.select(db.tags).get();
      for (final r in rows) {
        expect(r.normalizedName, r.name.toLowerCase());
      }
    });
  });

  group('accounts', () {
    test('Cash and Bank, zero opening balance, home currency', () async {
      final rows = await db.select(db.accounts).get();
      expect(rows.map((r) => r.name).toSet(), {'Cash', 'Bank'});
      for (final r in rows) {
        expect(r.openingBalanceMinor, 0);
        expect(r.currencyCode, 'INR');
        expect(r.isArchived, isFalse);
        expect(r.includeInNetWorth, isTrue);
      }
    });

    test(
      'the opening balance date is the seed date, not an absent value',
      () async {
        final rows = await db.select(db.accounts).get();
        for (final r in rows) {
          expect(r.openingBalanceDateKey.value, 20260728);
        }
      },
    );

    test('honours a non-default home currency', () async {
      final other = AlayaDatabase(
        NativeDatabase.memory(),
        seeder: SeedData(
          uids: SequentialUidGenerator(),
          clock: FixedClock(DateTime(2026, 7, 28)),
          homeCurrencyCode: 'JPY',
        ).insertAll,
      );
      addTearDown(other.close);

      final rows = await other.select(other.accounts).get();
      expect(rows.every((r) => r.currencyCode == 'JPY'), isTrue);
    });
  });

  group('shopping list', () {
    test('exactly one, marked default', () async {
      final rows = await db.select(db.shoppingLists).get();
      expect(rows, hasLength(1));
      expect(rows.single.isDefault, isTrue);
      expect(rows.single.isArchived, isFalse);
    });
  });

  group('app settings', () {
    test('homeCurrencyCode is stored', () async {
      final row = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals('homeCurrencyCode'))).getSingle();
      expect(row.value, 'INR');
      expect(row.valueType, 'string');
    });

    test('defaultAccountId points at a real account', () async {
      final setting = await (db.select(
        db.appSettings,
      )..where((t) => t.key.equals('defaultAccountId'))).getSingle();
      final account = await (db.select(
        db.accounts,
      )..where((t) => t.id.equals(setting.value))).getSingle();
      expect(
        account.name,
        'Cash',
        reason:
            'accounts has no isDefault column, so the default lives in app_settings',
      );
    });
  });

  group('determinism', () {
    test(
      'seeding twice with the same generator and clock produces identical ids',
      () async {
        Future<List<String>> seedIds() async {
          final fresh = AlayaDatabase(
            NativeDatabase.memory(),
            seeder: SeedData(
              uids: SequentialUidGenerator(prefix: 'seed'),
              clock: FixedClock(DateTime(2026, 7, 28, 9)),
            ).insertAll,
          );
          addTearDown(fresh.close);
          final tags = await fresh.select(fresh.tags).get();
          return tags.map((t) => t.id).toList();
        }

        expect(await seedIds(), await seedIds());
      },
    );
  });

  group('referential integrity', () {
    test('foreign keys are enforced after beforeOpen ran', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        row.data.values.first,
        1,
        reason:
            'SQLite defaults this OFF per connection — beforeOpen must turn it on',
      );
    });

    test('an account referencing an unknown currency is rejected', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
          'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
          "sort_order, created_at, updated_at) VALUES ('x','X','x','cash','ZZZ',0,20260728,0,1,0,0,0)",
        ),
        throwsA(anything),
      );
    });
  });
}
