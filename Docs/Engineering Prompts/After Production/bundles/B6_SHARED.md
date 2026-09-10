# B6_SHARED

The widget vocabulary.

**34 files · 4,267 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/shared/feedback/undo_snack.dart`

```dart
/// The single implementation of Law U9's success path.
///
/// **Every write reports its outcome.** A save that appears to do nothing is the worst result a form
/// can produce, and the second worst is five features each inventing their own snack bar.
///
/// One at a time: each call hides the current bar before showing its own. A queue would leave the
/// user reading the result of an action they took four taps ago.
library;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Reports a completed write and offers to reverse it.
///
/// Use wherever the data model can undo, which is most places — soft delete exists precisely so this
/// is possible (ARCH_3 §4). ARCH_5 §5.4 fixes what undo means per entity; in particular a stock
/// consume undoes by writing a **reversing movement**, never by deleting the original.
void showUndoSnack(
  BuildContext context, {
  required String message,
  required String undoLabel,
  required VoidCallback onUndo,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        action: SnackBarAction(label: undoLabel, onPressed: onUndo),
      ),
    );
}

/// Reports a completed write that cannot be undone.
void showResultSnack(
  BuildContext context, {
  required String message,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: AlayaDurations.snack,
        // **An offer, not a redirection.** A completed save must not throw the user into another form:
        // recording the expense was the task, and naming a warranty is a different one. The action puts
        // the next step one tap away without taking the decision for them (Law U9).
        action: actionLabel == null || onAction == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction),
      ),
    );
}

/// Reports a failed write, optionally offering a retry.
///
/// Coloured by the danger tone rather than left to the default surface: a failure that looks
/// identical to a success is a failure the user will not notice.
void showFailureSnack(
  BuildContext context, {
  required String message,
  String? retryLabel,
  VoidCallback? onRetry,
}) {
  final semantic = context.semantic;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: semantic.onStatus)),
        backgroundColor: semantic.danger,
        duration: AlayaDurations.snack,
        action: retryLabel == null || onRetry == null
            ? null
            : SnackBarAction(
                label: retryLabel,
                textColor: semantic.onStatus,
                onPressed: onRetry,
              ),
      ),
    );
}
```

### `lib/shared/widgets/account_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/account.dart';

/// Picks an account.
///
/// Shows each account's currency code alongside its name, because a transfer between accounts in
/// different currencies is a different operation from one within a currency — and the user needs to
/// see that before choosing, not after the form changes shape.
///
/// Archived accounts are excluded unless one is already selected, in which case it stays visible so
/// an old transaction can still be edited without silently losing its account.
class AccountPicker extends StatelessWidget {
  /// Creates an account picker.
  const AccountPicker({
    required this.accounts,
    required this.selected,
    required this.onChanged,
    this.label,
    this.hint,
    this.errorText,
    this.excludeId,
    this.enabled = true,
    super.key,
  });

  /// The accounts to offer.
  final List<Account> accounts;

  /// The current selection.
  final Account? selected;

  /// Called with the newly chosen account.
  final ValueChanged<Account> onChanged;

  /// The field's label.
  final String? label;

  /// Placeholder when nothing is selected.
  final String? hint;

  /// An error from the caller.
  final String? errorText;

  /// An account to hide — the other side of a transfer, so it cannot be both source and
  /// destination.
  final String? excludeId;

  /// Whether the picker accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible =
        accounts
            .where((account) => account.id != excludeId)
            .where(
              (account) => !account.isArchived || account.id == selected?.id,
            )
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Resolved by id to the instance actually in the item list. `Account`'s equality compares every
    // field, including the balance-affecting ones, so passing the caller's possibly-staler instance
    // would match no item and blank the field.
    Account? current;
    for (final account in eligible) {
      if (account.id == selected?.id) {
        current = account;
        break;
      }
    }

    return DropdownButtonFormField<Account>(
      // See UnitPicker: a FormField does not reliably follow later changes to the value it was
      // created with, and a transfer form must be able to clear one side when the other changes.
      key: ValueKey(current?.id),
      initialValue: current,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        enabled: enabled,
      ),
      isExpanded: true,
      items: [
        for (final account in eligible)
          DropdownMenuItem(
            value: account,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    account.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  account.currencyCode,
                  style: AlayaTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: enabled
          ? (account) => account == null ? null : onChanged(account)
          : null,
    );
  }
}
```

### `lib/shared/widgets/alaya_bottom_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one bottom-sheet scaffold (ARCH_3 §8.3).
///
/// **Every sheet goes through here.** It composes the keyboard inset padding, [SafeArea] and a
/// [SingleChildScrollView] in that order, exactly once — the combination each sheet otherwise gets
/// wrong in the same way. A `MainAxisSize.min` Column inside a `Padding` keyed to
/// `viewInsets.bottom` is correct in each half and broken together: the padding shrinks the
/// available height and the Column has no way to give up the room it already took, so it overflows
/// the instant a keyboard opens and never otherwise. Putting the scroll view *inside* the padding
/// turns that overflow into scroll extent instead.
///
/// Sheets therefore return content only — no `SafeArea`, no `viewInsets` padding and no scroll view
/// of their own. A sheet that adds one is reintroducing the bug.
class AlayaBottomSheet extends StatelessWidget {
  /// Wraps [child] in the sheet scaffold. Prefer [show].
  const AlayaBottomSheet({
    required this.child,
    this.padding = defaultPadding,
    super.key,
  });

  /// The sheet's content, laid out as though the viewport were tall enough for it.
  final Widget child;

  /// Padding around [child]. Inside the scroll view, so it scrolls with the content rather than
  /// eating viewport height a keyboard has already taken.
  final EdgeInsetsGeometry padding;

  /// The default content padding: screen-edge horizontally, tighter at the top where the drag
  /// handle already provides separation.
  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(
    AlayaSpacing.screenEdge,
    AlayaSpacing.xs,
    AlayaSpacing.screenEdge,
    AlayaSpacing.md,
  );

  /// Shows [builder]'s widget as a modal sheet and resolves to whatever it pops.
  ///
  /// `isScrollControlled` is not optional: without it the sheet is capped near half the screen and
  /// cannot grow when a keyboard pushes its content up. `useSafeArea` keeps the sheet clear of the
  /// status bar while deliberately leaving the bottom edge to this widget's own [SafeArea] — so the
  /// sheet's background still runs behind the navigation bar and only its content is inset.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    EdgeInsetsGeometry padding = defaultPadding,
    bool isDismissible = true,
    bool enableDrag = true,
  }) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (context) =>
        AlayaBottomSheet(padding: padding, child: builder(context)),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: SingleChildScrollView(
        padding: padding,
        child: child,
      ),
    ),
  );
}
```

### `lib/shared/widgets/alaya_card.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_elevation.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The app's one card surface.
///
/// Takes a surface **tier** rather than an elevation number, because depth here is a palette step and
/// not a shadow — which is what keeps a card legible in dark mode, where a soft black shadow on a
/// near-black ground conveys nothing (see `AlayaElevation`).
class AlayaCard extends StatelessWidget {
  /// Creates a card.
  const AlayaCard({
    required this.child,
    this.tier = 1,
    this.padding = const EdgeInsets.all(AlayaSpacing.md),
    this.onTap,
    this.onLongPress,
    this.border = false,
    this.semanticsLabel,
    super.key,
  });

  /// The card's content.
  final Widget child;

  /// The surface tier: -1 sunken, 0 base, 1 raised (the default), 2 overlay.
  final int tier;

  /// Inner padding. Always a token value.
  final EdgeInsetsGeometry padding;

  /// Tap handler. When null the card is not interactive and takes no ink.
  final VoidCallback? onTap;

  /// Long-press handler, usually a context menu.
  final VoidCallback? onLongPress;

  /// Draws a hairline border, for a card on a same-coloured surface.
  final bool border;

  /// An accessibility label describing the card as a whole.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final isDark = theme.brightness == Brightness.dark;
    final interactive = onTap != null || onLongPress != null;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderMd,
      side: border ? BorderSide(color: theme.dividerColor) : BorderSide.none,
    );
    final content = Padding(padding: padding, child: child);

    // The surface colour and the border belong to the Material, not to a DecoratedBox wrapped
    // around it. A Material paints its ink splashes *beneath* its child, so an opaque decoration
    // between the two hides every ripple — the card looked correct and simply never responded to a
    // press. The DecoratedBox here carries the shadow and nothing else.
    final surface = Material(
      color: semantic.surfaceForTier(tier),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: interactive
          ? InkWell(onTap: onTap, onLongPress: onLongPress, child: content)
          : content,
    );

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AlayaRadii.borderMd,
        // No shadow on a sunken tier: a well does not cast one.
        boxShadow: tier <= 0
            ? AlayaElevation.none
            : AlayaElevation.raised(isDark: isDark),
      ),
      child: surface,
    );

    return semanticsLabel == null
        ? card
        : Semantics(label: semanticsLabel, container: true, child: card);
  }
}
```

### `lib/shared/widgets/alaya_disclosure.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One labelled door to the rest of a form (ARCH_5 §2.9, Law U16).
///
/// A form with eleven controls is not hard to use because any one of them is hard — it is hard because
/// all eleven arrive at once and the reader has to decide which matter. This shows the few that usually
/// do, and puts the rest behind one row they can open.
///
/// **Three rules make the pattern safe rather than merely tidier:**
///
/// 1. **[summary] says what is inside.** A collapsed section that gives no account of itself is a place
///    values go to hide: somebody sets a tag, saves, reopens, and the tag is behind a chevron with
///    nothing to suggest it exists. The summary is not decoration — it is what makes collapsing
///    honest.
/// 2. **[startExpanded] opens it when anything inside is non-default.** Reopening a record must show
///    what that record actually holds. A caller passes `true` when it has values worth seeing, and the
///    section stays open from then on.
/// 3. **It never hides a required field.** Only one field in any capture path is required (Law U11), and
///    it belongs above this row. A validation error the user cannot see is worse than a long form.
///
/// The expansion animates at [AlayaDurations.base] — the fifth animation ARCH_5 §2.6 permits, and the
/// only one that exists to *explain*: a section appearing instantly reads as a layout glitch, and the
/// user cannot tell whether they opened something or the screen jumped. It skips entirely under
/// `MediaQuery.disableAnimationsOf`, like every other motion in the app.
class AlayaDisclosure extends StatefulWidget {
  /// Creates a disclosure.
  const AlayaDisclosure({
    required this.label,
    required this.child,
    this.summary,
    this.startExpanded = false,
    super.key,
  });

  /// What is behind the door, e.g. "More details".
  final String label;

  /// What is currently set inside, shown only while collapsed.
  ///
  /// Keep it to the values a user would look for — "Cash · Groceries · 2 tags", not a field list. Null
  /// when nothing inside has been set, which is the common case on a new record.
  final String? summary;

  /// Whether to open on first build.
  ///
  /// Pass `true` when anything inside holds a non-default value. Editing an existing record almost
  /// always means `true`; a blank one almost always means `false`.
  final bool startExpanded;

  /// The fields.
  final Widget child;

  @override
  State<AlayaDisclosure> createState() => _AlayaDisclosureState();
}

class _AlayaDisclosureState extends State<AlayaDisclosure> {
  late bool _open = widget.startExpanded;

  @override
  void didUpdateWidget(AlayaDisclosure oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Opens when the caller newly reports content, and never closes on its own. A section that shut
    // itself while the user was reading it would be the worst version of this widget.
    if (widget.startExpanded && !oldWidget.startExpanded) _open = true;
  }

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final summary = widget.summary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A whole-width row, not an icon button. The affordance is the row: a chevron alone is a
        // 24dp target on a 320dp screen and reads as decoration.
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(widget.label, style: AlayaTypography.bodyEmphasis),
                        if (!_open &&
                            summary != null &&
                            summary.isNotEmpty) ...[
                          const SizedBox(height: AlayaSpacing.xxs),
                          Text(
                            summary,
                            style: AlayaTypography.caption.copyWith(
                              color: semantic.muted,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AlayaSpacing.xs),
                  // Rotates rather than swapping glyphs, so the chevron is one object that moved and
                  // not two icons that flickered.
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : AlayaDurations.base,
                    child: Icon(
                      Icons.expand_more,
                      size: AlayaIconSize.md,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // `AnimatedSize` over the real child rather than a cross-fade: the fields must be in the tree
        // whether or not they are visible, so a validation error inside a closed section still counts
        // and `initialValue` on a text field is not re-seeded every time the section opens.
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : AlayaDurations.base,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
                  child: widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/alaya_drawer.dart`

```dart
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
```

### `lib/shared/widgets/alaya_expandable_fab.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One action inside an [AlayaExpandableFab].
class FabAction {
  /// Creates an action.
  const FabAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  /// The label, already localised. Always shown — an icon alone is a guess.
  final String label;

  /// The leading icon.
  final IconData icon;

  /// What tapping it does.
  final VoidCallback onPressed;
}

/// A FAB that unfolds into labelled actions.
///
/// Every action carries a visible label rather than an icon alone. A row of unlabelled icons is a
/// memory test, and the actions here — expense, income, item — are not distinguishable by any icon a
/// user has seen before.
///
/// Collapses on any action, on a tap anywhere outside itself, and on back.
///
/// ## Why the actions used to unfold on the wrong side of the screen
///
/// Two separate causes, and the first one is the one you see.
///
/// **`SizeTransition` left-aligns.** For a vertical axis it builds
/// `ClipRect(Align(alignment: AlignmentDirectional(-1.0, axisAlignment), heightFactor: t))` — and `-1.0`
/// on the horizontal axis means *left*. An `Align` given a `heightFactor` but no `widthFactor` also
/// **expands to fill the width it is offered**. So each min-width action row was being left-aligned inside
/// a box as wide as the whole FAB slot, while the button — not wrapped in a `SizeTransition` — obeyed
/// `CrossAxisAlignment.end` and stayed in the corner. Button right, actions hard left, which is exactly
/// what shipped. The rows fill the slot and right-align their own content now, so the framework's
/// alignment no longer has anything to decide.
///
/// **The slot's width also moved the anchor.** `FloatingActionButtonLocation.endFloat` answers
/// `x = screenWidth - slotWidth - margin` — it anchors by the slot's *own* width. Sizing to content made
/// that width 56 closed and full-screen open (the `Align` above), so `x` went to `-16` and the whole menu,
/// button included, shifted off the left edge. A slot of `screenWidth - 2 * md` makes it constant: `x = md`
/// open or closed, and off-screen becomes unreachable rather than unlikely.
///
/// The bound also gives the labels something to ellipsise against. `Flexible` was always there for that,
/// but under a full-screen loose constraint it had nothing to push back on and the row simply grew.
///
/// **Still no scrim (ARCH_3 §8.3).** A full-screen dim drawn from inside the FAB slot is either clipped
/// to the slot — invisible, and unable to receive the tap it exists for — or forces the slot wider and
/// reintroduces the anchor drift above. `TapRegion` supplies the dismissal without either failure, and
/// the rows carry opaque surfaces of their own so they stay legible over content.
class AlayaExpandableFab extends StatefulWidget {
  /// Creates an expandable FAB.
  const AlayaExpandableFab({
    required this.actions,
    required this.openLabel,
    required this.closeLabel,
    super.key,
  });

  /// The actions, in the order they unfold upward.
  final List<FabAction> actions;

  /// Accessibility label for the collapsed button.
  final String openLabel;

  /// Accessibility label for the expanded button.
  final String closeLabel;

  @override
  State<AlayaExpandableFab> createState() => _AlayaExpandableFabState();
}

class _AlayaExpandableFabState extends State<AlayaExpandableFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: AlayaDurations.slow,
    vsync: this,
  );
  bool _expanded = false;

  void _toggle() => _expanded ? _collapse() : _expand();

  /// Whether the platform has asked for reduced motion.
  ///
  /// **Skipped, not shortened** (ARCH_5 §2.6, §6). `jumpTo` puts the controller at its end state in one frame,
  /// so the actions appear and disappear without travelling — a user who asked for less motion gets none, and
  /// still gets the full affordance. Shortening the duration would be a smaller version of the thing they
  /// switched off.
  bool get _reducedMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _expand() {
    setState(() => _expanded = true);
    _reducedMotion ? _controller.value = 1 : _controller.forward();
  }

  void _collapse() {
    if (!_expanded) return;
    setState(() => _expanded = false);
    _reducedMotion ? _controller.value = 0 : _controller.reverse();
  }

  void _run(FabAction action) {
    _collapse();
    action.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The margin `endFloat` will subtract, on both sides, so the anchor lands at exactly `md`.
    //
    // **Clamped, because Android's first frame reports a zero-width viewport.** The engine logs it twice
    // before the tree builds — `D/FlutterRenderer: Width is zero. 0,0` — and `0 - 32` is `-32`, which is
    // not a width: `SizedBox` asserted `BoxConstraints has a negative minimum width` and the app opened
    // to a red screen on every launch. The fixed extent is still what keeps the anchor still (Law U28);
    // it simply cannot go below nothing. The next frame carries the real width and the slot corrects
    // itself, which is why the fault never survived to a screenshot and never showed up in tests — the
    // widget harness always sets a real viewport before pumping.
    final slotWidth = (MediaQuery.sizeOf(context).width - AlayaSpacing.md * 2)
        .clamp(0.0, double.infinity);

    return PopScope<Object?>(
      canPop: !_expanded,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _collapse();
      },
      child: TapRegion(
        onTapOutside: (_) => _collapse(),
        // Rebuilt per frame so the action rows leave the tree at the end of the reverse rather than the
        // start of it: a SizeTransition zeroes its child's height but not its width, and rows left
        // mounted while collapsed would keep taking hit tests over the content behind them.
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => SizedBox(
            width: slotWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!_controller.isDismissed)
                  for (final action in widget.actions)
                    SizeTransition(
                      sizeFactor: _controller,
                      axisAlignment: 1,
                      child: FadeTransition(
                        opacity: _controller,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            bottom: AlayaSpacing.sm,
                          ),
                          child: _ActionRow(
                            action: action,
                            onTap: () => _run(action),
                          ),
                        ),
                      ),
                    ),
                FloatingActionButton(
                  onPressed: _toggle,
                  tooltip: _expanded ? widget.closeLabel : widget.openLabel,
                  child: AnimatedRotation(
                    turns: _expanded ? 0.125 : 0,
                    duration: AlayaDurations.base,
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.onTap});

  final FabAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Fills the slot and right-aligns its content, rather than being a min-width row left-aligned by
    // `SizeTransition`. See the class doc: this is the line that puts the actions under the button.
    return Row(
      mainAxisSize: MainAxisSize.max,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Flexible against the slot's bounded width: the label ellipsises at the screen edge instead of
        // widening the row past it.
        Flexible(
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: AlayaSpacing.minTapTarget,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.sm,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      action.label,
                      style: AlayaTypography.button.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: AlayaSpacing.sm),
        SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Material(
            color: theme.colorScheme.secondary,
            shape: const RoundedRectangleBorder(
              borderRadius: AlayaRadii.borderSm,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Icon(
                action.icon,
                color: theme.colorScheme.onSecondary,
                size: AlayaIconSize.md,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/alaya_form_scaffold.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';

/// The body of every editor screen (ARCH_5 §3 archetype B).
///
/// Three things that every form needs and that every form otherwise reimplements slightly
/// differently:
///
/// 1. **A scrolling body.** Law U2 — a screen with a text input has a scroll ancestor, or it
///    overflows the moment a keyboard opens at a raised text scale.
/// 2. **A sticky footer holding the commit.** Law U14 — an app-bar "Save" is a stretch on a 6.7"
///    phone held one-handed, and this app is used one-handed. The footer sits above the keyboard
///    because the enclosing `Scaffold` resizes; the screen must therefore **not** set
///    `resizeToAvoidBottomInset: false`.
/// 3. **An unsaved-changes guard.** Law U10 — dismissing an editor with edits in it prompts, and a
///    rejected save leaves every field populated.
///
/// The screen supplies `Scaffold(appBar: …, body: AlayaFormScaffold(…))` and owns its own state;
/// this widget owns none of it.
class AlayaFormScaffold extends StatelessWidget {
  /// Creates a form body committing through [onPrimary].
  const AlayaFormScaffold({
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    required this.discardTitle,
    required this.discardBody,
    required this.discardConfirmLabel,
    required this.discardCancelLabel,
    this.secondaryLabel,
    this.onSecondary,
    this.isDirty = false,
    this.isSubmitting = false,
    this.padding = const EdgeInsets.fromLTRB(
      AlayaSpacing.screenEdge,
      AlayaSpacing.md,
      AlayaSpacing.screenEdge,
      AlayaSpacing.xxl,
    ),
    super.key,
  });

  /// The form's fields and sections.
  final Widget child;

  /// The commit button's label, already localised. Names the action — "Save expense", not "Save".
  final String primaryLabel;

  /// The commit. Null disables the button, which is how an invalid form reports itself.
  final VoidCallback? onPrimary;

  /// Title of the discard prompt.
  final String discardTitle;

  /// Body of the discard prompt. Says what will be lost.
  final String discardBody;

  /// The discard prompt's confirm label — the destructive one.
  final String discardConfirmLabel;

  /// The discard prompt's cancel label, which returns to the form.
  final String discardCancelLabel;

  /// An optional secondary action's label.
  final String? secondaryLabel;

  /// The secondary action.
  final VoidCallback? onSecondary;

  /// Whether the form holds unsaved edits. Drives the guard.
  final bool isDirty;

  /// Whether a save is in flight. Disables both actions and shows progress on the primary.
  final bool isSubmitting;

  /// Padding around [child], inside the scroll view.
  final EdgeInsetsGeometry padding;

  Future<void> _confirmDiscard(BuildContext context) async {
    final navigator = Navigator.of(context);
    final discard = await ConfirmSheet.show(
      context,
      title: discardTitle,
      body: discardBody,
      confirmLabel: discardConfirmLabel,
      cancelLabel: discardCancelLabel,
      destructive: true,
    );
    if (discard && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = isDirty || isSubmitting;
    return PopScope<Object?>(
      canPop: !blocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || isSubmitting) return;
        unawaited(_confirmDiscard(context));
      },
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: padding,
              child: child,
            ),
          ),
          _FormFooter(
            primaryLabel: primaryLabel,
            onPrimary: isSubmitting ? null : onPrimary,
            secondaryLabel: secondaryLabel,
            onSecondary: isSubmitting ? null : onSecondary,
            isSubmitting: isSubmitting,
          ),
        ],
      ),
    );
  }
}

class _FormFooter extends StatelessWidget {
  const _FormFooter({
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    required this.isSubmitting,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = secondaryLabel;

    final primary = FilledButton(
      onPressed: onPrimary,
      child: isSubmitting
          ? SizedBox(
              width: AlayaSpacing.lg,
              height: AlayaSpacing.lg,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.onPrimary,
              ),
            )
          : Text(primaryLabel),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: secondary == null
                ? SizedBox(width: double.infinity, child: primary)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onSecondary,
                          child: Text(secondary),
                        ),
                      ),
                      const SizedBox(width: AlayaSpacing.sm),
                      Expanded(flex: 2, child: primary),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/alaya_list_skeleton.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';

/// The loading state for any list surface (ARCH_5 §5.2).
///
/// **A skeleton rather than a spinner, and deliberately without shimmer.** The shape of what is
/// arriving tells the user more than a spinner does, and a spinner centred in a screen that is about
/// to be a list reads as "slow". Shimmer is left out because it is an animation the user waits
/// through on a surface that exists only to be replaced — and because it would have to be suppressed
/// under `disableAnimations` anyway, leaving this exact widget as the fallback.
///
/// Non-scrollable: it fills whatever room it is given and clips the rest, so it can never overflow
/// the space a list was going to occupy.
class AlayaListSkeleton extends StatelessWidget {
  /// Creates a skeleton of [rows] placeholder rows, described to assistive technology as [label].
  const AlayaListSkeleton({
    required this.label,
    this.rows = 5,
    this.hasLeading = true,
    this.hasTrailing = true,
    super.key,
  });

  /// What is loading, already localised. `CircularProgressIndicator` has semantics; a box does not.
  final String label;

  /// How many placeholder rows to draw.
  final int rows;

  /// Whether rows show a leading identity block — an icon or a colour dot.
  final bool hasLeading;

  /// Whether rows show a trailing block, which in this app is almost always an amount.
  final bool hasTrailing;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    liveRegion: true,
    child: ExcludeSemantics(
      child: ListView.builder(
        // `shrinkWrap` and `NeverScrollableScrollPhysics` travel together. The physics say it
        // will not scroll; `shrinkWrap` is what lets it size to its children instead of
        // demanding a viewport. One without the other throws the moment this skeleton renders
        // inside another scrollable — which is every detail screen, on its first frame.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xs),
        itemCount: rows,
        itemBuilder: (context, index) => _SkeletonRow(
          hasLeading: hasLeading,
          hasTrailing: hasTrailing,
          // Varied widths so the block reads as content rather than as a loading bar.
          titleFactor: index.isEven ? 0.55 : 0.4,
        ),
      ),
    ),
  );
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow({
    required this.hasLeading,
    required this.hasTrailing,
    required this.titleFactor,
  });

  final bool hasLeading;
  final bool hasTrailing;
  final double titleFactor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AlayaSpacing.screenEdge,
      vertical: AlayaSpacing.sm,
    ),
    child: Row(
      children: [
        if (hasLeading) ...[
          const _Block(
            width: AlayaSpacing.xxl,
            height: AlayaSpacing.xxl,
            rounded: true,
          ),
          const SizedBox(width: AlayaSpacing.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: titleFactor,
                child: const _Block(height: AlayaSpacing.md),
              ),
              const SizedBox(height: AlayaSpacing.xxs),
              const FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: 0.3,
                child: _Block(height: AlayaSpacing.sm),
              ),
            ],
          ),
        ),
        if (hasTrailing) ...[
          const SizedBox(width: AlayaSpacing.md),
          const _Block(width: AlayaSpacing.xxxl, height: AlayaSpacing.md),
        ],
      ],
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.height, this.width, this.rounded = false});

  final double height;
  final double? width;
  final bool rounded;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: context.semantic.surfaceSunken,
      borderRadius: rounded ? AlayaRadii.borderSm : AlayaRadii.borderXs,
    ),
  );
}
```

### `lib/shared/widgets/alaya_search_field.dart`

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The search input for every catalogue screen (ARCH_5 §3 archetype D).
///
/// **A visible field rather than a magnifying glass in the app bar.** Catalogues in this app are
/// searched constantly — an item you are about to consume, an asset you are about to service — and
/// hiding the field behind a tap costs an interaction every single time.
///
/// Debounced through [AlayaDurations.debounce] so a query does not run per keystroke, and the timer
/// is cancelled on dispose so a pending callback cannot fire into a disposed widget.
class AlayaSearchField extends StatefulWidget {
  /// Creates a search field reporting through [onChanged].
  const AlayaSearchField({
    required this.onChanged,
    required this.clearLabel,
    this.hintText,
    this.initialValue,
    this.autofocus = false,
    super.key,
  });

  /// Called with the trimmed query once typing settles, and immediately on clear.
  final ValueChanged<String> onChanged;

  /// Accessibility label for the clear button, already localised.
  final String clearLabel;

  /// Placeholder text, already localised.
  final String? hintText;

  /// A starting query, for a screen restoring its state.
  final String? initialValue;

  /// Whether to focus on mount. False on a list screen — a keyboard the user did not ask for
  /// covers the content they came to read.
  final bool autofocus;

  @override
  State<AlayaSearchField> createState() => _AlayaSearchFieldState();
}

class _AlayaSearchFieldState extends State<AlayaSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  Timer? _debounce;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
  }

  void _handleChanged(String raw) {
    final nowHasText = raw.isNotEmpty;
    if (nowHasText != _hasText) setState(() => _hasText = nowHasText);
    _debounce?.cancel();
    _debounce = Timer(
      AlayaDurations.debounce,
      () => widget.onChanged(raw.trim()),
    );
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    // Immediate rather than debounced: clearing is a decision, not a keystroke on the way to one.
    widget.onChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: widget.autofocus,
    textInputAction: TextInputAction.search,
    style: AlayaTypography.body,
    decoration: InputDecoration(
      hintText: widget.hintText,
      prefixIcon: const Icon(Icons.search, size: AlayaIconSize.md),
      suffixIcon: _hasText
          ? IconButton(
              icon: const Icon(Icons.close, size: AlayaIconSize.md),
              tooltip: widget.clearLabel,
              onPressed: _clear,
            )
          : null,
    ),
    onChanged: _handleChanged,
  );
}
```

### `lib/shared/widgets/alaya_timeline.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// How a timeline entry is toned.
enum TimelineTone {
  /// The default — a neutral event.
  neutral,

  /// Stock arriving.
  incoming,

  /// Stock leaving.
  outgoing,

  /// A correction, drawn muted and struck through.
  superseded,
}

/// One event on an [AlayaTimeline].
class AlayaTimelineEntry {
  /// Creates an entry.
  const AlayaTimelineEntry({
    required this.title,
    required this.trailing,
    this.subtitle,
    this.meta,
    this.icon,
    this.tone = TimelineTone.neutral,
    this.badge,
    this.onTap,
  });

  /// What happened.
  final String title;

  /// The figure, rendered by the caller so `Qty` still goes through `QtyText` (U7).
  final Widget trailing;

  /// When it happened, rendered by the caller so `DateKey` still goes through `DateText` (U7).
  final Widget? subtitle;

  /// A secondary line — a reason, a note.
  final String? meta;

  /// A glyph on the rail.
  final IconData? icon;

  /// How to tone the entry.
  final TimelineTone tone;

  /// A chip-like marker, e.g. "Reversed".
  final String? badge;

  /// Opens the entry.
  final VoidCallback? onTap;
}

/// A vertical event timeline (ARCH_5 §8), returned as a sliver.
///
/// **Takes a builder, not a list.** An earlier version took `List<AlayaTimelineEntry>`, and because
/// every entry holds constructed widgets — a `QtyText`, a `DateText` — a batch with a year of
/// consumption allocated the whole year's widgets on every rebuild. Rendering was virtualised;
/// construction was not, which is the half of U13 that a `SliverList` alone does not give you.
///
/// Place it inside a `CustomScrollView`.
class AlayaTimeline extends StatelessWidget {
  /// Creates the timeline.
  const AlayaTimeline({
    required this.itemCount,
    required this.itemBuilder,
    super.key,
  });

  /// How many events there are.
  final int itemCount;

  /// Builds the event at [index], newest first.
  final AlayaTimelineEntry Function(BuildContext context, int index)
  itemBuilder;

  @override
  Widget build(BuildContext context) => SliverList.builder(
    itemCount: itemCount,
    itemBuilder: (context, index) => _Entry(
      entry: itemBuilder(context, index),
      isFirst: index == 0,
      isLast: index == itemCount - 1,
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final AlayaTimelineEntry entry;
  final bool isFirst;
  final bool isLast;

  Color _toneColour(AlayaSemanticColors semantic) => switch (entry.tone) {
    TimelineTone.neutral => semantic.muted,
    TimelineTone.incoming => semantic.success,
    TimelineTone.outgoing => semantic.danger,
    TimelineTone.superseded => semantic.muted,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final colour = _toneColour(semantic);
    final superseded = entry.tone == TimelineTone.superseded;

    // `IntrinsicHeight` is what lets the connector reach the next entry. The rail is a Column with an
    // `Expanded` segment, and a sliver child's Row has no height of its own — so without this the
    // Column is unbounded and `Expanded` throws rather than stretching.
    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Rail(
              colour: colour,
              icon: entry.icon,
              isFirst: isFirst,
              isLast: isLast,
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **Stacks above 1.5x (Law U21).** `trailing` is whatever the caller passes — an
                  // `AmountText`, a `QtyText` — and it is not flexible, so at a doubled text scale it
                  // takes its natural width and pushes the title off the rail. `Flexible` is the wrong
                  // fix: against a tight `Expanded` the two split evenly and the title truncates at
                  // scale 1, and a clipped figure is a wrong figure.
                  if (MediaQuery.textScalerOf(context).scale(1) >= 1.5) ...[
                    Text(
                      entry.title,
                      style: AlayaTypography.body.copyWith(
                        color: superseded
                            ? semantic.muted
                            : theme.colorScheme.onSurface,
                        decoration: superseded
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xxs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: entry.trailing,
                    ),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: AlayaTypography.body.copyWith(
                              color: superseded
                                  ? semantic.muted
                                  : theme.colorScheme.onSurface,
                              decoration: superseded
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: AlayaSpacing.sm),
                        entry.trailing,
                      ],
                    ),
                  if (entry.subtitle != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    entry.subtitle!,
                  ],
                  if (entry.meta != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    Text(
                      entry.meta!,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ],
                  if (entry.badge != null) ...[
                    const SizedBox(height: AlayaSpacing.xs),
                    _Badge(label: entry.badge!, colour: colour),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final onTap = entry.onTap;
    if (onTap == null) return body;
    return InkWell(onTap: onTap, child: body);
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.colour,
    required this.icon,
    required this.isFirst,
    required this.isLast,
  });

  final Color colour;
  final IconData? icon;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: AlayaIconSize.lg,
    child: Column(
      children: [
        _Line(colour: colour, visible: !isFirst, height: AlayaSpacing.xs),
        Icon(icon ?? Icons.circle, size: AlayaIconSize.sm, color: colour),
        if (!isLast) Expanded(child: _Line(colour: colour, visible: true)),
      ],
    ),
  );
}

class _Line extends StatelessWidget {
  const _Line({required this.colour, required this.visible, this.height});

  final Color colour;
  final bool visible;
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
    width: AlayaSpacing.xxs / 2,
    height: height,
    color: visible ? colour.withValues(alpha: 0.28) : Colors.transparent,
  );
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.colour});

  final String label;
  final Color colour;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AlayaSpacing.xs,
      vertical: AlayaSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.12),
      borderRadius: AlayaRadii.borderXs,
    ),
    child: Text(
      label,
      style: AlayaTypography.overline.copyWith(color: colour),
    ),
  );
}
```

### `lib/shared/widgets/amount_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_parser.dart';
import 'package:alaya/core/result/failure.dart';

/// A money input backed by [MoneyParser].
///
/// **It never rejects an intermediate typing state.** Typing `1`, then `1.`, then `1.2` passes through
/// three inputs of which only two parse — and the field rewrites the text in none of them. A field
/// that "corrects" as you type is unusable: deleting a digit to fix a typo momentarily produces
/// something unparseable, and a field that reformats at that instant moves the cursor and eats the
/// next keystroke.
///
/// So parsing drives [onChanged] and the error text only, never the controller's value.
/// [onChanged] receives null while the input is not yet a valid amount, which is the signal a Save
/// button should disable on — distinct from a zero amount, which is valid input the caller may still
/// choose to reject.
class AmountField extends StatefulWidget {
  /// Creates an amount field.
  const AmountField({
    required this.currencyCode,
    required this.onChanged,
    this.decimalDigits = 2,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.allowNegative = false,
    this.autofocus = false,
    this.controller,
    super.key,
  });

  /// The currency the typed number is denominated in.
  final String currencyCode;

  /// Called on every keystroke with the parsed amount, or null while it does not parse.
  final ValueChanged<Money?> onChanged;

  /// The currency's minor-unit precision. JPY is 0.
  final int decimalDigits;

  /// A starting amount, rendered as plain digits so it is immediately editable.
  final Money? initialValue;

  /// The field's label, already localised.
  final String? label;

  /// Placeholder text, already localised.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  ///
  /// Takes precedence over the internal parse message, because "you have insufficient balance" is more
  /// useful than "enter an amount" when both are true.
  final String? errorText;

  /// Whether a leading minus is accepted.
  final bool allowNegative;

  /// Whether to focus on mount.
  final bool autofocus;

  /// An external controller, when the caller needs to clear or preset the text.
  final TextEditingController? controller;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  static const MoneyParser _parser = MoneyParser();

  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: _initialText());
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    if (initial == null || initial.isZero) return '';
    // Plain digits with a decimal point, not a formatted string: grouping separators in an editable
    // field fight the cursor, and the parser accepts either so there is nothing to gain.
    //
    // Split into a sign and a magnitude rather than dividing the signed minor value: `~/` truncates
    // toward zero, so -50 minor over a divisor of 100 gives a whole part of 0 and the minus sign
    // disappears — a -0.50 opening balance would load as 0.50.
    final divisor = _pow10(widget.decimalDigits);
    final sign = initial.isNegative ? '-' : '';
    final magnitude = initial.minor.abs();
    final whole = magnitude ~/ divisor;
    if (widget.decimalDigits == 0) return '$sign$whole';
    final fraction = (magnitude % divisor).toString().padLeft(
      widget.decimalDigits,
      '0',
    );
    return '$sign$whole.$fraction';
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  void _handleChanged(String raw) {
    if (raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      currencyCode: widget.currencyCode,
      decimalDigits: widget.decimalDigits,
      allowNegative: widget.allowNegative,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] but is also what every user types on the way
  /// to entering paise — so it stays silent. Only failures that cannot become valid by typing more are
  /// surfaced.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorAmountInvalidCharacter,
      ParseFailure.negativeNotAllowed => strings.errorAmountNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorAmountTooManyDecimals,
      ParseFailure.tooLarge => strings.errorAmountTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: widget.autofocus,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textAlign: TextAlign.right,
    style: AlayaTypography.amountLarge,
    inputFormatters: [
      // Filters at the keystroke rather than validating after: a letter in a numeric field is
      // never intentional, and blocking it is not the same as rejecting an incomplete number.
      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-\u0020]')),
      LengthLimitingTextInputFormatter(24),
    ],
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      errorText: widget.errorText ?? _parseMessage(context),
      prefixText: widget.currencyCode,
    ),
    onChanged: _handleChanged,
  );
}
```

### `lib/shared/widgets/amount_text.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/money/money_formatter.dart';

/// How large an amount renders.
enum AmountSize {
  /// The dashboard headline. One per screen.
  display,

  /// A card's primary figure.
  large,

  /// A ledger row. The default.
  medium,

  /// A converted or secondary figure.
  small,
}

/// Renders a [Money] with the app's colour convention and tabular figures.
///
/// **This is the widget the design is built around.** Three things happen here that make a column of
/// amounts readable:
///
/// 1. Tabular figures, from `AlayaTypography`. Digits share one advance width, so values align on the
///    decimal as they change instead of jittering.
/// 2. Colour from [AlayaSemanticColors.forAmount] and nowhere else, so the red/green rule has one
///    definition (ARCH_3 §8.1).
/// 3. **An explicit sign, always.** Colour alone would exclude the roughly eight percent of men with
///    a red-green deficiency; the palettes additionally keep income lighter than expense, but a glyph
///    is the only signal that survives both colour blindness and a greyscale screenshot.
class AmountText extends StatelessWidget {
  /// Creates an amount.
  const AmountText(
    this.amount, {
    this.size = AmountSize.medium,
    this.decimalDigits = 2,
    this.symbol,
    this.kind,
    this.showSign = true,
    this.muted = false,
    this.textAlign,
    super.key,
  });

  /// The amount.
  final Money amount;

  /// How large to render it.
  final AmountSize size;

  /// The currency's minor-unit precision.
  ///
  /// Defaults to 2. The real value lives on the `currencies` row, and a feature screen that has the
  /// currency to hand should pass it — JPY has 0 and rendering `¥1,200.00` is wrong.
  final int decimalDigits;

  /// The currency symbol.
  ///
  /// Defaults to the currency code, which is never wrong even when it is less pretty than `₹`. A
  /// hardcoded symbol would be wrong for every other currency the app supports.
  final String? symbol;

  /// The transaction kind, when known.
  ///
  /// Supplied only to colour a transfer neutrally: a transfer's leg is signed like any other, so
  /// without this it would render as income on the way in and expense on the way out — one movement
  /// of money looking like two different things.
  final TransactionKind? kind;

  /// Whether to render the sign.
  ///
  /// Defaults to true. Set false only where the direction is already unambiguous in the layout — a
  /// column headed "Spent", for instance.
  final bool showSign;

  /// Renders in the muted colour instead of the semantic one, for a disabled or historical row.
  final bool muted;

  /// How to align the text. Amounts in a column should be [TextAlign.right].
  final TextAlign? textAlign;

  static const MoneyFormatter _formatter = MoneyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final color = muted
        ? semantic.muted
        : kind == null
        ? semantic.forAmount(amount)
        : semantic.forTransactionKind(kind!, amount);

    return Text(
      _formatter.format(
        amount,
        decimalDigits: decimalDigits,
        symbol: symbol ?? amount.currencyCode,
        showPlusSign: showSign && amount.isPositive,
      ),
      style: _styleFor(size).copyWith(color: color),
      textAlign: textAlign,
      maxLines: 1,
      // An amount is never truncated with an ellipsis: a partly shown number reads as a smaller
      // number. Scaling down is wrong for the same reason, so it clips and the caller gives it room.
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }

  TextStyle _styleFor(AmountSize size) => switch (size) {
    AmountSize.display => AlayaTypography.displayAmount,
    AmountSize.large => AlayaTypography.amountLarge,
    AmountSize.medium => AlayaTypography.amountMedium,
    AmountSize.small => AlayaTypography.amountSmall,
  };
}
```

### `lib/shared/widgets/chart_card.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One analytics figure in a card, owning all four of its states (ARCH_5 §7's `ChartCard`).
///
/// **The reason this is shared rather than written per surface is Law U4.** Twenty-four figures each
/// needing loading, empty, error and populated is ninety-six states, and the failure mode ARCH_5 §0
/// names — "a screen that is nearly a screen" — is what happens when the twenty-fourth author is
/// bored. Here they are written once and every surface inherits them.
///
/// **A failing card costs the reader that card and nothing else** (ARCH_5 §3 archetype F). The error
/// branch renders inside the card, so an unreachable rate table blanks one figure rather than the
/// screen.
///
/// This *is* the tier-1 surface, so nothing handed to [builder] may be another [AlayaCard]
/// (ARCH_5 §2.5). Group inside it with space and a `SectionHeader`.
///
/// **A `StatelessWidget` that imports `flutter_riverpod` for `AsyncValue` and nothing else.** It reads
/// no provider and takes no `WidgetRef` — the caller watches, this renders. `shared/tag_picker.dart`
/// already imports the package for the same reason, and Law L12's layering is about `core` → `domain`
/// → `data` → `features`, which a state-management type does not cross.
class ChartCard<T> extends StatelessWidget {
  /// Creates a card for [value], titled [title].
  const ChartCard({
    required this.title,
    required this.value,
    required this.isEmpty,
    required this.emptyMessage,
    required this.builder,
    required this.onRetry,
    this.subtitle,
    this.approximateCount = 0,
    this.unconvertedCount = 0,
    this.onTap,
    this.trailing,
    super.key,
  });

  /// What this figure answers, already localised. Sentence case (ARCH_5 §2.8).
  final String title;

  /// An optional line under the title — the window, the unit, the caveat.
  final String? subtitle;

  /// The figure, consumed with all three branches (Law U4).
  final AsyncValue<T> value;

  /// Whether the loaded figure holds nothing.
  ///
  /// Required rather than inferred: "empty" is different for every result type — an empty slice
  /// list, a zero total, a trend with one point — and a widget guessing at it would show a chart
  /// axis with no data and call that populated.
  final bool Function(T data) isEmpty;

  /// What to say when there is nothing yet. Names the next action where there is one (ARCH_5 §2.8).
  final String emptyMessage;

  /// Renders the populated figure.
  final Widget Function(BuildContext context, T data) builder;

  /// Recomputes this figure. Wired to `ref.invalidate` of the provider behind it.
  final VoidCallback onRetry;

  /// How many of this figure's data points converted only approximately (ARCH_3 §1.3).
  final int approximateCount;

  /// How many could not be converted at all, and are therefore **excluded** from the figure.
  ///
  /// Surfaced rather than hidden, because a total that silently omitted an unconvertible amount
  /// would look complete while under-reporting (anomaly A15, A34).
  final int unconvertedCount;

  /// Opens the drill-down behind this figure.
  final VoidCallback? onTap;

  /// A rendered value beside the title — an `AmountText` carrying the figure's headline.
  final Widget? trailing;

  /// Above this text scale the header stacks instead of sharing a row (Law U21).
  static const double _stackAboveScale = 1.5;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final scale = MediaQuery.textScalerOf(context).scale(1);

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: title,
            subtitle: subtitle,
            trailing: trailing,
            showChevron: onTap != null,
            stacked: scale >= _stackAboveScale,
          ),
          const SizedBox(height: AlayaSpacing.sm),
          value.when(
            // Not a spinner: a card that is about to hold a chart reads as "slow" behind one
            // (ARCH_5 §5.2). A muted line naming what is coming says more and costs no layout.
            loading: () => Text(
              strings.chartLoading,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            // The repository's own message, never a generic body (Law U9). A figure that fails
            // identically for every cause is a bug nobody can find.
            error: (error, stack) => _CardError(
              message: error.toString(),
              retryLabel: strings.actionRetry,
              onRetry: onRetry,
            ),
            // **The builder is never wrapped in a fixed height.** A card sizes to its own content and
            // the screen's `SliverList` scrolls; a chart inside it asks for its own height through
            // `AnalyticsPlotBox`. Bounding the whole builder here squeezed the title and the subtitle of
            // any card that put chrome above its plot.
            data: (data) => isEmpty(data)
                ? Text(
                    emptyMessage,
                    style: AlayaTypography.body.copyWith(color: semantic.muted),
                  )
                : builder(context, data),
          ),
          if (approximateCount > 0 || unconvertedCount > 0) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Wrap(
              spacing: AlayaSpacing.xs,
              runSpacing: AlayaSpacing.xxs,
              children: [
                if (unconvertedCount > 0)
                  StatusChip(
                    label: strings.chartUnconverted(unconvertedCount),
                    tone: StatusTone.warning,
                  ),
                if (approximateCount > 0)
                  StatusChip(
                    label: strings.chartApproximate(approximateCount),
                    tone: StatusTone.info,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// The title, its subtitle, and whatever sits opposite them.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.showChevron,
    required this.stacked,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool showChevron;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            subtitle!,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
        ],
      ],
    );

    final chevron = showChevron
        ? Padding(
            padding: const EdgeInsets.only(left: AlayaSpacing.xs),
            child: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
          )
        : null;

    // **Stacked above 1.5x, and `Flexible` on the value is not the fix** (Law U21). `trailing` is
    // usually an `AmountText`, which clips rather than ellipsises — so a clipped figure is a wrong
    // figure, and it must be given its own row rather than squeezed. Against a tight `Expanded` the
    // two would split evenly and the *title* would truncate at scale 1 instead.
    if (stacked) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: label),
              if (chevron != null) chevron,
            ],
          ),
          if (trailing != null) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: label),
        if (trailing != null) ...[
          const SizedBox(width: AlayaSpacing.sm),
          trailing!,
        ],
        if (chevron != null) chevron,
      ],
    );
  }
}

/// An inline failure, sized for a card rather than for a screen.
///
/// Not `ErrorState`: that one is a full-height state with a 40px glyph and its own
/// `ScrollSafeCenter`, which inside a card would push every sibling off the screen.
class _CardError extends StatelessWidget {
  const _CardError({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline,
              size: AlayaIconSize.md,
              color: semantic.danger,
            ),
            const SizedBox(width: AlayaSpacing.xs),
            Expanded(
              child: Text(
                message,
                style: AlayaTypography.caption.copyWith(color: semantic.danger),
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onRetry,
            child: Text(retryLabel, style: AlayaTypography.button),
          ),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/confirm_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// A bottom sheet asking the user to confirm something.
///
/// A sheet rather than a dialog: it appears near the thumb, and on a one-handed phone a centred
/// dialog puts the destructive button where a stretch is needed.
///
/// Returns `true` only on explicit confirmation. Dismissing by tapping outside or swiping down
/// returns `false` rather than null, so a caller cannot treat "they walked away" as consent by
/// forgetting a null check.
class ConfirmSheet extends StatelessWidget {
  /// Creates a confirmation sheet. Prefer [show].
  const ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    this.destructive = false,
    super.key,
  });

  /// The question, phrased so that confirming is the obvious reading.
  final String title;

  /// What confirming will do, including anything reversible about it.
  final String body;

  /// The confirm button's label. Names the action — "Delete", not "OK".
  final String confirmLabel;

  /// The cancel button's label.
  final String cancelLabel;

  /// Renders the confirm button in the danger colour.
  final bool destructive;

  /// Shows the sheet and resolves to whether the user confirmed.
  ///
  /// Through [AlayaBottomSheet.show], so the content scrolls. There is no keyboard here, but a user
  /// at a large accessibility text scale can still make a title, a body and two buttons taller than
  /// the sheet — the same overflow with a different cause.
  static Future<bool> show(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
    bool destructive = false,
  }) async {
    final result = await AlayaBottomSheet.show<bool>(
      context: context,
      builder: (context) => ConfirmSheet(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        destructive: destructive,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    // AlayaBottomSheet owns the safe area, the padding and the scroll view.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          body,
          style: AlayaTypography.body.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: semantic.danger,
                  foregroundColor: semantic.onStatus,
                )
              : null,
          child: Text(confirmLabel),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel),
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/date_picker_field.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/core/time/date_key.dart';

/// Picks a civil date, working in [DateKey] throughout.
///
/// Converts to `DateTime` only to hand Material's picker something it understands, and converts
/// straight back. Holding a `DateTime` in the field's state would reintroduce the time-of-day and
/// timezone that `DateKey` exists to eliminate — and a date that shifts by a day near midnight is the
/// exact bug the type prevents.
class DatePickerField extends StatelessWidget {
  /// Creates a date field.
  const DatePickerField({
    required this.value,
    required this.onChanged,
    required this.formatted,
    this.label,
    this.hint,
    this.errorText,
    this.firstDate,
    this.lastDate,
    this.enabled = true,
    super.key,
  });

  /// The selected date, or null when unset.
  final DateKey? value;

  /// Called with the newly chosen date.
  final ValueChanged<DateKey> onChanged;

  /// Renders [value] for display.
  ///
  /// Injected because date formatting is locale-dependent and belongs with the caller's formatter,
  /// not duplicated inside a field widget.
  final String Function(DateKey) formatted;

  /// The field's label.
  final String? label;

  /// Placeholder shown when [value] is null.
  final String? hint;

  /// An error from the caller.
  final String? errorText;

  /// Earliest selectable date. Defaults to ten years back.
  final DateKey? firstDate;

  /// Latest selectable date. Defaults to five years forward.
  final DateKey? lastDate;

  /// Whether the field accepts input.
  final bool enabled;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final initial = value?.toUtcMidnight() ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate?.toUtcMidnight() ?? DateTime(now.year - 10),
      lastDate: lastDate?.toUtcMidnight() ?? DateTime(now.year + 5),
    );
    if (picked != null) onChanged(DateKey.fromDateTime(picked));
  }

  @override
  Widget build(BuildContext context) {
    final current = value;
    return InkWell(
      onTap: enabled ? () => _pick(context) : null,
      child: InputDecorator(
        // **The hint belongs to the decoration, not to the child.** With `isEmpty: true` the label sits
        // inside the field rather than floating, and a child `Text(hint)` then renders in exactly the
        // same place — so an unset date showed its label and its hint on top of each other. Handing the
        // hint to `InputDecoration` lets the decorator own that collision, which is the only thing that
        // knows where the label currently is.
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          suffixIcon: Icon(
            Icons.calendar_today_outlined,
            size: AlayaIconSize.md,
          ),
          enabled: enabled,
        ),
        isEmpty: current == null,
        child: current == null
            ? const SizedBox.shrink()
            : Text(formatted(current)),
      ),
    );
  }
}
```

### `lib/shared/widgets/date_text.dart`

```dart
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';

/// How a [DateText] renders its date.
enum DateTextStyle {
  /// `Saturday, 1 August 2026` — a detail screen's one date field.
  full,

  /// `1 Aug 2026` — the default. List rows, key/value rows.
  medium,

  /// `1 Aug` — a sticky day header, a dense chip, a chart axis.
  dayMonth,

  /// `Today`, `Yesterday`, `Tomorrow`, else [medium]. Only via [DateText.relative].
  relative,
}

/// Renders a [DateKey], and is the only path from one to pixels (Law U7).
///
/// **Never `DateKey.toString()`.** That prints the raw `yyyymmdd` integer, which is a debug
/// representation — `20260801` in front of a user instead of `1 Aug 2026`.
///
/// Formatting goes through `intl` against the widget's own locale, so the same date reads correctly
/// in `en_IN` and `de_DE` without a call site knowing which. The [DateKey] is converted with
/// [DateKey.toUtcMidnight], whose calendar fields are the civil ones by construction — no timezone
/// can shift the rendered day, which is the entire reason Law L4 separates civil dates from
/// instants.
class DateText extends StatelessWidget {
  /// Renders [date] in [style]. [DateTextStyle.relative] is unavailable here — use [DateText.relative].
  const DateText(
    this.date, {
    this.style = DateTextStyle.medium,
    this.textStyle,
    this.muted = false,
    this.textAlign,
    super.key,
  }) : _clock = null,
       assert(
         style != DateTextStyle.relative,
         'DateTextStyle.relative needs a Clock. Use DateText.relative().',
       );

  /// Renders [date] as `Today` / `Yesterday` / `Tomorrow`, falling back to [DateTextStyle.medium].
  ///
  /// Takes the [Clock] rather than calling `DateTime.now()`, so a date-sensitive golden or widget
  /// test is reproducible instead of depending on the day it ran.
  const DateText.relative(
    this.date, {
    required Clock clock,
    this.textStyle,
    this.muted = false,
    this.textAlign,
    super.key,
  }) : style = DateTextStyle.relative,
       _clock = clock;

  /// The civil date to render.
  final DateKey date;

  /// Which presentation to use.
  final DateTextStyle style;

  /// Overrides the default [AlayaTypography.caption].
  final TextStyle? textStyle;

  /// Renders in the muted colour, for a secondary or historical row.
  final bool muted;

  /// How to align the text.
  final TextAlign? textAlign;

  final Clock? _clock;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      _format(context),
      style: (textStyle ?? AlayaTypography.caption).copyWith(
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _format(BuildContext context) {
    final localeTag = Localizations.localeOf(context).toString();
    final moment = date.toUtcMidnight();

    if (style == DateTextStyle.relative) {
      final clock = _clock;
      if (clock != null) {
        final strings = AlayaStrings.of(context);
        switch (date.diffDays(clock.today())) {
          case 0:
            return strings.dateToday;
          case -1:
            return strings.dateYesterday;
          case 1:
            return strings.dateTomorrow;
        }
      }
      return DateFormat.yMMMd(localeTag).format(moment);
    }

    return switch (style) {
      DateTextStyle.full => DateFormat.yMMMMEEEEd(localeTag).format(moment),
      DateTextStyle.medium => DateFormat.yMMMd(localeTag).format(moment),
      DateTextStyle.dayMonth => DateFormat.MMMd(localeTag).format(moment),
      DateTextStyle.relative => DateFormat.yMMMd(localeTag).format(moment),
    };
  }
}
```

### `lib/shared/widgets/empty_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when it has nothing to show.
///
/// **An empty screen is an invitation to act, not a report that there is no data.** So [body] names
/// the next step and [actionLabel] performs it — "Add your first expense and it will appear here",
/// not "No data available". The copy lives in the ARB; this widget only lays it out.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. The
/// vertical margin is `xl` rather than `xxxl` because it is a *minimum*: the content is centred in
/// whatever space there is, so a larger figure buys nothing on a tall screen and costs 48px of
/// headroom on a short one.
class EmptyState extends StatelessWidget {
  /// Creates an empty state.
  const EmptyState({
    required this.title,
    required this.body,
    this.icon,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// A short line naming what is absent.
  final String title;

  /// One or two lines naming what to do about it.
  final String body;

  /// An optional icon above the title.
  final IconData? icon;

  /// The action's label. Ignored when [onAction] is null.
  final String? actionLabel;

  /// The action.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return ScrollSafeCenter(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xxl,
        vertical: AlayaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.xl, color: semantic.muted),
            const SizedBox(height: AlayaSpacing.md),
          ],
          Text(
            title,
            style: AlayaTypography.cardTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            body,
            style: AlayaTypography.body.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/error_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';

/// What a screen shows when a read failed.
///
/// **Errors do not apologise and are never vague about what happened.** [title] names the failure and
/// [body] says what to do; neither says "sorry". A retry appears only when retrying could plausibly
/// work — offering it for a deleted record trains the user to ignore the button.
///
/// Scrolls rather than overflowing when the viewport is short, through [ScrollSafeCenter]. This one
/// is the tallest of the three states — icon, two text blocks and a 48px button — so it is the one
/// most likely to meet a viewport that cannot hold it.
class ErrorState extends StatelessWidget {
  /// Creates an error state.
  const ErrorState({
    required this.title,
    required this.body,
    this.retryLabel,
    this.onRetry,
    super.key,
  });

  /// What went wrong.
  final String title;

  /// What to do about it.
  final String body;

  /// The retry action's label. Ignored when [onRetry] is null.
  final String? retryLabel;

  /// The retry action.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return ScrollSafeCenter(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xxl,
        vertical: AlayaSpacing.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: AlayaIconSize.xl,
            color: semantic.danger,
          ),
          const SizedBox(height: AlayaSpacing.md),
          Text(
            title,
            style: AlayaTypography.cardTitle.copyWith(
              color: theme.colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            body,
            style: AlayaTypography.body.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null && retryLabel != null) ...[
            const SizedBox(height: AlayaSpacing.xl),
            OutlinedButton(onPressed: onRetry, child: Text(retryLabel!)),
          ],
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/filter_chip_bar.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One active filter, rendered as a removable chip.
class ActiveFilter {
  /// Creates a filter labelled [label] that [onRemove] clears.
  const ActiveFilter({required this.label, required this.onRemove});

  /// What is filtered, already localised and including the value — "Account: HDFC", not "Account".
  final String label;

  /// Clears just this filter.
  final VoidCallback onRemove;
}

/// The active-filter row above a ledger list (ARCH_5 §3 archetype C).
///
/// **A filter the user cannot see is a bug report waiting to happen.** A list quietly constrained by
/// a filter set on a previous visit is indistinguishable from a list that lost its data, and "my
/// transactions disappeared" is the support mail that follows. So every active filter is visible and
/// individually removable, and the bar disappears entirely when nothing is filtered.
///
/// A [Wrap] rather than a horizontal scroller: a scroller has to be given a height, and a fixed
/// height overflows the moment the text scale is raised (Law U15).
class FilterChipBar extends StatelessWidget {
  /// Creates a bar for [filters]. Renders nothing when the list is empty.
  const FilterChipBar({
    required this.filters,
    this.onClearAll,
    this.clearAllLabel,
    super.key,
  });

  /// The filters currently narrowing the list.
  final List<ActiveFilter> filters;

  /// Clears every filter at once. Offered only when more than one is active.
  final VoidCallback? onClearAll;

  /// The clear-all action's label, already localised.
  final String? clearAllLabel;

  @override
  Widget build(BuildContext context) {
    if (filters.isEmpty) return const SizedBox.shrink();
    final showClearAll =
        onClearAll != null && clearAllLabel != null && filters.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.xs,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final filter in filters) _FilterChip(filter: filter),
          if (showClearAll)
            TextButton(
              onPressed: onClearAll,
              child: Text(clearAllLabel!, style: AlayaTypography.button),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.filter});

  final ActiveFilter filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: filter.label,
      child: Material(
        color: theme.colorScheme.secondary.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderXs,
          side: BorderSide(
            color: theme.colorScheme.secondary.withValues(alpha: 0.28),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: filter.onRemove,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Center(
              widthFactor: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.xs,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        filter.label,
                        style: AlayaTypography.overline.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AlayaSpacing.xxs),
                    Icon(
                      Icons.close,
                      size: AlayaIconSize.sm,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/frequency_preview.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/shared/widgets/date_text.dart';

/// One date a schedule will land on, and whether the anchor had to shorten to reach it.
class PreviewedDate {
  /// Creates a previewed date.
  const PreviewedDate({required this.dateKey, this.clamped = false});

  /// When it lands.
  final DateKey dateKey;

  /// Whether the anchor day exceeded this month and was pulled back to its last day.
  final bool clamped;
}

/// Shows where a schedule actually lands (ARCH_5 §8 — the one shared addition Phase 6D makes).
///
/// **This is the only way a user can tell a clamp is doing what they meant.** A bill anchored on the
/// 31st shows Jan 31, Feb 28, Mar 31 — and the February row says it was shortened. Without that, a
/// user who typed 31 and saw 28 would reasonably conclude the app lost their input, and the
/// alternative designs are worse: refusing days above 28 makes the 31st unexpressible, and silently
/// storing 28 walks the anchor backwards forever (anomaly A13).
///
/// The dates are computed by the caller from `RecurringEngine.nextDue`, not here. This widget renders;
/// duplicating the arithmetic would give the preview and the materialiser two answers.
class FrequencyPreview extends StatelessWidget {
  /// Creates the preview.
  const FrequencyPreview({required this.dates, super.key});

  /// The next few dates, soonest first. Empty renders a prompt rather than nothing.
  final List<PreviewedDate> dates;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Container(
      padding: const EdgeInsets.all(AlayaSpacing.sm),
      decoration: BoxDecoration(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.event_repeat,
                size: AlayaIconSize.sm,
                color: semantic.muted,
              ),
              const SizedBox(width: AlayaSpacing.xxs),
              Expanded(
                child: Text(
                  strings.previewTitle,
                  style: AlayaTypography.label.copyWith(color: semantic.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.xs),
          if (dates.isEmpty)
            Text(
              strings.previewEmpty,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            )
          else
            for (final date in dates)
              Padding(
                padding: const EdgeInsets.only(bottom: AlayaSpacing.xxs),
                // A `Wrap`: the date and the clamp note both grow with text scale, and a `Row` would
                // starve one of them at 320dp (Law U21).
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DateText(date.dateKey, style: DateTextStyle.full),
                    if (date.clamped)
                      Text(
                        strings.previewClamped,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.warning,
                        ),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/key_value_row.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One label/value line on a detail screen (ARCH_5 §3 archetype E).
///
/// **Renders nothing at all when there is no value.** A detail screen that shows `—` for every
/// unset field reads as broken data rather than as a record with optional fields, and on a schema
/// where most columns are nullable that is most of the screen. Hiding the row is the difference
/// between "this asset has no warranty" and "this app failed to load the warranty".
///
/// Both sides are [Flexible], so a long value wraps instead of overflowing — which is what keeps
/// the row safe at a doubled text scale (Law U15).
class KeyValueRow extends StatelessWidget {
  /// Creates a row for [label]. Renders nothing unless [value] or [valueWidget] is supplied.
  const KeyValueRow({
    required this.label,
    this.value,
    this.valueWidget,
    this.onTap,
    this.icon,
    super.key,
  });

  /// The field's name, already localised.
  final String label;

  /// The value as text. Ignored when [valueWidget] is supplied.
  final String? value;

  /// The value as a widget — an `AmountText`, a `QtyText`, a `DateText`, a chip row.
  ///
  /// Preferred over [value] for anything typed: Law U7 routes every `Money`, `Qty` and `DateKey`
  /// through its own widget, and formatting one into a string here would bypass that.
  final Widget? valueWidget;

  /// Makes the row tappable — a payee that opens its detail, a phone number that dials.
  final VoidCallback? onTap;

  /// A leading icon, for a row that is also an action.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final rendered = valueWidget;
    if (rendered == null && value == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final semantic = context.semantic;

    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.md, color: semantic.muted),
            const SizedBox(width: AlayaSpacing.sm),
          ],
          Flexible(
            flex: 2,
            child: Text(
              label,
              style: AlayaTypography.label.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AlayaSpacing.md),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child:
                  rendered ??
                  Text(
                    value!,
                    style: AlayaTypography.body.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.end,
                  ),
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AlayaSpacing.xs),
            Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AlayaSpacing.minTapTarget,
          ),
          child: content,
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/loading_state.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A centred loading indicator with a label.
///
/// The label is not decoration: a bare spinner tells a screen reader nothing, and
/// `CircularProgressIndicator` has no implicit semantics of its own.
class LoadingState extends StatelessWidget {
  /// Creates a loading state.
  const LoadingState({required this.label, this.compact = false, super.key});

  /// What is loading, already localised.
  final String label;

  /// Renders inline rather than filling the viewport — for a list footer.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final indicator = SizedBox(
      width: AlayaSpacing.xl,
      height: AlayaSpacing.xl,
      child: CircularProgressIndicator(strokeWidth: 2, semanticsLabel: label),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(AlayaSpacing.md),
        child: Center(child: indicator),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          indicator,
          const SizedBox(height: AlayaSpacing.md),
          Text(
            label,
            style: AlayaTypography.caption.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/measure_text.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/measure.dart';
import 'package:alaya/core/quantity/measure_formatter.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Renders a [Measure] in a named unit, and is the only path from one to pixels.
///
/// **A sibling of [QtyText] rather than a parameter on it, and the split is deliberate.** `QtyText` is
/// consumed by six features and derives its own unit from the category — `4 kg 450 g`, `3 pc` — because a
/// stored quantity is unit-free and the best presentation of it is a property of the number. Adding an
/// optional `unit` would have put a concern belonging to three recipe screens into a widget every screen
/// uses, and given `QtyText` two modes that need explaining to every reader of every call site.
///
/// **The unit's `code` is the label, not its `displayName`.** `1 1/2 tbsp` is how a recipe is written;
/// `1 1/2 Tablespoon` is how a database is written. The code is already the abbreviation cooks use, which
/// also side-steps pluralisation — there is no `displayNamePlural` column and "1 1/2 tablespoon" would
/// need one.
///
/// **`≈` when the amount was snapped, and never otherwise.** [MeasureStyle.kitchen] rounds to what a
/// measuring set can produce, so the text can stop being the stored value — and a row that showed a
/// snapped figure as though it were exact would be asserting something false. The glyph is the whole cost
/// of not doing that, and `RenderedMeasure.isApproximate` decides when it appears, so at a recipe's own
/// serving count nothing is marked anywhere.
class MeasureText extends StatelessWidget {
  /// Renders [measure] in [unit].
  const MeasureText(
    this.measure, {
    required this.unit,
    this.style = MeasureStyle.exact,
    this.muted = false,
    this.textStyle,
    this.textAlign,
    super.key,
  });

  /// The amount, in thousandths of [unit].
  final Measure measure;

  /// The unit to render in. Its `code` becomes the label and its factor is not needed here — [measure] is
  /// already expressed in this unit.
  final Unit unit;

  /// Whether to render what the amount is, or what a cook should reach for.
  final MeasureStyle style;

  /// Renders in the muted colour, for a secondary row.
  final bool muted;

  /// Overrides the default [AlayaTypography.quantity].
  final TextStyle? textStyle;

  /// How to align the text.
  final TextAlign? textAlign;

  static const MeasureFormatter _formatter = MeasureFormatter();

  /// The approximation mark. A mathematical symbol rather than copy, like the decimal separator — it
  /// carries no language and is not translated. The sentence explaining it is an ARB string; this is not.
  static const String _approximately = '\u2248';

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final rendered = _formatter.format(
      measure,
      style: style,
      localeTag: Localizations.localeOf(context).toString(),
    );
    final prefix = rendered.isApproximate ? '$_approximately ' : '';

    return Text(
      '$prefix${rendered.text} ${unit.code}',
      style: (textStyle ?? AlayaTypography.quantity).copyWith(
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
```

### `lib/shared/widgets/module_tile.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A navigation tile carrying a live number (ARCH_5 §8 — the one shared addition Phase 6F makes).
///
/// **The number is the point.** A grid of labelled icons is decoration: it tells the user what the app
/// contains, which they already know, and gives no reason to tap one tile rather than another. A count
/// that moves — three items running low, two bills due — is the difference between a menu and a
/// dashboard.
///
/// The count arrives as already-localised text rather than an `int`, because "nothing tracked" and
/// "3 running low" are different sentences and only the ARB knows which to use.
///
/// ## Requires a bounded height, and never overflows inside one
///
/// A grid cell is a fixed box, and both of this tile's labels grow with text scale while the box does
/// not. The first version put a `MainAxisSize.max` column of freely-wrapping `Text`s inside that box and
/// overflowed by 22px at scale 1 and 250px at scale 2 — the P1 shape, one layer in: not a starved
/// `Expanded` sibling but a starved `Column` (Law U2, U21).
///
/// Both `Text`s are therefore `Flexible` and ellipsise. **Ellipsis is legitimate here precisely because
/// neither string is a `Money` or a `Qty`.** U7 forbids truncating a figure because half a number reads
/// as a smaller number; a truncated sentence still reads as a sentence. `ModuleGrid` sizes its cells from
/// the current text scaler, so the ellipsis is a floor the layout rarely reaches rather than the normal
/// case — but it is the floor, and the tile holds it on its own.
///
/// Given an *unbounded* height the flex assertion fires and names the caller, which is the same contract
/// `ScrollSafeCenter` carries. That is deliberate: a tile with nothing bounding it has no shape to
/// defend.
class ModuleTile extends StatelessWidget {
  /// Creates a tile.
  const ModuleTile({
    required this.label,
    required this.icon,
    required this.detail,
    required this.onTap,
    this.tone,
    this.semanticsLabel,
    super.key,
  });

  /// What the module is called — the drawer's own wording, so the tile names somewhere real.
  final String label;

  /// Its glyph.
  final IconData icon;

  /// The live number, already localised and pluralised.
  final String detail;

  /// Opens the module.
  final VoidCallback onTap;

  /// Colours the glyph when the count is worth noticing; muted when it is not.
  final Color? tone;

  /// Overrides the composed semantics label, which otherwise reads label then detail.
  final String? semanticsLabel;

  /// How many lines each of the two labels may take before it truncates.
  ///
  /// Public because `ModuleGrid` reserves exactly this many when it measures a cell. A tile that budgets
  /// two lines inside a cell sized for one is the overflow all over again, so the two read one number.
  static const int maxLabelLines = 2;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;

    return Semantics(
      button: true,
      label: semanticsLabel ?? '$label. $detail',
      excludeSemantics: true,
      child: Material(
        color: semantic.surfaceSunken,
        borderRadius: AlayaRadii.borderMd,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget * 2,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AlayaSpacing.sm),
              // A `Column`, not a `Row`: the label and the count both grow with text scale, and side by
              // side one of them starves at 320dp (Law U21).
              //
              // `min` rather than `max`, and `start` rather than `spaceBetween`: the flexible children
              // already absorb whatever room the cell has, so `spaceBetween` had nothing left to
              // distribute while `max` forced the column to fill a box its content could exceed.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: AlayaIconSize.lg,
                    color: tone ?? semantic.muted,
                  ),
                  const SizedBox(height: AlayaSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      style: AlayaTypography.body.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Flexible(
                    child: Text(
                      detail,
                      style: AlayaTypography.caption.copyWith(
                        color: tone ?? semantic.muted,
                      ),
                      maxLines: maxLabelLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/qty_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_parser.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/unit_picker.dart';

/// A quantity input paired with its unit.
///
/// The number and the unit are one control because a quantity without a unit is meaningless — `2` is
/// not a quantity until you know whether it is kilograms or pieces. Splitting them into two fields
/// lets a user submit a number with the wrong unit still selected.
///
/// Parses through [QtyParser], so no `double` touches a quantity (Law L2) and a value finer than the
/// selected unit can express is reported rather than rounded away.
///
/// Like `AmountField`, it never rewrites what is being typed: [onChanged] receives null while the
/// input is incomplete, and the text is left alone.
class QtyField extends StatefulWidget {
  /// Creates a quantity field.
  const QtyField({
    required this.category,
    required this.units,
    required this.selectedUnit,
    required this.onChanged,
    required this.onUnitChanged,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.unitLabel,
    super.key,
  });

  /// The category being measured. Constrains which units are offered (Law L8).
  final UnitCategory category;

  /// The units available in [category].
  final List<Unit> units;

  /// The unit currently chosen.
  final Unit? selectedUnit;

  /// Called with the parsed quantity, or null while the input is not yet a valid one.
  final ValueChanged<Qty?> onChanged;

  /// Called when the user picks a different unit.
  final ValueChanged<Unit> onUnitChanged;

  /// A starting quantity.
  final Qty? initialValue;

  /// The field's label.
  final String? label;

  /// Placeholder text.
  final String? hint;

  /// An error from the caller — a business rule, not a parse failure.
  final String? errorText;

  /// The unit picker's label.
  final String? unitLabel;

  @override
  State<QtyField> createState() => _QtyFieldState();
}

class _QtyFieldState extends State<QtyField> {
  static const QtyParser _parser = QtyParser();

  late final TextEditingController _controller = TextEditingController(
    text: _initialText(),
  );
  ParseFailure? _failure;

  String _initialText() {
    final initial = widget.initialValue;
    final unit = widget.selectedUnit;
    if (initial == null || initial.isZero || unit == null) return '';
    return _parser.format(initial, factorToBaseMilli: unit.factorToBaseMilli);
  }

  /// Re-derives the quantity from [raw].
  ///
  /// [unit] overrides `widget.selectedUnit`, and the unit picker must supply it. The parent has not
  /// rebuilt yet when the picker fires, so `widget.selectedUnit` still holds the *previous* unit —
  /// re-parsing against it stored `10 g` for a field displaying `10 kg`.
  void _handleChanged(String raw, {Unit? unit}) {
    unit ??= widget.selectedUnit;
    if (unit == null || raw.trim().isEmpty) {
      setState(() => _failure = null);
      widget.onChanged(null);
      return;
    }
    final result = _parser.parse(
      raw,
      category: widget.category,
      factorToBaseMilli: unit.factorToBaseMilli,
    );
    setState(() => _failure = result.failureOrNull);
    widget.onChanged(result.valueOrNull);
  }

  /// The parse failures worth showing mid-typing.
  ///
  /// A trailing decimal point is [ParseFailure.malformed] and is also what everyone types on the way
  /// to entering a fraction, so it stays silent — only failures that cannot become valid by typing
  /// more are surfaced. `tooManyDecimalDigits` is one of those and matters most: it is the case the
  /// old `double` path resolved by silently rounding.
  String? _parseMessage(BuildContext context) {
    final failure = _failure;
    if (failure == null) return null;
    final strings = AlayaStrings.of(context);
    return switch (failure) {
      ParseFailure.invalidCharacter => strings.errorQuantityInvalidCharacter,
      ParseFailure.negativeNotAllowed =>
        strings.errorQuantityNegativeNotAllowed,
      ParseFailure.tooManyDecimalDigits => strings.errorQuantityTooPrecise,
      ParseFailure.tooLarge => strings.errorQuantityTooLarge,
      ParseFailure.empty || ParseFailure.malformed => null,
    };
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 3,
        child: TextField(
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          style: AlayaTypography.quantity,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            LengthLimitingTextInputFormatter(12),
          ],
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            errorText: widget.errorText ?? _parseMessage(context),
          ),
          onChanged: _handleChanged,
        ),
      ),
      const SizedBox(width: AlayaSpacing.xs),
      Expanded(
        flex: 2,
        child: UnitPicker(
          category: widget.category,
          units: widget.units,
          selected: widget.selectedUnit,
          label: widget.unitLabel,
          onChanged: (unit) {
            widget.onUnitChanged(unit);
            // Re-derive with the new factor: the typed number means something different now,
            // and it may no longer be expressible — 0.5 is half a piece but not half a
            // milligram. The unit is passed explicitly because `widget.selectedUnit` is still the
            // old one until the parent rebuilds.
            _handleChanged(_controller.text, unit: unit);
          },
        ),
      ),
    ],
  );
}
```

### `lib/shared/widgets/qty_text.dart`

```dart
import 'package:flutter/widgets.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/qty_formatter.dart';

/// Renders a [Qty] through [QtyFormatter].
///
/// **Never `Qty.toString()`.** That is a debug representation — it prints milli-base units and the
/// category name, which would put `2000000 milli weight` in front of a user instead of `2 kg`. The
/// formatter is the only path to a displayable quantity.
class QtyText extends StatelessWidget {
  /// Creates a quantity.
  const QtyText(
    this.quantity, {
    this.style = UnitStyle.mixed,
    this.muted = false,
    this.textStyle,
    this.textAlign,
    super.key,
  });

  /// The quantity.
  final Qty quantity;

  /// Which unit presentation to use — [UnitStyle.mixed] decomposes `4 kg 450 g`.
  final UnitStyle style;

  /// Renders in the muted colour, for a depleted batch or a disabled row.
  final bool muted;

  /// Overrides the default [AlayaTypography.quantity].
  final TextStyle? textStyle;

  /// How to align the text.
  final TextAlign? textAlign;

  static const QtyFormatter _formatter = QtyFormatter();

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Text(
      _formatter.format(quantity, style: style),
      style: (textStyle ?? AlayaTypography.quantity).copyWith(
        // Not `forAmount`: a quantity has no financial direction, so a negative one is a correction
        // rather than an expense and colouring it red would assert something false.
        color: muted ? semantic.muted : null,
      ),
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
    );
  }
}
```

### `lib/shared/widgets/scroll_safe_center.dart`

```dart
import 'package:flutter/material.dart';

/// Centres [child] in the available space, and scrolls instead of overflowing when there is not
/// enough of it (ARCH_3 §8.3).
///
/// The shape the full-height state widgets share, in one place. A bare `Center` hands its child
/// loose constraints and then lets it exceed them, which is why a state widget that looks right on a
/// phone in portrait paints an overflow stripe in a short list area, in landscape, or at a large
/// accessibility text scale. The `minHeight` is what keeps the content vertically centred when the
/// space *is* sufficient, so the common case is indistinguishable from a plain `Center`.
///
/// Falls back to a bare `Center` when the incoming height is unbounded, because a vertical
/// `SingleChildScrollView` given infinite height asserts rather than degrading.
class ScrollSafeCenter extends StatelessWidget {
  /// Centres and, when necessary, scrolls [child].
  const ScrollSafeCenter({
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// The content to centre.
  final Widget child;

  /// Padding around [child], inside the scrollable area so it scrolls with the content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final content = Padding(
        padding: padding,
        child: Center(child: child),
      );
      if (!constraints.hasBoundedHeight) return content;
      return SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: content,
        ),
      );
    },
  );
}
```

### `lib/shared/widgets/section_header.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// A header separating sections inside a scrolling screen.
///
/// Upper-cases its label. The transformation lives here rather than in the ARB, because the ARB holds
/// the sentence a translator writes and casing is presentation — a locale where upper case is wrong,
/// or a screen reader that spells out capitals, both need the original string intact.
class SectionHeader extends StatelessWidget {
  /// Creates a header.
  const SectionHeader({
    required this.label,
    this.trailing,
    this.padding = const EdgeInsets.only(
      left: AlayaSpacing.screenEdge,
      right: AlayaSpacing.screenEdge,
      top: AlayaSpacing.xl,
      bottom: AlayaSpacing.xs,
    ),
    super.key,
  });

  /// The label, already localised.
  final String label;

  /// An optional action on the right — "See all", a count, a filter.
  final Widget? trailing;

  /// Surrounding padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AlayaTypography.sectionHeader.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              // The original casing is what assistive technology reads.
              semanticsLabel: label,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
```

### `lib/shared/widgets/shake_on_error.dart`

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';

/// Shakes its child horizontally when [trigger] changes.
///
/// Used on the PIN pad and on a rejected form. A shake communicates rejection without moving focus or
/// stealing the keyboard, which a snack bar or dialog both do — and on a PIN pad, keeping focus is the
/// difference between retrying immediately and re-tapping the field.
///
/// Keyed on an incrementing [trigger] rather than a bool, so two consecutive failures shake twice. A
/// bool that is already `true` produces no change and therefore no second shake, which reads as the
/// app having ignored the attempt.
///
/// Respects `MediaQuery.disableAnimations`: when a user has asked the platform to reduce motion, the
/// shake is skipped entirely rather than shortened.
class ShakeOnError extends StatefulWidget {
  /// Creates a shake wrapper.
  const ShakeOnError({
    required this.trigger,
    required this.child,
    this.distance = 10,
    super.key,
  });

  /// Increment this to shake.
  final int trigger;

  /// The widget to shake.
  final Widget child;

  /// Peak horizontal displacement in logical pixels.
  final double distance;

  @override
  State<ShakeOnError> createState() => _ShakeOnErrorState();
}

class _ShakeOnErrorState extends State<ShakeOnError>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    // Four legs plus a settle, each one shakeLeg long.
    duration: AlayaDurations.shakeLeg * 5,
    vsync: this,
  );

  @override
  void didUpdateWidget(ShakeOnError oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger > 0) {
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    builder: (context, child) {
      // A decaying sine: four crossings, each smaller than the last, settling at zero.
      final t = _controller.value;
      final decay = 1 - t;
      final offset = widget.distance * decay * math.sin(t * 4 * math.pi);
      return Transform.translate(offset: Offset(offset, 0), child: child);
    },
    child: widget.child,
  );
}
```

### `lib/shared/widgets/status_chip.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// What a [StatusChip] is reporting.
///
/// A tone rather than a colour: the chip is the single place any of these seven states is rendered,
/// so `needsReview`, `unallocated`, `detached`, `overdue`, `expiring`, `low` and `approximate` all
/// look the same wherever they appear, and changing what "warning" looks like is one edit.
enum StatusTone {
  /// Factual, no judgement — `detached`, `approximate`, a count.
  neutral,

  /// Worth knowing — `needsReview`, `unallocated`.
  info,

  /// Needs attention soon — `expiring`, `low`, due within the window.
  warning,

  /// Wrong or past due — `overdue`, `expired`.
  danger,

  /// Completed — `paid`, `restored`.
  success,
}

/// A small labelled status pill.
///
/// **The label is required, and that is Law U17 rather than a style choice.** Colour alone excludes
/// roughly eight percent of men, and survives neither a greyscale screenshot nor a screen reader.
/// The tone tints the chip; the word carries the meaning.
class StatusChip extends StatelessWidget {
  /// Creates a chip reading [label] in [tone].
  const StatusChip({
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
    this.trailing,
    this.onTap,
    super.key,
  });

  /// The status, already localised. Two or three words at most.
  final String label;

  /// Which semantic colour to tint with.
  final StatusTone tone;

  /// An optional leading glyph. Never a substitute for [label].
  final IconData? icon;

  /// A rendered value after the label — an `AmountText` or a `QtyText`.
  ///
  /// A chip that must show money cannot take it as a string: `Money` is minor units, and formatting
  /// it at the call site is how `2000.00` reaches the screen as `200000` (Law U7). The value is
  /// rendered by its own widget and handed in.
  final Widget? trailing;

  /// Makes the chip an action — "3 need details" opening a filtered list.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final foreground = switch (tone) {
      StatusTone.neutral => semantic.muted,
      StatusTone.info => semantic.transfer,
      StatusTone.warning => semantic.warning,
      StatusTone.danger => semantic.danger,
      StatusTone.success => semantic.success,
    };

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: AlayaIconSize.sm, color: foreground),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            trailing!,
          ],
        ],
      ),
    );

    // The tint is the tone at low alpha rather than a second palette entry, so a chip cannot drift
    // out of step with the colour it is reporting.
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: BorderSide(color: foreground.withValues(alpha: 0.28)),
    );
    final background = foreground.withValues(alpha: 0.12);

    if (onTap == null) {
      return Semantics(
        label: label,
        child: Material(
          color: background,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: body,
        ),
      );
    }

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}
```

### `lib/shared/widgets/tag_chip.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Renders one [Tag].
///
/// A tag may carry its own `colorArgb`, which is user data rather than a palette value — so it is
/// used for a small leading dot and never for the label or the fill. A user-chosen colour behind text
/// would break contrast unpredictably, and there is no way to guarantee a readable foreground for an
/// arbitrary background.
///
/// **A tappable chip reaches the 48px tap-target floor; a display-only one stays compact.** The chip
/// is the densest interactive element in the app and it is how tags get selected, so the hit area
/// cannot be the 21px the label alone implies. The coloured pill is also the ink surface rather than
/// sitting on top of one, because a Material paints its splashes beneath its child and an opaque fill
/// in between makes a press produce no feedback at all.
class TagChip extends StatelessWidget {
  /// Creates a chip for [tag].
  const TagChip({
    required this.tag,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.removeLabel,
    super.key,
  });

  /// The tag.
  final Tag tag;

  /// Whether the tag is currently applied.
  final bool selected;

  /// Tap handler, usually a toggle.
  final VoidCallback? onTap;

  /// Remove handler. When set, a trailing dismiss affordance appears.
  final VoidCallback? onRemove;

  /// Accessibility label for the dismiss affordance, already localised.
  ///
  /// Passed in rather than read from the ARB here, so this widget needs no `Localizations` ancestor
  /// and its goldens stay independent of `flutter gen-l10n` having run.
  final String? removeLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final dotColor = tag.colorArgb == null ? null : Color(tag.colorArgb!);
    final background = selected
        ? theme.colorScheme.primary
        : semantic.surfaceSunken;
    final foreground = selected
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSurfaceVariant;
    final shape = RoundedRectangleBorder(
      borderRadius: AlayaRadii.borderXs,
      side: selected ? BorderSide.none : BorderSide(color: theme.dividerColor),
    );

    final body = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.xs,
        vertical: AlayaSpacing.xxs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            _Dot(color: dotColor),
            const SizedBox(width: AlayaSpacing.xxs),
          ],
          Flexible(
            child: Text(
              tag.name,
              style: AlayaTypography.overline.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: AlayaSpacing.xxs),
            Semantics(
              button: true,
              label: removeLabel,
              child: InkResponse(
                onTap: onRemove,
                radius: AlayaSpacing.md,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(AlayaSpacing.xxs),
                  child: Icon(
                    Icons.close,
                    size: AlayaIconSize.sm,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: body,
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: background,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Center(widthFactor: 1, child: body),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: AlayaSpacing.xs,
    height: AlayaSpacing.xs,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
```

### `lib/shared/widgets/tag_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Selects zero or more tags, filtered to those valid for a [scope].
///
/// A wrap of chips rather than a dropdown or a dialog. Tags are chosen several at a time and the
/// current selection needs to stay visible while choosing — a dropdown hides it at exactly the moment
/// the user is deciding whether they have enough.
///
/// Filters by [scope] because `Tag.allowedScopes` exists: a tag scoped to items should not be offerable
/// on a transaction, and letting it through would put a link row in a table whose scope forbids it.
class TagPicker extends StatelessWidget {
  /// Creates a tag picker.
  const TagPicker({
    required this.available,
    required this.selectedIds,
    required this.scope,
    required this.onToggle,
    this.label,
    this.emptyLabel,
    super.key,
  });

  /// Every tag the user has.
  final List<Tag> available;

  /// The ids currently applied.
  final Set<String> selectedIds;

  /// The scope being tagged.
  final TagScope scope;

  /// Called with a tag's id when the user toggles it.
  final ValueChanged<String> onToggle;

  /// The control's label.
  final String? label;

  /// Shown when no tag is valid for [scope].
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eligible =
        available
            .where((tag) => !tag.isDeleted && tag.allowedScopes.contains(scope))
            .toList()
          ..sort((a, b) {
            // Selected first, then the user's own order. Keeping selection at the top means a long tag
            // list never hides what is already applied.
            final aSelected = selectedIds.contains(a.id);
            final bSelected = selectedIds.contains(b.id);
            if (aSelected != bSelected) return aSelected ? -1 : 1;
            return a.sortOrder.compareTo(b.sortOrder);
          });

    if (eligible.isEmpty && emptyLabel != null) {
      return Text(
        emptyLabel!,
        style: AlayaTypography.caption.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: AlayaTypography.label.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xs),
        ],
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final tag in eligible)
              TagChip(
                tag: tag,
                selected: selectedIds.contains(tag.id),
                onTap: () => onToggle(tag.id),
              ),
          ],
        ),
      ],
    );
  }
}
```

### `lib/shared/widgets/unit_picker.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Picks a unit from within one category.
///
/// **Only units in [category] are offered, and that is a correctness constraint rather than a
/// convenience.** A `Qty` is a bare integer plus a category, so offering litres for a weight would
/// store a number that is reinterpreted on read — Law L8's cross-category prohibition, broken
/// silently rather than loudly.
class UnitPicker extends StatelessWidget {
  /// Creates a unit picker.
  const UnitPicker({
    required this.category,
    required this.units,
    required this.selected,
    required this.onChanged,
    this.label,
    this.enabled = true,
    super.key,
  });

  /// The category whose units may be chosen.
  final UnitCategory category;

  /// The available units. Any not in [category] are filtered out rather than trusted.
  final List<Unit> units;

  /// The current selection.
  final Unit? selected;

  /// Called with the newly chosen unit.
  final ValueChanged<Unit> onChanged;

  /// The field's label.
  final String? label;

  /// Whether the picker accepts input.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Filtered here rather than assumed of the caller: a picker that trusts its input to already be
    // category-correct is one bad call site away from breaking L8.
    final eligible = units.where((unit) => unit.category == category).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    // Resolved to the instance in `eligible` that shares the selected code, not passed through. A
    // dropdown matches its value against its items by `==`, and `Unit`'s equality covers every
    // field — so a caller holding an instance read before the row was edited would match nothing
    // and the field would render blank with no error.
    Unit? current;
    for (final unit in eligible) {
      if (unit.code == selected?.code) {
        current = unit;
        break;
      }
    }

    return DropdownButtonFormField<Unit>(
      // Keyed on the selection so a change from the caller rebuilds the form field rather than
      // being absorbed: a FormField keeps its own copy of the value it was created with.
      key: ValueKey(current?.code),
      initialValue: current,
      // Without this the button lays its items out at their natural width against unbounded
      // constraints and then overflows the narrow column a QtyField gives it.
      isExpanded: true,
      decoration: InputDecoration(labelText: label, enabled: enabled),
      items: [
        for (final unit in eligible)
          DropdownMenuItem(
            value: unit,
            child: Text(
              unit.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: enabled
          ? (unit) => unit == null ? null : onChanged(unit)
          : null,
    );
  }
}
```
