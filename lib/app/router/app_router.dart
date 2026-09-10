import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/lock/presentation/screens/recovery_flow.dart';
import 'package:alaya/features/onboarding/presentation/screens/onboarding_flow.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_detail_screen.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_editor_screen.dart';
import 'package:alaya/features/recipe/presentation/screens/recipe_list_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/about_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/account_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/appearance_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/data_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/split_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tag_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/unit_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_bill_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_group_editor_screen.dart';
import 'package:alaya/features/split/presentation/screens/split_home_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/support/presentation/widgets/support_action.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// Whether the first-run flow still has to happen, consulted on every navigation.
typedef OnboardingGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The eleven drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day
/// route: a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves
/// analytics for the ledger and needs a back arrow, which a shell owning a drawer can never imply.
///
/// **`_detail` was removed in 7B and `_destination` in 8A.** Both were declared and then called by
/// nothing once the last placeholder became a real screen, and `very_good_analysis` reports
/// `unused_element` on each. `_DetailScaffold` below is now in the same position and is kept only
/// because removing it is a separate decision from adding a route.
///
/// **Phase 8A: the redirect gained an onboarding gate and a `refreshListenable`, and its lock test
/// became a prefix test.** The equality test was harmless while `/lock` was a leaf and silently made
/// `/lock/recovery` unreachable the moment one existed.
abstract final class AppRouter {
  /// Builds the router.
  static GoRouter build({
    LockGate? isLocked,
    OnboardingGate? needsOnboarding,
    Listenable? refreshListenable,
    String initialLocation = Routes.initial,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final locked = isLocked ?? () => false;
    final onboarding = needsOnboarding ?? () => false;
    return GoRouter(
      initialLocation: initialLocation,
      navigatorKey: navigatorKey,
      debugLogDiagnostics: false,
      // **Phase 8A: without this the gates are decorative.** A `redirect` runs on navigation and
      // whenever `refreshListenable` fires, and nothing else — so unlocking updated the state and left
      // the user on the lock screen looking at a correct boolean. `routerRefreshProvider` supplies it.
      refreshListenable: refreshListenable,
      redirect: (context, state) {
        final location = state.matchedLocation;
        // **A prefix test, not an equality test, and that is a fix rather than a refinement.** The
        // gate previously compared against `Routes.lock` exactly, which was harmless while `/lock` was
        // a leaf — and silently unreachable the moment 8A added `/lock/recovery` beneath it. A locked
        // user tapping "I have forgotten my PIN" would have been bounced straight back to the screen
        // they were trying to leave.
        final inLockBranch =
            location == Routes.lockBranch ||
            location.startsWith('${Routes.lockBranch}/');
        if (locked()) return inLockBranch ? null : Routes.lock;
        if (inLockBranch) return Routes.dashboard;
        // **Checked after the lock, not before.** A lock protects data that onboarding is about to add
        // to; asking somebody to finish setting up an app they cannot yet open would be the wrong
        // order.
        if (onboarding()) {
          return location == Routes.onboarding ? null : Routes.onboarding;
        }
        if (location == Routes.onboarding) return Routes.dashboard;
        return null;
      },
      routes: [
        // Literal before parameterised, and **`/lock/recovery` before `/lock`**: go_router walks this
        // list in order, and a `/lock` declared first would match the prefix and swallow its own child.
        GoRoute(
          path: Routes.lockRecovery,
          builder: (context, state) => const RecoveryFlow(),
        ),
        GoRoute(
          path: Routes.lock,
          builder: (context, state) => const LockScreen(),
        ),
        // No `_DetailScaffold`: onboarding brings its own chrome, and a back arrow into a shell the
        // user has not reached yet would be a way out of a flow with nothing behind it.
        GoRoute(
          path: Routes.onboarding,
          builder: (context, state) => const OnboardingFlow(),
        ),
        ShellRoute(
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed
          // to a pathless `ShellRoute`'s builder reports `/` for every screen inside it.
          builder: (context, state, child) => _ShellScaffold(child: child),
          routes: [
            GoRoute(
              path: Routes.dashboard,
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: Routes.expenses,
              builder: (context, state) => const TransactionListScreen(),
            ),
            GoRoute(
              path: Routes.inventory,
              builder: (context, state) => const InventoryListScreen(),
            ),
            GoRoute(
              path: Routes.recipes,
              builder: (context, state) => const RecipeListScreen(),
            ),
            GoRoute(
              path: Routes.split,
              builder: (context, state) => const SplitHomeScreen(),
            ),
            GoRoute(
              path: Routes.shopping,
              builder: (context, state) => const ShoppingListScreen(),
            ),
            GoRoute(
              path: Routes.recurring,
              builder: (context, state) => const TemplateListScreen(),
            ),
            GoRoute(
              path: Routes.services,
              builder: (context, state) => const AssetListScreen(),
            ),
            GoRoute(
              path: Routes.calendar,
              builder: (context, state) => const CalendarScreen(),
              routes: [
                // A sub-route rather than a sibling detail route: a day is a view of the month, so it
                // keeps the drawer shell and the month stays behind it (Law U27).
                GoRoute(
                  path: ':${Routes.pDateKey}',
                  builder: (context, state) => CalendarScreen(
                    initialDay: _dateKeyParam(
                      state.pathParameters[Routes.pDateKey],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: Routes.insights,
              builder: (context, state) => const AnalyticsHomeScreen(),
            ),
            GoRoute(
              path: Routes.settings,
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
        GoRoute(
          path: Routes.transactionNew,
          builder: (context, state) => const TransactionEditorScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesNew,
          builder: (context, state) => const LineItemsScreen(),
        ),
        GoRoute(
          path: Routes.transactionLinesPattern,
          builder: (context, state) => LineItemsScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionEditPattern,
          builder: (context, state) => TransactionEditorScreen(
            transactionId: state.pathParameters[Routes.pTransactionId],
          ),
        ),
        GoRoute(
          path: Routes.transactionDetailPattern,
          builder: (context, state) => TransactionDetailScreen(
            transactionId: state.pathParameters[Routes.pTransactionId]!,
          ),
        ),
        // **Outside the shell, all of them.** `AppBar` resolves its leading slot by checking
        // `hasDrawer` before `canPop`, so a screen rendered inside the drawer shell gets a hamburger
        // where a back arrow belongs (Law U18). Only `/split` itself is a destination; these are
        // reached from it.
        //
        // `/split/new` is declared first. There is no `/split/:id` route today, so nothing can swallow
        // it — but go_router takes the first match rather than the most specific, and the day somebody
        // adds one this ordering is what stops the bill screen quietly becoming unreachable.
        GoRoute(
          path: Routes.splitNew,
          // **`extra` carries the split being edited.** A `/split/:id/edit` route would be a fifth on a module
          // that just went from eight routes to four, and this screen's draft is in-memory — so a deep
          // link into a half-edited split could not restore what the URL promised.
          builder: (context, state) =>
              SplitBillScreen(expenseId: state.extra as String?),
        ),
        // Literal before parameterised, or `:groupId` swallows the word `new`.
        GoRoute(
          path: Routes.splitGroupNew,
          builder: (context, state) => const SplitGroupEditorScreen(),
        ),
        GoRoute(
          path: Routes.splitGroupEdit,
          builder: (context, state) => SplitGroupEditorScreen(
            groupId: state.pathParameters[Routes.pGroupId],
          ),
        ),
        GoRoute(
          path: Routes.settingsSplit,
          builder: (context, state) => const SplitSettingsScreen(),
        ),
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) =>
              BatchEditorScreen(itemId: state.pathParameters[Routes.pItemId]!),
        ),
        GoRoute(
          path: Routes.batchHistoryPattern,
          builder: (context, state) => BatchHistoryScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId]!,
          ),
        ),
        GoRoute(
          path: Routes.batchEditPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
            batchId: state.pathParameters[Routes.pBatchId],
          ),
        ),
        GoRoute(
          path: Routes.itemEditPattern,
          builder: (context, state) =>
              ItemEditorScreen(itemId: state.pathParameters[Routes.pItemId]),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) =>
              ItemDetailScreen(itemId: state.pathParameters[Routes.pItemId]!),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) =>
              ShoppingListScreen(listId: state.pathParameters[Routes.pListId]),
        ),
        GoRoute(
          path: Routes.recurringNew,
          builder: (context, state) => const TemplateBuilderScreen(),
        ),
        GoRoute(
          path: Routes.recurringHistoryPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.recurringEditPattern,
          builder: (context, state) => TemplateBuilderScreen(
            templateId: state.pathParameters[Routes.pTemplateId],
          ),
        ),
        GoRoute(
          path: Routes.recurringDetailPattern,
          builder: (context, state) => OccurrenceHistoryScreen(
            templateId: state.pathParameters[Routes.pTemplateId]!,
          ),
        ),
        GoRoute(
          path: Routes.assetNew,
          builder: (context, state) => const AssetEditorScreen(),
        ),
        GoRoute(
          path: Routes.serviceNewPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.serviceEditPattern,
          builder: (context, state) => ServiceEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
            recordId: state.pathParameters[Routes.pRecordId],
          ),
        ),
        GoRoute(
          path: Routes.assetEditPattern,
          builder: (context, state) =>
              AssetEditorScreen(assetId: state.pathParameters[Routes.pAssetId]),
        ),
        GoRoute(
          path: Routes.assetDetailPattern,
          builder: (context, state) => AssetDetailScreen(
            assetId: state.pathParameters[Routes.pAssetId]!,
          ),
        ),
        GoRoute(
          path: Routes.insightsDrillDownPattern,
          builder: (context, state) => DrillDownScreen(
            // Parsed rather than trusted: this route is deep-linkable, so an unknown axis has to reach
            // the screen as null and be explained there rather than throwing in a builder.
            spec: DrillDownSpec.parse(
              kind: state.pathParameters[Routes.pDrillKind],
              value: state.pathParameters[Routes.pDrillValue],
            ),
          ),
        ),
        // **Every settings branch sits outside the shell.** `/settings` is the drawer destination; its
        // children are reached *from* it and need a back arrow, which a shell owning a drawer can never
        // imply (Law U18). Each one brings its own `Scaffold` and app bar, so none uses
        // `_DetailScaffold` — a catalogue needs a pinned search field and an overflow of its own, which
        // that wrapper does not offer (ARCH_5 §3 archetype D).
        //
        // The literal children of `/settings/accounts`, `/settings/tags` and `/settings/units` are
        // declared before their parameterised siblings, or `:accountId` swallows the word `new`.
        GoRoute(
          path: Routes.accountNew,
          builder: (context, state) => const AccountEditorScreen(),
        ),
        GoRoute(
          path: Routes.accountEditPattern,
          builder: (context, state) => AccountEditorScreen(
            accountId: state.pathParameters[Routes.pAccountId],
          ),
        ),
        GoRoute(
          path: Routes.settingsAccounts,
          builder: (context, state) => const AccountsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.tagNew,
          builder: (context, state) => const TagEditorScreen(),
        ),
        GoRoute(
          path: Routes.tagEditPattern,
          builder: (context, state) =>
              TagEditorScreen(tagId: state.pathParameters[Routes.pTagId]),
        ),
        GoRoute(
          path: Routes.settingsTags,
          builder: (context, state) => const TagsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.unitNew,
          builder: (context, state) => const UnitEditorScreen(),
        ),
        GoRoute(
          path: Routes.unitEditPattern,
          builder: (context, state) => UnitEditorScreen(
            unitCode: state.pathParameters[Routes.pUnitCode],
          ),
        ),
        GoRoute(
          path: Routes.settingsUnits,
          builder: (context, state) => const UnitsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPaymentMethods,
          builder: (context, state) => const PaymentMethodsSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsPayees,
          builder: (context, state) => const PayeesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsCurrencies,
          builder: (context, state) => const CurrenciesSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAppearance,
          builder: (context, state) => const AppearanceSettingsScreen(),
        ),
        // `/settings/security/pin` before `/settings/security`, for the same ordering reason.
        GoRoute(
          path: Routes.settingsPin,
          builder: (context, state) => const PinSetupFlow(),
        ),
        GoRoute(
          path: Routes.settingsSecurity,
          builder: (context, state) => const SecuritySettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsData,
          builder: (context, state) => const DataSettingsScreen(),
        ),
        GoRoute(
          path: Routes.settingsAbout,
          builder: (context, state) => const AboutSettingsScreen(),
        ),
        // Phase 8B. `/settings/data/backup/restore` before `/settings/data/backup`, and both before
        // `/settings/data`, for the same first-match reason every other nesting here has.
        GoRoute(
          path: Routes.settingsRestore,
          builder: (context, state) => const RestoreFlow(),
        ),
        GoRoute(
          // Before `recipeDetail`, or `/recipes/new` matches `/recipes/:id` and the editor never
          // opens — go_router takes the first match, not the most specific.
          path: Routes.recipeNew,
          builder: (context, state) => const RecipeEditorScreen(recipeId: ''),
        ),
        GoRoute(
          path: Routes.recipeEdit,
          builder: (context, state) =>
              RecipeEditorScreen(recipeId: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          // Outside the shell, like every other drill-down: a detail screen owns its own app bar
          // and back arrow rather than inheriting the shell's.
          path: Routes.recipeDetail,
          builder: (context, state) =>
              RecipeDetailScreen(recipeId: state.pathParameters['id'] ?? ''),
        ),
        GoRoute(
          path: Routes.settingsBackup,
          builder: (context, state) => const BackupScreen(),
        ),
        GoRoute(
          path: Routes.settingsTrash,
          builder: (context, state) => const TrashScreen(),
        ),
        GoRoute(
          path: Routes.settingsReminders,
          builder: (context, state) => const RemindersScreen(),
        ),
        GoRoute(
          path: Routes.support,
          builder: (context, state) => const SupportScreen(),
        ),
      ],
    );
  }
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so
    // the `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's —
    // and a pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside
    // the shell therefore looked like the dashboard: the home action never rendered, `AlayaDrawer`
    // highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location
    // no matter which builder asks.
    final here = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.path;
    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see:
    // every shell screen except the dashboard carries a home action. The hamburger keeps its slot,
    // because the drawer is still how you move between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        // **The title is the second way home, and it costs nothing.** Somebody reading "Inventory" at
        // the top of the screen is already looking at the name of where they are; tapping it to leave
        // is the one gesture that needs no new affordance and no explanation once found.
        //
        // Not a replacement for the button — an undiscoverable path cannot be the only path. It is the
        // one a returning user finds by accident and then keeps using, which is the best kind.
        title: here == Routes.dashboard
            ? Text(AlayaDrawer.titleFor(context, here))
            : InkWell(
                onTap: () => context.go(Routes.dashboard),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: AlayaSpacing.xs,
                    horizontal: AlayaSpacing.xxs,
                  ),
                  child: Text(AlayaDrawer.titleFor(context, here)),
                ),
              ),
        actions: [
          // Home moved to a floating button; see [_HomeFab]. The ternary that was here read
          // `canPop() ? pop() : go(dashboard)`, and **the first branch could never run** — the comment
          // above explains why `canPop` is always false from a `ShellRoute` builder.
          //
          // `SupportAction` loads nothing until pressed. ARCH_4 §5.1 said rewarded ads live "only in
          // Support Us"; this amends the entry point and keeps the constraint — no `MobileAds`
          // initialisation, no consent fetch and no ad request happen on build, so a user who never
          // taps it never has an advertising identifier collected.
          const SupportAction(),
        ],
      ),
      body: child,
      // **In the shell, so it reaches every screen** — which is what makes it worth having. Only the
      // dashboard defines an expandable FAB, so "above the existing FAB" would have placed Home on the
      // one screen where you are already home.
      //
      // `here`, not `canPop`: this context cannot see the shell's navigator, and the leaf path can.
      floatingActionButton: here == Routes.dashboard ? null : const _HomeFab(),
      // `startFloat` — bottom-left, diagonally opposite where a screen's own FAB sits. Two buttons in
      // one corner is a collision; using the other corner removes it rather than managing it: no
      // stacking, no offset arithmetic, and nothing to interact with an unfolding menu.
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
    );
  }
}

class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: child,
  );
}

/// Parses a `:dateKey` path parameter, or null when it is absent or not a date key.
///
/// A malformed deep link opens the calendar on today rather than throwing — the route is reachable
/// from outside the app.
DateKey? _dateKeyParam(String? raw) {
  final value = int.tryParse(raw ?? '');
  if (value == null) return null;
  final year = value ~/ 10000;
  final month = (value ~/ 100) % 100;
  final day = value % 100;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  // Round-trip through `fromYmd`, which normalises overflow through `DateTime.utc`: 20260230 comes
  // back as 20260302 and fails this check, where a digit-range test alone would accept it.
  final probe = DateKey.fromYmd(year, month, day);
  return probe.value == value ? probe : null;
}

/// A floating way back to the dashboard.
///
/// **Small, and bottom-left.** A screen's own FAB is its primary action and owns the bottom-right
/// corner; this is navigation, which is secondary, so it takes the opposite corner and a smaller
/// footprint.
///
/// `go`, not `push`: the dashboard is a peer destination, and pushing it would grow a stack of
/// dashboards behind the user (Law U27).
class _HomeFab extends StatelessWidget {
  const _HomeFab();

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final scheme = Theme.of(context).colorScheme;
    return FloatingActionButton.small(
      // An explicit tag: two `FloatingActionButton`s in one route throw on the default hero tag, and
      // seven of the twelve shell screens already have one.
      heroTag: 'alaya-home-fab',
      // **Low emphasis, and this is the point.** In primary colour a bottom-left FAB reads as *the*
      // action on the screen, competing with the create button diagonally opposite it — two saturated
      // circles, equal weight, different jobs. Surface-toned with a muted glyph, it reads as a way
      // *out* rather than a thing to do, which is what navigation should look like.
      //
      // The position was never the problem. Two primary actions was.
      backgroundColor: scheme.surfaceContainerHighest,
      foregroundColor: semantic.muted,
      elevation: 1,
      highlightElevation: 2,
      onPressed: () => context.go(Routes.dashboard),
      tooltip: strings.navBackToDashboard,
      child: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
    );
  }
}
