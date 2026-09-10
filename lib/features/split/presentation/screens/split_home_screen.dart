import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/name_placeholder_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/settle_up_sheet.dart';
import 'package:alaya/features/split/presentation/sheets/split_share_sheet.dart';
import 'package:alaya/features/split/presentation/widgets/quick_split_card.dart';
import 'package:alaya/features/split/presentation/widgets/split_groups_list.dart';
import 'package:alaya/features/split/presentation/widgets/split_history_list.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The whole split module, on one destination (ARCH_5 §3 archetype C).
///
/// ## Three tabs instead of seven routes
///
/// `/split/groups`, `/split/groups/:groupId` and `/split/groups/:groupId/settle` are gone. The groups
/// list is a tab; a group's balances and its settle-up plan are bottom sheets. **None of the three was an
/// editor** — each read something and offered actions — so each route bought a back arrow, an app bar
/// competing for a 320dp title, and somewhere for a user to end up without knowing how.
///
/// What remains a route is what genuinely earns one: the bill editor, and the group editor. Both are
/// forms with a discard guard, which is what `AlayaFormScaffold` and archetype B exist for.
///
/// ## Balances, History, Groups — in that order
///
/// **Balances first because it answers the question people open the app with**, and the quick splitter
/// sits at the top of it so dividing a bill is still zero taps from arriving. **History second** because
/// it is the only surface that remembers a split settled the same evening — a balance list is not a
/// record of what happened. **Groups last** because a group is a convenience for the other two, not a
/// thing anybody comes here to look at.
///
/// ## No `Scaffold`, no app bar, no FAB
///
/// `Routes.split` sits inside the drawer shell, which owns all three — and the first version of this
/// screen wrapped itself in a second `Scaffold`, stacking a bar with a back arrow under the real one on a
/// destination nobody navigates *into*. That is also why "Create a split" is a button in content: a FAB
/// belongs to the shell, and one hovering over the Groups tab would be the wrong action in the wrong
/// place.
///
/// **Every row that pairs text with an amount is a `Wrap`, not a `Row`.** An `AmountText` cannot shrink
/// below its own text, so `Row(Expanded(name), amount)` overflows the moment the figure is long and the
/// scaler is doubled — ₹1,23,456.78 at 2.0 overran 320dp by 215 pixels.
class SplitHomeScreen extends ConsumerWidget {
  /// Creates the screen.
  const SplitHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // **A `TabBar` in the body rather than in an app bar**, because the app bar belongs to
          // `_ShellScaffold` and putting tabs there would show them on all eleven destinations.
          TabBar(
            tabs: [
              Tab(text: strings.splitTabBalances),
              Tab(text: strings.splitTabHistory),
              Tab(text: strings.splitTabGroups),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                const _BalancesTab(),
                // Every group and none — a split filed under no group is most of them, since the bill
                // screen makes a group optional.
                const SplitHistoryList(),
                const SplitGroupsList(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancesTab extends ConsumerWidget {
  const _BalancesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final balances = ref.watch(splitBalancesProvider);
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return balances.when(
      // **The splitter still shows while balances load**, because it needs none of them. Hiding a
      // working calculator behind somebody else's query is the kind of coupling a skeleton makes easy and
      // nobody notices.
      loading: () => ListView(
        padding: const EdgeInsets.fromLTRB(
          AlayaSpacing.screenEdge,
          AlayaSpacing.md,
          AlayaSpacing.screenEdge,
          AlayaSpacing.xxxl,
        ),
        children: [
          const QuickSplitCard(),
          const SizedBox(height: AlayaSpacing.lg),
          AlayaListSkeleton(label: strings.loadingLabel),
        ],
      ),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(splitBalancesProvider),
      ),
      data: (rows) => _BalancesBody(rows: rows, hasSelf: self != null),
    );
  }
}

class _BalancesBody extends ConsumerWidget {
  const _BalancesBody({required this.rows, required this.hasSelf});

  final List<SplitBalance> rows;

  /// Whether the app knows which payee the user is.
  final bool hasSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final totals = ref.watch(splitTotalsProvider).valueOrNull ?? const {};
    final ageing = ref.watch(splitAgeingProvider).valueOrNull ?? const [];
    final aged = {for (final debt in ageing) debt.balance.payeeId: debt};

    final owed = [
      for (final row in rows)
        if (row.theyOweMe) row,
    ];
    final owing = [
      for (final row in rows)
        if (row.iOweThem) row,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.md,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xxxl,
      ),
      children: [
        // **The question moved to onboarding.** `SplitSetupCard` used to sit here asking who the user is,
        // because nothing in this module works until `split.selfPayeeId` is set and the screens that
        // noticed pointed at a settings branch with an empty list of candidates. Step one of the first-run
        // flow asks it now, before Split is ever opened — so the common path never reaches the empty state
        // below, and this screen went back to being about balances.
        const QuickSplitCard(),

        const SizedBox(height: AlayaSpacing.sm),
        // Two buttons, not three: Groups is a tab now. A `Wrap` rather than `Expanded`s because at a
        // doubled text scale each label needs more than half the width, and a button's own row cannot
        // shrink its label.
        Wrap(
          spacing: AlayaSpacing.sm,
          runSpacing: AlayaSpacing.xs,
          children: [
            OutlinedButton.icon(
              onPressed: () => context.push(Routes.splitNew),
              icon: const Icon(
                Icons.call_split_outlined,
                size: AlayaIconSize.md,
              ),
              label: Text(strings.splitCreateSplit),
            ),
            OutlinedButton.icon(
              onPressed: rows.isEmpty
                  ? null
                  : () => SplitShareSheet.show(context),
              icon: const Icon(Icons.ios_share, size: AlayaIconSize.md),
              label: Text(strings.actionShare),
            ),
          ],
        ),

        if (rows.isEmpty) ...[
          const SizedBox(height: AlayaSpacing.xl),
          // **Two empty states, because they mean opposite things.** "Nothing outstanding" is success;
          // "the app does not know who you are" is a setup step that silently makes every balance
          // unanswerable — and the setup card above is already asking, so this one only reassures.
          if (hasSelf)
            EmptyState(
              title: strings.splitAllSettledTitle,
              body: strings.splitAllSettledBody,
              icon: Icons.check_circle_outline,
            )
          else
            EmptyState(
              title: strings.splitNoSelfTitle,
              body: strings.splitSelfPayeeUnset,
              icon: Icons.person_outline,
              // **Reachable again, and only for the person who skipped.** Onboarding's name step is
              // optional — archetype B makes the whole flow skippable — so somebody who declined needs
              // somewhere to answer later. That is what a settings branch is for, and it is one tap rather
              // than the four-screen chain this used to be.
              actionLabel: strings.settingsSplit,
              onAction: () => context.push(Routes.settingsSplit),
            ),
        ] else ...[
          for (final entry in totals.entries)
            Padding(
              padding: const EdgeInsets.only(top: AlayaSpacing.md),
              child: AlayaCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TotalRow(
                      label: strings.splitOwedToYou,
                      amount: entry.value.owedToMe,
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    _TotalRow(
                      label: strings.splitYouOwe,
                      amount: entry.value.iOwe,
                    ),
                  ],
                ),
              ),
            ),

          if (owed.isNotEmpty) ...[
            SectionHeader(
              label: strings.splitOwedToYou,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xs,
              ),
            ),
            for (final row in owed)
              _BalanceRow(balance: row, aged: aged[row.payeeId]),
          ],

          if (owing.isNotEmpty) ...[
            SectionHeader(
              label: strings.splitYouOwe,
              padding: const EdgeInsets.only(
                top: AlayaSpacing.xl,
                bottom: AlayaSpacing.xs,
              ),
            ),
            for (final row in owing)
              _BalanceRow(balance: row, aged: aged[row.payeeId]),
          ],

          // **The "tap a balance to settle up" hint is gone.** It was instructions for an affordance that
          // should not have needed any, and it sat where nobody scrolled to. Each row now carries its own
          // button, which is the thing the sentence was compensating for.
        ],
      ],
    );
  }
}

/// One side of the totals card: a label and a figure.
///
/// **Stacked rather than side by side.** Two totals in a `Row` of `Expanded`s each get half of 320dp, and
/// half of 320 does not hold "Owed to you" beside ₹1,23,456.78 at a doubled scale.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.amount});

  final String label;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AlayaSpacing.sm,
      runSpacing: AlayaSpacing.xxs,
      children: [
        Text(
          label,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        // Through `AmountText`, and without a colour of its own: that widget has no `tone` parameter and
        // colours from `kind` deliberately. The label beside it already says which figure this is.
        AmountText(amount, showSign: false),
      ],
    );
  }
}

class _BalanceRow extends ConsumerWidget {
  const _BalanceRow({required this.balance, this.aged});

  final SplitBalance balance;

  /// Set when this debt is old enough to mention.
  final AgeingDebt? aged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final payee = ref.watch(splitPayeeProvider(balance.payeeId));
    final name = payee?.name ?? strings.splitUnknownPerson;
    final days = aged?.ageInDays;

    // **A row this app created, not somebody the user chose.** Saving a split writes a
    // `PayeeKind.splitPlaceholder` for anybody anonymous so the debt can exist at all; this is where
    // that gets fixed, because "Person 4 owes you ₹1,250" is a question asked at exactly the moment the
    // answer is known.
    //
    // Read from `kind` rather than by matching the name — a real contact called "Person 5" is not a
    // placeholder, and a placeholder renamed to "Ravi" stops being one because the *kind* changed.
    final provisional =
        payee != null && SplitPlaceholderNames.isPlaceholder(payee);

    void settle() => SettleUpSheet.show(
      context,
      payeeId: balance.payeeId,
      payeeName: name,
      outstanding: balance.outstanding,
      theyOweMe: balance.theyOweMe,
    );

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // The whole card stays tappable — for anybody who has learnt it, it is the larger target. But it is
      // no longer the *only* way in: see the button below.
      onTap: settle,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: provisional
                    // Muted and italic, exactly as the bill screen renders an unnamed slot, so the two
                    // places a placeholder appears look like the same thing.
                    ? AlayaTypography.body.copyWith(
                        color: semantic.muted,
                        fontStyle: FontStyle.italic,
                      )
                    : AlayaTypography.body,
              ),
              // **The action, spelled out, because "the row is tappable" was the only affordance and
              // nobody found it.** A card with no button, no icon and no chevron reads as a list item, and
              // the one sentence that said otherwise sat centred and muted *below* every row — off screen
              // the moment somebody had four balances. Recording a repayment is the reason this module
              // exists after the arithmetic, and it was the least visible thing on the screen.
              //
              // Its own button rather than a trailing chevron: a chevron says "there is more to read",
              // and this is a write.
              TextButton.icon(
                onPressed: settle,
                icon: const Icon(
                  Icons.handshake_outlined,
                  size: AlayaIconSize.sm,
                ),
                label: Text(
                  // Says which direction the money goes, because "Settle up" does not. Somebody looking at
                  // "You owe Ravi ₹1,250" wants to record that they *paid* him.
                  balance.theyOweMe
                      ? strings.splitRecordTheyPaid
                      : strings.splitRecordYouPaid,
                ),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (provisional)
                // Its own button, so it does not fight the card's tap. Settling with somebody and naming
                // them are different intents, and a long-press would hide one of them.
                //
                // **`NamePlaceholderSheet`, not `PayeeSheet`.** A name field can only say "call this row
                // Ravi", and if Ravi already exists that leaves two of him — two balances, and settling
                // one leaves the other outstanding with nothing on screen to explain it. The sheet offers
                // the people you already have first, and a name field second.
                TextButton.icon(
                  onPressed: () =>
                      NamePlaceholderSheet.show(context, placeholder: payee),
                  icon: const Icon(
                    Icons.drive_file_rename_outline,
                    size: AlayaIconSize.sm,
                  ),
                  label: Text(strings.splitNameThisPerson),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (days != null) ...[
                const SizedBox(height: AlayaSpacing.xxs),
                // The sentence no competitor writes, and it costs nothing: the balance view already
                // carries the oldest contributing expense.
                StatusChip(
                  label: strings.splitOutstandingDays(days),
                  tone: StatusTone.warning,
                ),
              ],
            ],
          ),
          // Direction is carried by which section the row sits under — "Owed to you" or "You owe" —
          // rather than by a colour `AmountText` has no parameter for.
          AmountText(balance.outstanding, showSign: false),
        ],
      ),
    );
  }
}
