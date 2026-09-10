import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Proves the migration harness works, and asserts the shape of a freshly created database.
///
/// **Creating fresh at the current version exercises `onCreate`, not `onUpgrade`** — so nothing in this file
/// runs a migration step, and that has been true since v1. `split_migration_test.dart` is where steps actually
/// execute, against the snapshots in `lib/data/db/migrations/schema/`.
///
/// ARCH_2 §13 asks for this file anyway, because discovering the harness is broken at v2 — with users holding
/// data — is unrecoverable.
///
/// **v5 retires `ItemKind`.** An item's kind became a row in `tags`, scoped by `allowed_in_inventory`, so a
/// user can add `Vegetables` or `Cereals` without a code change. It adds no table, no view and no index: the
/// three counts below are unchanged from v4. What it changes is one column on `items`, which the `v5 columns`
/// group at the bottom asserts — including the absence of the old one, because a migration that added the new
/// column and forgot to drop the old would leave two sources for one value and pass every other test here.
void main() {
  late AlayaDatabase db;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // forces onCreate + beforeOpen
  });

  tearDown(() => db.close());

  Future<Set<String>> namesOf(String type) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
          variables: [Variable<String>(type)],
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  group('v1 creation', () {
    test('the declared schema version is 5', () {
      // **Bumping this is what makes `schema dump` write a v5 snapshot.** Dumping while it still said 4
      // overwrote `drift_schema_v4.json` with a v5-shaped schema — a snapshot that cannot be regenerated,
      // because `items` no longer has the column v4 had.
      expect(db.schemaVersion, 5);
    });

    test(
      'user_version matches the declared version, which the restore gate depends on',
      () async {
        final row = await db.customSelect('PRAGMA user_version').getSingle();
        expect(
          row.data.values.first,
          5,
          reason:
              'Phase 4C refuses a backup whose user_version exceeds this build (A32)',
        );
      },
    );

    test('all 35 tables exist', () async {
      const expected = {
        'app_settings',
        'currencies',
        'currency_rates',
        'units',
        'attachments',
        'tags',
        'transaction_tags',
        'item_tags',
        'asset_tags',
        'accounts',
        'payment_methods',
        'payees',
        'transactions',
        'transaction_lines',
        'items',
        'inventory_batches',
        'stock_movements',
        'shopping_lists',
        'shopping_entries',
        'recipes',
        'recipe_ingredients',
        'recipe_steps',
        'recipe_cook_log',
        'recurring_templates',
        'recurring_occurrences',
        'assets',
        'service_records',
        'notification_schedule',
        'backup_history',
        'analytics_cache',
        'split_groups',
        'split_members',
        'split_expenses',
        'split_shares',
        'split_settlements',
      };
      final tables = await namesOf('table');
      expect(expected.difference(tables), isEmpty, reason: 'missing tables');
      // The count guards the literal set above against a table being deleted from it by accident —
      // `difference` alone would still pass. v5 adds none: a kind became a row in a table that already
      // existed, which is the whole reason it needed no table of its own.
      expect(expected, hasLength(35));
    });

    test('all 15 views exist', () async {
      const expected = {
        'v_account_ledger',
        'v_account_balances',
        'v_active_transactions',
        'v_transaction_allocation',
        'v_monthly_totals',
        'v_item_stock',
        'v_batch_stock_check',
        'v_low_stock',
        'v_recurring_due',
        'v_asset_alerts',
        'v_calendar_events',
        'v_split_expenses',
        'v_split_balances',
        'v_split_group_balances',
        'v_split_activity',
      };
      final views = await namesOf('view');
      expect(views, containsAll(expected));
      expect(expected, hasLength(15));
    });

    test('all 36 indexes from ARCH_2 §11 exist', () async {
      const expected = {
        'idx_items_identity',
        'idx_accounts_name',
        'idx_tags_name',
        'idx_payees_name',
        'idx_shopping_auto',
        'idx_recurring_occ',
        'idx_rates_point',
        'idx_tx_date',
        'idx_tx_month_kind',
        'idx_tx_from',
        'idx_tx_to',
        'idx_tx_subtype',
        'idx_tx_recurring',
        'idx_lines_item',
        'idx_lines_tx',
        'idx_batch_item',
        'idx_batch_expiry',
        'idx_move_batch',
        'idx_move_item_date',
        'idx_occ_due',
        'idx_asset_service',
        'idx_asset_warranty',
        'idx_split_groups_name',
        'idx_split_member',
        'idx_split_share',
        'idx_split_exp_date',
        'idx_split_exp_month',
        'idx_split_exp_group',
        'idx_split_exp_payer',
        'idx_split_exp_tx',
        'idx_split_exp_settle',
        'idx_split_share_exp',
        'idx_split_share_who',
        'idx_split_settle_from',
        'idx_split_settle_to',
        'idx_split_settle_group',
      };
      final indexes = await namesOf('index');
      expect(expected.difference(indexes), isEmpty, reason: 'missing indexes');
      expect(expected, hasLength(36));
    });

    test('the twelve partial indexes really carry their WHERE clause', () async {
      final rows = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
          )
          .get();
      final partial = rows
          .where((r) => r.read<String>('sql').toUpperCase().contains(' WHERE '))
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(
        partial,
        containsAll({
          'idx_items_identity',
          'idx_accounts_name',
          'idx_tags_name',
          'idx_payees_name',
          'idx_shopping_auto',
          'idx_recurring_occ',
        }),
        reason:
            'without WHERE deleted_at IS NULL, re-adding a soft-deleted name fails (A19)',
      );
    });

    test('both FTS5 tables and their six triggers exist', () async {
      final tables = await namesOf('table');
      expect(tables, containsAll({'items_fts', 'transactions_fts'}));

      final triggers = await namesOf('trigger');
      expect(
        triggers,
        containsAll({
          'items_fts_after_insert',
          'items_fts_after_delete',
          'items_fts_after_update',
          'transactions_fts_after_insert',
          'transactions_fts_after_delete',
          'transactions_fts_after_update',
        }),
      );
    });

    test('the bundled SQLite has FTS5 compiled in (risk R3)', () async {
      final rows = await db.customSelect('PRAGMA compile_options').get();
      final options = rows
          .map((r) => r.data.values.first)
          .whereType<String>()
          .map((v) => v.toUpperCase());
      expect(options.any((o) => o.contains('ENABLE_FTS5')), isTrue);
    });
  });

  group('beforeOpen', () {
    test('foreign keys are ON', () async {
      final row = await db.customSelect('PRAGMA foreign_keys').getSingle();
      expect(
        row.data.values.first,
        1,
        reason:
            'off by default per connection; all 51 FKs are inert until this runs',
      );
    });
  });

  group('constraints survive createAll', () {
    test('the transactions shape CHECK rejects a self-transfer', () async {
      await db.customStatement(
        "INSERT INTO currencies (code, name, symbol, decimal_digits, is_enabled, sort_order, "
        "created_at, updated_at) VALUES ('INR','Rupee','R',2,1,0,0,0)",
      );
      await db.customStatement(
        'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
        'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
        "sort_order, created_at, updated_at) VALUES ('a','A','a','cash','INR',0,20260728,0,1,0,0,0)",
      );
      expect(
        () => db.customStatement(
          'INSERT INTO transactions (id, kind, subtype, occurred_at, date_key, month_key, '
          'original_amount_minor, original_currency_code, from_account_id, to_account_id, '
          "needs_review, created_at, updated_at) VALUES "
          "('t','transfer','transferSelf',0,20260728,202607,100,'INR','a','a',0,0,0)",
        ),
        throwsA(anything),
        reason:
            'from_account_id <> to_account_id is what makes the ledger sound',
      );
    });

    test('the month_key CHECK rejects an inconsistent pair', () async {
      await db.customStatement(
        "INSERT INTO currencies (code, name, symbol, decimal_digits, is_enabled, sort_order, "
        "created_at, updated_at) VALUES ('INR','Rupee','R',2,1,0,0,0)",
      );
      await db.customStatement(
        'INSERT INTO accounts (id, name, normalized_name, kind, currency_code, '
        'opening_balance_minor, opening_balance_date_key, is_archived, include_in_net_worth, '
        "sort_order, created_at, updated_at) VALUES ('a','A','a','cash','INR',0,20260728,0,1,0,0,0)",
      );
      expect(
        () => db.customStatement(
          'INSERT INTO transactions (id, kind, subtype, occurred_at, date_key, month_key, '
          'original_amount_minor, original_currency_code, from_account_id, to_account_id, '
          "needs_review, created_at, updated_at) VALUES "
          "('t','deposit','otherIn',0,20260728,202608,100,'INR',NULL,'a',0,0,0)",
        ),
        throwsA(anything),
      );
    });

    test('the stock_movements quantity CHECK rejects zero', () async {
      expect(
        () => db.customStatement(
          'INSERT INTO stock_movements (id, batch_id, item_id, kind, quantity_milli, '
          "occurred_at, date_key, created_at, updated_at) VALUES ('m','b','i','consume',0,0,20260728,0,0)",
        ),
        throwsA(anything),
      );
    });
  });

  group('v3 columns', () {
    // Schema only. This file builds `AlayaDatabase(NativeDatabase.memory())` with **no seeder**, by
    // design — its subject is the shape of the database, not its contents. The units assertion I
    // put here was checking seeded rows in a setUp that deliberately seeds nothing; it belongs in
    // `seed_test.dart`, which does.
    test('items carries both conversion bridges, nullable', () async {
      final columns = await db.customSelect("PRAGMA table_info('items')").get();
      final byName = {
        for (final row in columns)
          row.data['name'] as String: row.data['notnull'] as int,
      };
      expect(byName.containsKey('density_milli_grams_per_ml'), isTrue);
      expect(byName.containsKey('milli_grams_per_piece'), isTrue);
      // Nullable is the whole design: an item with no density keeps reporting "can't compare"
      // rather than guessing, so a NOT NULL here would force a wrong number onto every item.
      expect(
        byName['density_milli_grams_per_ml'],
        0,
        reason: 'must be nullable',
      );
      expect(byName['milli_grams_per_piece'], 0, reason: 'must be nullable');
    });
  });

  group('v5 columns', () {
    // **The only structural change v5 makes, and both halves of it need asserting.** A migration that added
    // `kind_tag_id` and forgot to drop `item_kind` would leave two sources for one value — the thing §6
    // forbids outright — and every other test in this file would still pass.
    test('items carries kind_tag_id, nullable, referencing tags', () async {
      final columns = await db.customSelect("PRAGMA table_info('items')").get();
      final byName = {
        for (final row in columns)
          row.data['name'] as String: row.data['notnull'] as int,
      };

      expect(byName.containsKey('kind_tag_id'), isTrue);
      // Nullable, and after v5's backfill never null in practice. `from4To5` had to add it nullable —
      // there was nothing to default it to before the tags existed — and then filled every row.
      // Tightening it afterwards would mean a second table rebuild for a constraint the data already
      // satisfies, and would leave no way to represent an item whose kind was deleted before the
      // Settings fallback moved it to Other.
      expect(byName['kind_tag_id'], 0, reason: 'must be nullable');

      final fks = await db
          .customSelect("PRAGMA foreign_key_list('items')")
          .get();
      final toTags = fks.where((r) => r.data['table'] == 'tags');
      expect(
        toTags.map((r) => r.data['from']),
        contains('kind_tag_id'),
        reason: 'a kind is a tags row, not a string',
      );
    });

    test('item_kind is gone', () async {
      // **`ItemKind` was six fixed strings and nothing but a code change could add a seventh.** The column
      // is dropped rather than kept beside the new one: a shadow column that drifts is worse than a
      // migration that has to be right once.
      final columns = await db.customSelect("PRAGMA table_info('items')").get();
      final names = columns.map((r) => r.data['name'] as String).toSet();
      expect(names.contains('item_kind'), isFalse);
    });
  });
}
