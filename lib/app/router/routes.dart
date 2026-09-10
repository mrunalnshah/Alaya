/// Every route path in the app, in one place.
///
/// Hand-written: `go_router_builder` cannot resolve alongside `drift_dev` (ARCH_1 §7.1). A literal
/// path anywhere else is a route that drifts silently when this file changes.
abstract final class Routes {
  /// Where the app opens.
  static const String initial = dashboard;

  // ── top level, inside the drawer shell ──

  /// The dashboard.
  static const String dashboard = '/';

  /// The transaction ledger.
  static const String expenses = '/expenses';

  /// The inventory catalogue.
  static const String inventory = '/inventory';

  /// The recipe catalogue.
  static const String recipes = '/recipes';

  /// One recipe.
  static const String recipeDetail = '/recipes/:id';

  /// Builds the path to one recipe.
  static String recipeDetailFor(String id) => '/recipes/$id';

  /// A new recipe.
  ///
  /// Declared before [recipeDetail] and matched before it too: `/recipes/new` would otherwise be
  /// read as a recipe whose id is the word "new" — the same first-match ordering every nested route
  /// in this file depends on.
  static const String recipeNew = '/recipes/new';

  /// Editing an existing recipe.
  static const String recipeEdit = '/recipes/:id/edit';

  /// Builds the path to a recipe's editor.
  static String recipeEditFor(String id) => '/recipes/$id/edit';

  /// Shared expenses, and who owes what.
  ///
  /// **One destination for the whole module.** `/split/groups`, `/split/groups/:groupId` and
  /// `/split/groups/:groupId/settle` were deleted: the groups list is a tab here, and a group's balances
  /// and its settle-up plan are bottom sheets. Nothing in any of the three was an editor, so each route
  /// bought a back arrow, an app bar competing for a 320dp title, and a place for somebody to end up
  /// without knowing how they got there.
  static const String split = '/split';

  /// Splitting a bill, on one screen.
  ///
  /// **Declared before every `/split/:something` route**, for the reason [recipeNew] and
  /// [splitGroupNew] both record: go_router takes the first match rather than the most specific, so a
  /// parameterised sibling declared earlier would read `new` as an id. There is no `/split/:id` route
  /// today; this ordering is what keeps adding one from silently breaking this path.
  static const String splitNew = '/split/new';

  /// A new group.
  ///
  /// Declared before [splitGroupEdit] and matched before it too: `/split/groups/new` would otherwise
  /// be read as a group whose id is the word "new" — the same first-match ordering every nested route
  /// in this file depends on.
  static const String splitGroupNew = '/split/groups/new';

  /// Editing an existing group.
  static const String splitGroupEdit = '/split/groups/:groupId/edit';

  /// Builds the path to a group's editor.
  static String splitGroupEditFor(String id) => '/split/groups/$id/edit';

  /// The shopping lists.
  static const String shopping = '/shopping';

  /// The recurring templates.
  static const String recurring = '/recurring';

  /// The assets and service records.
  static const String services = '/services';

  /// The calendar.
  static const String calendar = '/calendar';

  /// The insights.
  static const String insights = '/insights';

  /// The settings.
  static const String settings = '/settings';

  /// Who you are in a split, and where people can pay you.
  static const String settingsSplit = '/settings/split';

  // ── outside the shell: full-screen editors and the lock ──

  /// The PIN gate.
  static const String lock = '/lock';

  /// The palette workbench.
  static const String themeLab = '/settings/theme-lab';

  /// The first-run flow. Skippable and resumable (ARCH_5 §3 archetype B).
  static const String onboarding = '/onboarding';

  /// The forgotten-PIN flow: recovery code, then a new PIN.
  ///
  /// **Under `/lock`, and that placement is load-bearing.** The redirect permits anything beneath
  /// [lockBranch] while locked; anywhere else and a locked user would be bounced back to `/lock` the
  /// moment they tapped "I have forgotten my PIN", which is the one path they need.
  static const String lockRecovery = '/lock/recovery';

  /// Everything the lock gate lets through while the app is locked.
  static const String lockBranch = lock;

  /// Settings › Accounts.
  static const String settingsAccounts = '/settings/accounts';

  /// Settings › Payment methods.
  static const String settingsPaymentMethods = '/settings/payment-methods';

  /// Settings › Payees.
  static const String settingsPayees = '/settings/payees';

  /// Settings › Tags.
  static const String settingsTags = '/settings/tags';

  /// Settings › Units.
  static const String settingsUnits = '/settings/units';

  /// Settings › Currencies.
  static const String settingsCurrencies = '/settings/currencies';

  /// Settings › Appearance.
  static const String settingsAppearance = '/settings/appearance';

  /// Settings › Security.
  static const String settingsSecurity = '/settings/security';

  /// Settings › Data.
  static const String settingsData = '/settings/data';

  /// Settings › Data › Backup.
  static const String settingsBackup = '/settings/data/backup';

  /// Restoring from a backup file.
  ///
  /// Under Backup rather than beside it: a restore is something you reach *from* the list of backups
  /// you have taken, and the route saying so is what gives it a back arrow to somewhere sensible.
  static const String settingsRestore = '/settings/data/backup/restore';

  /// Settings › Data › Trash.
  static const String settingsTrash = '/settings/data/trash';

  /// Settings › Reminders.
  static const String settingsReminders = '/settings/reminders';

  /// Support Us — rewarded ads and a one-time tip.
  ///
  /// **Outside every settings branch, and that is deliberate.** Ads load when this screen opens and
  /// nowhere else (ARCH_4 §5.1); burying it under Settings › About would make it look like a
  /// disclosure rather than a choice, and putting it in the shell would load an SDK for people who
  /// never asked.
  static const String support = '/support';

  /// Settings › About.
  static const String settingsAbout = '/settings/about';

  /// Setting or changing the PIN, reached from Settings › Security.
  ///
  /// Onboarding does **not** navigate here — it embeds the same widget as a step. A route would fight
  /// the onboarding gate, which sends everything outside `/onboarding` back to it.
  static const String settingsPin = '/settings/security/pin';

  /// A new account.
  static const String accountNew = '/settings/accounts/new';

  /// A new tag.
  static const String tagNew = '/settings/tags/new';

  /// A new unit.
  static const String unitNew = '/settings/units/new';

  /// A new transaction.
  static const String transactionNew = '/expenses/new';

  /// The line items of a new transaction.
  static const String transactionLinesNew = '/expenses/new/lines';

  /// A new item.
  static const String itemNew = '/inventory/new';

  /// A new recurring template.
  static const String recurringNew = '/recurring/new';

  /// A new asset.
  static const String assetNew = '/services/new';

  // ── parameterised ──

  /// Path pattern for one transaction.
  static const String transactionDetailPattern = '/expenses/:transactionId';

  /// Path pattern for editing one transaction.
  static const String transactionEditPattern = '/expenses/:transactionId/edit';

  /// Path pattern for the line items of one transaction.
  static const String transactionLinesPattern =
      '/expenses/:transactionId/lines';

  /// Path pattern for one item.
  static const String itemDetailPattern = '/inventory/:itemId';

  /// Path pattern for editing one item.
  static const String itemEditPattern = '/inventory/:itemId/edit';

  /// Path pattern for adding a batch to one item.
  static const String batchNewPattern = '/inventory/:itemId/batch/new';

  /// Path pattern for editing one batch.
  static const String batchEditPattern = '/inventory/:itemId/batch/:batchId';

  /// Path pattern for one batch's movement history.
  static const String batchHistoryPattern =
      '/inventory/:itemId/batch/:batchId/history';

  /// Path pattern for one shopping list.
  static const String shoppingListPattern = '/shopping/:listId';

  /// Path pattern for turning a shopping list's ticked entries into a purchase.
  static const String shoppingConvertPattern = '/shopping/:listId/convert';

  /// Path pattern for editing one recurring template.
  static const String recurringEditPattern = '/recurring/:templateId/edit';

  /// Path pattern for one template's occurrence history.
  static const String recurringHistoryPattern =
      '/recurring/:templateId/history';

  /// Path pattern for one recurring template.
  static const String recurringDetailPattern = '/recurring/:templateId';

  /// Path pattern for editing one asset.
  static const String assetEditPattern = '/services/:assetId/edit';

  /// Path pattern for a new service record against one asset.
  static const String serviceNewPattern = '/services/:assetId/service/new';

  /// Path pattern for editing one service record.
  static const String serviceEditPattern =
      '/services/:assetId/service/:recordId';

  /// Path pattern for one asset.
  static const String assetDetailPattern = '/services/:assetId';

  /// Path pattern for one calendar day.
  static const String calendarDayPattern = '/calendar/:dateKey';

  /// Path pattern for editing one account.
  static const String accountEditPattern = '/settings/accounts/:accountId';

  /// Path pattern for editing one tag.
  static const String tagEditPattern = '/settings/tags/:tagId';

  /// Path pattern for editing one unit. Keyed by code, which is the `units` primary key (ARCH_2 §2).
  static const String unitEditPattern = '/settings/units/:unitCode';

  /// Path pattern for one analytics drill-down.
  ///
  /// **Outside the shell**, unlike [calendarDayPattern]. A day is a view *of* the month, so it keeps
  /// the drawer and the grid stays behind it (Law U27); a drill-down leaves analytics for the ledger
  /// and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
  ///
  /// **The window is deliberately absent from the path.** ARCH_5 §5.7 keeps a selected range in the
  /// view-model — the URL is the record's identity and nothing else — so a drill-down inherits
  /// whatever range the analytics screen is showing.
  static const String insightsDrillDownPattern =
      '/insights/drill/:drillKind/:drillValue';

  // ── param names, so a builder reading them cannot misspell one ──

  /// The transaction id parameter.
  static const String pTransactionId = 'transactionId';

  /// The item id parameter.
  static const String pItemId = 'itemId';

  /// The batch id parameter.
  static const String pBatchId = 'batchId';

  /// The shopping list id parameter.
  static const String pListId = 'listId';

  /// The recurring template id parameter.
  static const String pTemplateId = 'templateId';

  /// The asset id parameter.
  static const String pAssetId = 'assetId';

  /// The service record id parameter.
  static const String pRecordId = 'recordId';

  /// The calendar date parameter.
  static const String pDateKey = 'dateKey';

  /// The account parameter.
  static const String pAccountId = 'accountId';

  /// The split-group id parameter.
  static const String pGroupId = 'groupId';

  /// The tag parameter.
  static const String pTagId = 'tagId';

  /// The unit parameter — a code, not a UUID.
  static const String pUnitCode = 'unitCode';

  /// The drill-down axis parameter.
  static const String pDrillKind = 'drillKind';

  /// The drill-down value parameter.
  static const String pDrillValue = 'drillValue';

  // ── builders ──

  /// The location for transaction [id].
  static String transactionDetail(String id) => '$expenses/$id';

  /// The location for editing transaction [id].
  static String transactionEdit(String id) => '$expenses/$id/edit';

  /// The location for the line items of transaction [id], or of a new one when null.
  static String transactionLines(String? id) =>
      id == null ? transactionLinesNew : '$expenses/$id/lines';

  /// The location for item [id].
  static String itemDetail(String id) => '$inventory/$id';

  /// The location for editing item [id].
  static String itemEdit(String id) => '$inventory/$id/edit';

  /// The location for adding a batch to item [itemId].
  static String batchNew(String itemId) => '$inventory/$itemId/batch/new';

  /// The location for editing batch [batchId] of item [itemId].
  static String batchEdit(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId';

  /// The location for batch [batchId]'s movement history.
  static String batchHistory(String itemId, String batchId) =>
      '$inventory/$itemId/batch/$batchId/history';

  /// The location for shopping list [id].
  static String shoppingList(String id) => '$shopping/$id';

  /// The location for converting shopping list [id] into a purchase.
  static String shoppingConvert(String id) => '$shopping/$id/convert';

  /// The location for recurring template [id].
  static String recurringDetail(String id) => '$recurring/$id';

  /// The location for editing recurring template [id], or for a new one when null.
  static String recurringEdit(String? id) =>
      id == null ? recurringNew : '$recurring/$id/edit';

  /// The location for template [id]'s occurrence history.
  static String recurringHistory(String id) => '$recurring/$id/history';

  /// The location for asset [id].
  static String assetDetail(String id) => '$services/$id';

  /// The location for editing asset [id], or for a new one when null.
  static String assetEdit(String? id) =>
      id == null ? assetNew : '$services/$id/edit';

  /// The location for a new service record against asset [assetId].
  static String serviceNew(String assetId) => '$services/$assetId/service/new';

  /// The location for editing service record [recordId] of asset [assetId].
  static String serviceEdit(String assetId, String recordId) =>
      '$services/$assetId/service/$recordId';

  /// The location for the calendar on [dateKey].
  static String calendarDay(int dateKey) => '$calendar/$dateKey';

  /// The location for editing [id], or for a new account when null.
  static String accountEdit(String? id) =>
      id == null ? accountNew : '$settingsAccounts/$id';

  /// The location for editing [id], or for a new tag when null.
  static String tagEdit(String? id) =>
      id == null ? tagNew : '$settingsTags/$id';

  /// The location for editing [code], or for a new unit when null.
  static String unitEdit(String? code) =>
      code == null ? unitNew : '$settingsUnits/$code';

  /// The location for the analytics drill-down on [kind] with [value].
  static String insightsDrillDown(String kind, String value) =>
      '$insights/drill/$kind/$value';

  /// The eleven drawer destinations, in drawer order.
  ///
  /// Named for the drawer rather than the shell because `AlayaDrawer` reads it by this name — a route
  /// cannot exist in the router and be missing from the drawer without this list disagreeing.
  ///
  /// **`AlayaDrawer` switches on this list exhaustively, twice**, for a label and an icon, so adding a
  /// destination fails to compile until both know about it. That is the check, and it is why the
  /// count in this sentence is the only part of the arrangement that can go stale — it said "nine"
  /// while the list held eleven.
  static const List<String> drawerDestinations = [
    dashboard,
    expenses,
    inventory,
    recipes,
    split,
    shopping,
    recurring,
    services,
    calendar,
    insights,
    settings,
  ];
}
