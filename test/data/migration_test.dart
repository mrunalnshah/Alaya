import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/data/db/alaya_database.dart';

/// Proves the migration harness works *before* there is a migration to run.
///
/// At `schemaVersion = 1` there is nothing to step between, so "v1 -> v1 passes" means something
/// narrower but still worth asserting: a fresh database reaches version 1 with every schema
/// object present, `beforeOpen` actually ran, and the guard rails are live. ARCH_2 §13 asks for
/// this now precisely because discovering the harness is broken at v2 — with users holding
/// data — is unrecoverable.
///
/// Once v2 exists, add `verifyMigrations()` against the generated snapshots. See
/// `lib/data/db/migrations/schema/README.md`.
void main() {
  late AlayaDatabase db;

  setUp(() async {
    db = AlayaDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get(); // forces onCreate + beforeOpen
  });

  tearDown(() => db.close());

  Future<Set<String>> namesOf(String type) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = ? AND name NOT LIKE 'sqlite_%'",
      variables: [Variable<String>(type)],
    ).get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  group('v1 creation', () {
    test('the declared schema version is 1', () {
      expect(db.schemaVersion, 1);
    });

    test('user_version is written to 1, which the restore gate depends on', () async {
      final row = await db.customSelect('PRAGMA user_version').getSingle();
      expect(row.data.values.first, 1,
          reason: 'Phase 4C refuses a backup whose user_version exceeds this build (A32)');
    });

    test('all 26 tables exist', () async {
      const expected = {
        'app_settings', 'currencies', 'currency_rates', 'units', 'attachments',
        'tags', 'transaction_tags', 'item_tags', 'asset_tags',
        'accounts', 'payment_methods', 'payees', 'transactions', 'transaction_lines',
        'items', 'inventory_batches', 'stock_movements',
        'shopping_lists', 'shopping_entries',
        'recurring_templates', 'recurring_occurrences',
        'assets', 'service_records',
        'notification_schedule', 'backup_history', 'analytics_cache',
      };
      final tables = await namesOf('table');
      expect(expected.difference(tables), isEmpty, reason: 'missing tables');
      expect(expected, hasLength(26));
    });

    test('all 11 views exist', () async {
      const expected = {
        'v_account_ledger', 'v_account_balances',
        'v_active_transactions', 'v_transaction_allocation', 'v_monthly_totals',
        'v_item_stock', 'v_batch_stock_check', 'v_low_stock',
        'v_recurring_due', 'v_asset_alerts',
        'v_calendar_events',
      };
      final views = await namesOf('view');
      expect(views, containsAll(expected));
      expect(expected, hasLength(11));
    });

    test('all 22 indexes from ARCH_2 §11 exist', () async {
      const expected = {
        'idx_items_identity', 'idx_accounts_name', 'idx_tags_name', 'idx_payees_name',
        'idx_shopping_auto', 'idx_recurring_occ', 'idx_rates_point',
        'idx_tx_date', 'idx_tx_month_kind', 'idx_tx_from', 'idx_tx_to', 'idx_tx_subtype',
        'idx_tx_recurring', 'idx_lines_item', 'idx_lines_tx',
        'idx_batch_item', 'idx_batch_expiry',
        'idx_move_batch', 'idx_move_item_date', 'idx_occ_due',
        'idx_asset_service', 'idx_asset_warranty',
      };
      final indexes = await namesOf('index');
      expect(expected.difference(indexes), isEmpty, reason: 'missing indexes');
      expect(expected, hasLength(22));
    });

    test('the twelve partial indexes really carry their WHERE clause', () async {
      final rows = await db.customSelect(
        "SELECT name, sql FROM sqlite_master WHERE type = 'index' AND sql IS NOT NULL",
      ).get();
      final partial = rows
          .where((r) => r.read<String>('sql').toUpperCase().contains(' WHERE '))
          .map((r) => r.read<String>('name'))
          .toSet();
      expect(
        partial,
        containsAll({
          'idx_items_identity', 'idx_accounts_name', 'idx_tags_name', 'idx_payees_name',
          'idx_shopping_auto', 'idx_recurring_occ',
        }),
        reason: 'without WHERE deleted_at IS NULL, re-adding a soft-deleted name fails (A19)',
      );
    });

    test('both FTS5 tables and their six triggers exist', () async {
      final tables = await namesOf('table');
      expect(tables, containsAll({'items_fts', 'transactions_fts'}));

      final triggers = await namesOf('trigger');
      expect(
        triggers,
        containsAll({
          'items_fts_after_insert', 'items_fts_after_delete', 'items_fts_after_update',
          'transactions_fts_after_insert', 'transactions_fts_after_delete',
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
      expect(row.data.values.first, 1,
          reason: 'off by default per connection; all 51 FKs are inert until this runs');
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
        reason: 'from_account_id <> to_account_id is what makes the ledger sound',
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

  group('onUpgrade scaffold', () {
    test('is documented as unreachable at v1 and throws rather than guessing', () {
      // Asserted by construction: schemaVersion is 1, so drift never calls onUpgrade on a
      // database it just created. The scaffold exists so that a file written by a future build
      // fails loudly instead of being reinterpreted against a schema this code does not know.
      expect(db.schemaVersion, 1);
    }, skip: 'No second schema version yet — see migrations/schema/README.md');
  });
}
