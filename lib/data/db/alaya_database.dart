import 'package:drift/drift.dart';

// The generated `alaya_database.g.dart` is a `part` of this library, and a part file cannot
// declare its own imports. Everything the generated code names must therefore be imported
// HERE, including types that this file's own source never mentions: the row classes expose
// `DateKey` and every enum, and the generated table classes instantiate every converter.
// Dart imports are not transitive, so importing the table files alone is not enough.
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/ops_enums.dart';
import 'package:alaya/core/enums/recurring_enums.dart';
import 'package:alaya/core/enums/service_enums.dart';
import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/data/db/converters/date_key_converter.dart';
import 'package:alaya/data/db/converters/enum_converters.dart';
import 'package:alaya/data/db/migrations/migration_strategy.dart';
import 'package:alaya/data/db/tables/inventory_tables.dart';
import 'package:alaya/data/db/tables/meta_tables.dart';
import 'package:alaya/data/db/tables/money_tables.dart';
import 'package:alaya/data/db/tables/ops_tables.dart';
import 'package:alaya/data/db/tables/recipe_tables.dart';
import 'package:alaya/data/db/tables/recurring_tables.dart';
import 'package:alaya/data/db/tables/service_tables.dart';
import 'package:alaya/data/db/tables/shopping_tables.dart';
import 'package:alaya/data/db/tables/split_tables.dart';
import 'package:alaya/data/db/tables/tag_tables.dart';

part 'alaya_database.g.dart';

/// The Alaya database. Plaintext by design (ARCH_1 §2.1): no SQLCipher, no `PRAGMA key`, and
/// `android:allowBackup="false"` in the manifest is what stops Android replicating it to Drive.
///
/// The `include` set is what brings the 15 views, 36 indexes and 2 FTS tables into
/// `Migrator.createAll()`. Without those entries the `.drift` files are inert: the schema would
/// create bare tables and every repository read would fail against a view that does not exist.
///
/// Phases 2A-2C add the DAOs on top of this.
@DriftDatabase(
  tables: [
    // Meta & reference
    AppSettings,
    Currencies,
    CurrencyRates,
    Units,
    Attachments,
    // Tags
    Tags,
    TransactionTags,
    ItemTags,
    AssetTags,
    // Money
    Accounts,
    PaymentMethods,
    Payees,
    Transactions,
    TransactionLines,
    // Inventory
    Items,
    InventoryBatches,
    StockMovements,
    // Shopping
    ShoppingLists,
    ShoppingEntries,
    // Recurring
    RecurringTemplates,
    RecurringOccurrences,
    // Service
    Assets,
    ServiceRecords,
    // Recipes
    Recipes,
    RecipeIngredients,
    RecipeSteps,
    RecipeCookLog,
    // Split
    SplitGroups,
    SplitMembers,
    SplitExpenses,
    SplitShares,
    SplitSettlements,
    // Ops
    NotificationSchedule,
    BackupHistory,
    AnalyticsCache,
  ],
  include: {
    'views/account_views.drift',
    'views/transaction_views.drift',
    'views/inventory_views.drift',
    'views/schedule_views.drift',
    'views/calendar_view.drift',
    'views/split_views.drift',
    'indexes.drift',
    'fts.drift',
  },
)
class AlayaDatabase extends _$AlayaDatabase {
  /// Opens the database over [executor], optionally running [seeder] on first creation.
  ///
  /// Never construct this directly outside `connection/open_database.dart` — Law L10 requires
  /// exactly one open path, and that file is it.
  ///
  /// [seeder] is null in most tests, which want a bare schema, and non-null in production so a
  /// first launch arrives with currencies, units, tags and accounts already present.
  AlayaDatabase(super.executor, {this.seeder});

  /// Populates a freshly created database. See `seed/seed_data.dart`.
  final DatabaseSeeder? seeder;

  @override
  // v4 is the Split module: five tables, fourteen indexes, four new views, and one existing view
  // that changed shape. `from3To4` in `migration_strategy.dart` is the step; it is the first in this
  // project to create an index or drop a view, because `from1To2` only created tables and `from2To3`
  // only added columns.
  //
  // The step file and the v4 snapshot are GENERATED — see the two commands in this phase's notes.
  // Editing `schema_steps.dart` by hand puts the generated and declared schemas out of step, which
  // drift detects only when a real device tries to migrate.
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration =>
      buildMigrationStrategy(this, seeder: seeder);
}
