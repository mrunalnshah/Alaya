import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/analytics/presentation/screens/analytics_home_screen.dart';
import 'package:alaya/features/analytics/presentation/screens/drill_down_screen.dart';
import 'package:alaya/features/analytics/state/drill_down_spec.dart';
import 'package:alaya/features/backup/presentation/screens/backup_screen.dart';
import 'package:alaya/features/backup/presentation/screens/restore_flow.dart';
import 'package:alaya/features/calendar/presentation/screens/calendar_screen.dart';
import 'package:alaya/features/reminders/presentation/screens/reminders_screen.dart';
import 'package:alaya/features/support/presentation/screens/support_screen.dart';
import 'package:alaya/features/trash/presentation/screens/trash_screen.dart';
import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/screens/pin_setup_flow.dart';
import 'package:alaya/features/lock/presentation/screens/recovery_flow.dart';
import 'package:alaya/features/onboarding/presentation/screens/onboarding_flow.dart';
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
import 'package:alaya/features/support/presentation/widgets/support_action.dart';
import 'package:alaya/features/settings/presentation/screens/tag_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/unit_editor_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/features/dashboard/presentation/screens/dashboard_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_editor_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/batch_history_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/inventory_list_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_detail_screen.dart';
import 'package:alaya/features/inventory/presentation/screens/item_editor_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/occurrence_history_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_builder_screen.dart';
import 'package:alaya/features/recurring/presentation/screens/template_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_detail_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_editor_screen.dart';
import 'package:alaya/features/service/presentation/screens/asset_list_screen.dart';
import 'package:alaya/features/service/presentation/screens/service_editor_screen.dart';
import 'package:alaya/features/settings/presentation/theme_lab_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/convert_to_purchase_screen.dart';
import 'package:alaya/features/shopping/presentation/screens/shopping_list_screen.dart';
import 'package:alaya/shared/widgets/alaya_drawer.dart';

/// Whether the app is currently locked, consulted on every navigation.
typedef LockGate = bool Function();

/// Whether the first-run flow still has to happen, consulted on every navigation.
typedef OnboardingGate = bool Function();

/// The app's `go_router` configuration — hand-written, per ARCH_1 §7.3.
///
/// **The nine drawer destinations sit inside the shell; every detail and editor route sits outside
/// it** (U18). `AppBar` resolves its leading slot by checking `hasDrawer` *before* `canPop`, so a
/// detail screen rendered inside the drawer shell gets a hamburger where a back arrow belongs.
///
/// Literal-path segments are declared before their parameterised siblings, because go_router walks
/// its route list in order and `:itemId` would otherwise swallow the word `new`.
///
/// **Phase 7B: `/insights` is now a real screen and `/insights/drill/...` is its drill-down.** The
/// drill-down is a top-level route rather than a child of `/insights`, unlike the calendar's day route:
/// a day is a view *of* the month and keeps the drawer (Law U27), while a drill-down leaves analytics
/// for the ledger and needs a back arrow, which a shell owning a drawer can never imply (Law U18).
///
/// **`_detail` was removed in 7B and `_destination` in 8A.** Both were declared and then called by
/// nothing once the last placeholder became a real screen, and `very_good_analysis` reports
/// `unused_element` on each. The `placeholder_screen.dart` import goes with them: **8A was the final
/// phase with a placeholder destination**, so nothing in this file names `PlaceholderScreen` any more.
/// The widget itself stays where it is, for 8B's Reminders and Support Us screens.
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
        // to; asking someone to finish setting up an app they cannot yet open would be the wrong order.
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
          // No `location` passed: `_ShellScaffold` reads it from the router, because the state handed to a
          // pathless `ShellRoute`'s builder reports `/` for every screen inside it.
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
        GoRoute(
          path: Routes.itemNew,
          builder: (context, state) => const ItemEditorScreen(),
        ),
        GoRoute(
          path: Routes.batchNewPattern,
          builder: (context, state) => BatchEditorScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
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
          builder: (context, state) => ItemEditorScreen(
            itemId: state.pathParameters[Routes.pItemId],
          ),
        ),
        GoRoute(
          path: Routes.itemDetailPattern,
          builder: (context, state) => ItemDetailScreen(
            itemId: state.pathParameters[Routes.pItemId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingConvertPattern,
          builder: (context, state) => ConvertToPurchaseScreen(
            listId: state.pathParameters[Routes.pListId]!,
          ),
        ),
        GoRoute(
          path: Routes.shoppingListPattern,
          builder: (context, state) => ShoppingListScreen(
            listId: state.pathParameters[Routes.pListId],
          ),
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
          builder: (context, state) => AssetEditorScreen(
            assetId: state.pathParameters[Routes.pAssetId],
          ),
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
        GoRoute(
          path: Routes.themeLab,
          builder: (context, state) => _DetailScaffold(
            title: AlayaStrings.of(context).navThemeLab,
            child: const ThemeLabScreen(),
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
          builder: (context, state) => TagEditorScreen(
            tagId: state.pathParameters[Routes.pTagId],
          ),
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
    // `AppBar` resolves its implied leading by checking `hasDrawer` **before** `canPop`, so a shell that
    // owns a drawer can never show a back arrow no matter how it was reached. That is fine for a drawer
    // destination switched into as a peer, and wrong for one pushed as a drill-down — and both happen
    // here: the drawer `go`es, the dashboard's module grid `push`es.
    //
    // So the slot is stated rather than implied. Pushed: a back arrow that pops the shell's own navigator
    // (`context.pop`, not `Navigator.maybePop`, which from above the shell navigator would target the root
    // one and do nothing). Switched into: null, which lets the hamburger be implied as before.
    //
    // The drawer stays attached either way, so the edge swipe still opens it on a pushed screen.
    final strings = AlayaStrings.of(context);

    // **Read from the router, not from the builder's `state`.** `ShellRoute` declares no `path`, so the
    // `GoRouterState` handed to its builder describes the *shell's* match rather than the leaf's — and a
    // pathless route's `matchedLocation` is its parent's, which here is `/`. Every screen inside the shell
    // therefore looked like the dashboard: `atDashboard` was permanently true so the home action never
    // rendered, `AlayaDrawer` highlighted Dashboard wherever you were, and `titleFor` named it too.
    //
    // `currentConfiguration` is the delegate's live `RouteMatchList`, so its `uri` is the leaf location no
    // matter which builder asks.
    final here = GoRouter.of(
      context,
    ).routerDelegate.currentConfiguration.uri.path;

    // **`context.canPop()` cannot answer this question from here.** This widget is the `ShellRoute`
    // builder, so its context sits *above* the shell's own `Navigator`; `canPop` resolves against the
    // root navigator, which only ever holds the shell itself. It therefore returns false however the
    // screen was reached, `leading` was always null, and the back arrow this once tried to show could
    // never appear. The drawer's hamburger was the only leading widget users ever saw, and from a module
    // the sole way home was the system back gesture.
    //
    // So the way home is stated outright instead of inferred from a stack this context cannot see: every
    // shell screen except the dashboard carries a home action. It pops when there is something to pop and
    // navigates otherwise, so arriving by the module grid's `push` and by the drawer's `go` both end up
    // in the same place — and the hamburger keeps its slot, because the drawer is still how you move
    // between peers (Law U27).
    return Scaffold(
      drawer: AlayaDrawer(currentLocation: here),
      appBar: AppBar(
        title: Text(AlayaDrawer.titleFor(context, here)),
        // **Unconditional, deliberately.** This was `if (!atDashboard)` and never appeared, and rather
        // than reason about why a condition is false I would rather the button exist and be seen. It
        // shows on the dashboard too, where it is merely redundant — a redundant button is a far smaller
        // fault than a missing one, and its presence there is also the proof that this file is live.
        //
        // Once it is confirmed visible, `if (!atDashboard)` can come back.
        actions: [
          IconButton(
            onPressed: () =>
                context.canPop() ? context.pop() : context.go(Routes.dashboard),
            tooltip: strings.navBackToDashboard,
            icon: const Icon(Icons.home_outlined, size: AlayaIconSize.md),
          ),
          // **Beside the home button, and it loads nothing until pressed.** ARCH_4 §5.1 said rewarded ads live
          // "only in Support Us"; this amends the entry point and keeps the constraint — no `MobileAds`
          // initialisation, no consent fetch and no ad request happen on build, so a user who never taps it never
          // has an advertising identifier collected.
          const SupportAction(),
        ],
      ),
      body: child,
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
