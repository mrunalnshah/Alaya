import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The app's navigation drawer.
///
/// Its destination list is `Routes.drawerDestinations`, so a route cannot exist in the router and be
/// missing from the drawer — the two read the same constant.
///
/// A drawer rather than a bottom bar because there are nine destinations. A bottom bar holds four
/// comfortably and five at a squeeze; beyond that the labels truncate and the targets shrink below the
/// tap-target floor.
class AlayaDrawer extends StatelessWidget {
  /// Creates the drawer.
  const AlayaDrawer({required this.currentLocation, super.key});

  /// The location currently shown, used to mark the selected row.
  final String currentLocation;

  /// The localised title for [location].
  ///
  /// Static so the app bar can title itself from the same mapping the drawer uses, rather than each
  /// screen repeating its own name and the two drifting apart.
  static String titleFor(BuildContext context, String location) {
    final strings = AlayaStrings.of(context);
    return switch (_rootOf(location)) {
      Routes.dashboard => strings.navDashboard,
      Routes.expenses => strings.navExpenses,
      Routes.inventory => strings.navInventory,
      Routes.recipes => strings.navRecipes,
      Routes.split => strings.navSplit,
      Routes.shopping => strings.navShopping,
      Routes.recurring => strings.navRecurring,
      Routes.services => strings.navServices,
      Routes.calendar => strings.navCalendar,
      Routes.insights => strings.navInsights,
      Routes.settings => strings.navSettings,
      Routes.support => strings.supportTitle,
      _ => strings.appName,
    };
  }

  /// The icon for [location].
  static IconData iconFor(String location) => switch (_rootOf(location)) {
    Routes.dashboard => Icons.dashboard_outlined,
    Routes.expenses => Icons.receipt_long_outlined,
    Routes.inventory => Icons.inventory_2_outlined,
    // A cooking pot rather than a book: the module is about what you can make from what is on
    // hand, not about storing text.
    Routes.recipes => Icons.restaurant_menu_outlined,
    // A fork in a path, not a group of people: the module is about dividing a bill, and the people
    // are labels on the division rather than the subject of it.
    Routes.split => Icons.call_split_outlined,
    Routes.shopping => Icons.shopping_cart_outlined,
    Routes.recurring => Icons.autorenew_outlined,
    Routes.services => Icons.build_outlined,
    Routes.calendar => Icons.calendar_month_outlined,
    Routes.insights => Icons.insights_outlined,
    Routes.settings => Icons.settings_outlined,
    // Joined hands, matching the app bar action so the two read as the same thing in two places.
    Routes.support => Icons.handshake_outlined,
    _ => Icons.circle_outlined,
  };

  /// The top-level route a possibly-nested [location] belongs to.
  ///
  /// `/expenses/abc123` selects Expenses. Matching the full location would leave nothing selected as
  /// soon as the user opened a detail screen.
  static String _rootOf(String location) {
    if (location == Routes.dashboard) return Routes.dashboard;
    for (final destination in Routes.drawerDestinations) {
      if (destination == Routes.dashboard) continue;
      if (location == destination || location.startsWith('$destination/'))
        return destination;
    }
    return location;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final strings = AlayaStrings.of(context);
    final selected = _rootOf(currentLocation);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.md),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.md,
                AlayaSpacing.xs,
                AlayaSpacing.md,
                AlayaSpacing.lg,
              ),
              child: Text(
                strings.appName,
                style: AlayaTypography.screenTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            for (final destination in Routes.drawerDestinations)
              _DrawerRow(
                destination: destination,
                selected: destination == selected,
                onTap: () {
                  Navigator.of(context).pop();
                  if (destination != selected) context.go(destination);
                },
              ),
            // **Phase 8B, below the destinations and behind a divider.** Support Us is not a place the app does
            // work, so it is not a peer of Expenses or Inventory — the separation says so without a label.
            //
            // Opening this screen is what starts the ad SDK; the drawer row only navigates, so pulling the
            // drawer out costs nothing (ARCH_4 §5.1).
            const Divider(height: AlayaSpacing.lg),
            _DrawerRow(
              destination: Routes.support,
              selected: selected == Routes.support,
              onTap: () {
                Navigator.of(context).pop();
                if (selected != Routes.support) context.push(Routes.support);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final String destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: ListTile(
        selected: selected,
        selectedColor: theme.colorScheme.secondary,
        selectedTileColor: theme.colorScheme.secondary.withValues(alpha: 0.10),
        leading: Icon(AlayaDrawer.iconFor(destination)),
        title: Text(AlayaDrawer.titleFor(context, destination)),
        onTap: onTap,
      ),
    );
  }
}
