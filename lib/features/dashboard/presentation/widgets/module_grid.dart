import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/dashboard/providers/module_providers.dart';
import 'package:alaya/shared/widgets/module_tile.dart';

/// Navigation tiles, each carrying a live number (ARCH_5 §3 archetype F).
///
/// **Every tile's number is real, and a zero is worded rather than shown.** "0 running low" is a figure
/// the reader has to interpret; "nothing tracked" is an answer. The ARB holds both wordings and picks by
/// count, which is why `ModuleTile` takes text rather than an `int`.
///
/// A count still arriving shows the module's name and no number rather than a spinner: the tile's job is
/// navigation, and it can do that job before its count lands.
///
/// ## The cell height is measured, not a ratio
///
/// `childAspectRatio` ties a cell's height to its *width*, and width does not move when the user doubles
/// their text size. So the box stayed put while both labels inside it grew, and every dashboard test
/// overflowed — by 22px at scale 1 and 250px at scale 2 (Law U15, and the reason U15 asks for a test
/// rather than an opinion).
///
/// `mainAxisExtent` computed from `MediaQuery.textScalerOf` grows with the text instead. The grid gets
/// taller and the dashboard scrolls, which is the right outcome: archetype F requires the screen to
/// *survive* 320dp at scale 2, not to fit on it.
///
/// ## `push`, not `go` — a tile is a drill-down
///
/// Tapping a tile is a "go into this" gesture, so it should come back. `go` made the module a peer of the
/// dashboard and left the drawer as the only way home: two taps, and no back affordance at all. `push`
/// slides the module over the dashboard and `_ShellScaffold` now shows a back arrow when it can pop, so
/// the way out is the arrow, the OS gesture, or the drawer — three, rather than one.
///
/// The drawer still `go`es, which is correct: choosing Expenses from a list of nine destinations *is* a
/// peer switch, and it should not accumulate a stack.
///
/// `push` also keeps the dashboard live underneath. Six of its providers are `autoDispose`, so leaving the
/// location tears their subscriptions down and returning refetches — a visible loading flash on a screen
/// the user was just looking at. Pushed, the dashboard stays mounted, its drift streams keep emitting, and
/// a transaction added on the pushed screen has already landed in the figures before the pop finishes.
///
/// The budget below is what one tile actually needs — its glyph, its two spacers, both labels at
/// `ModuleTile.maxLabelLines`, and the tile's own padding — floored at two tap targets so a tile is never
/// smaller than something you can hit (U3).
class ModuleGrid extends ConsumerWidget {
  /// Creates the grid.
  const ModuleGrid({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final expenses = ref.watch(expenseCountProvider).valueOrNull;
    final inventory = ref.watch(inventoryCountProvider);
    final shopping = ref.watch(shoppingCountProvider).valueOrNull;
    final recurring = ref.watch(recurringCountProvider).valueOrNull;
    final services = ref.watch(serviceCountProvider);

    // A count worth acting on is coloured; a settled one is not. Colour is the only thing distinguishing
    // "two bills due" from "two bills paid", and the wording carries the rest.
    Color? toneFor(int? count) =>
        count != null && count > 0 ? semantic.warning : null;

    final scaler = MediaQuery.textScalerOf(context);

    // The height one label occupies at its full line budget, at the scale in force right now.
    double labelBudget(TextStyle style) =>
        scaler.scale(style.fontSize!) *
        style.height! *
        ModuleTile.maxLabelLines;

    final tileExtent = math
        .max(
          AlayaSpacing.minTapTarget * 2,
          AlayaIconSize.lg +
              AlayaSpacing.xs +
              labelBudget(AlayaTypography.body) +
              AlayaSpacing.xxs +
              labelBudget(AlayaTypography.caption) +
              AlayaSpacing.sm * 2,
        )
        .toDouble();

    return GridView(
      shrinkWrap: true,
      // The dashboard owns the scroll (Law U13): a grid that scrolls inside a `CustomScrollView` is two
      // gestures fighting over one drag. `shrinkWrap` and `NeverScrollableScrollPhysics` travel together
      // — one without the other is the defect (ARCH_6 P2).
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AlayaSpacing.sm,
        crossAxisSpacing: AlayaSpacing.sm,
        mainAxisExtent: tileExtent,
      ),
      children: [
        ModuleTile(
          label: strings.navExpenses,
          icon: Icons.receipt_long_outlined,
          detail: expenses == null ? '' : strings.moduleExpenses(expenses),
          onTap: () => context.push(Routes.expenses),
        ),
        ModuleTile(
          label: strings.navInventory,
          icon: Icons.inventory_2_outlined,
          detail: strings.moduleInventory(inventory),
          tone: toneFor(inventory),
          onTap: () => context.push(Routes.inventory),
        ),
        ModuleTile(
          label: strings.navShopping,
          icon: Icons.shopping_basket_outlined,
          detail: shopping == null ? '' : strings.moduleShopping(shopping),
          tone: toneFor(shopping),
          onTap: () => context.push(Routes.shopping),
        ),
        ModuleTile(
          label: strings.navRecurring,
          icon: Icons.event_repeat,
          detail: recurring == null ? '' : strings.moduleRecurring(recurring),
          tone: toneFor(recurring),
          onTap: () => context.push(Routes.recurring),
        ),
        ModuleTile(
          label: strings.navServices,
          icon: Icons.handyman_outlined,
          detail: strings.moduleServices(services),
          tone: toneFor(services),
          onTap: () => context.push(Routes.services),
        ),
      ],
    );
  }
}
