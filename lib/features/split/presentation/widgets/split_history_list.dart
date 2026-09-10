import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/split_read_models.dart';
import 'package:alaya/features/split/presentation/sheets/split_expense_detail_sheet.dart';
import 'package:alaya/features/split/providers/split_history_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Every split and every settlement, newest first.
///
/// ## Why the module needed this
///
/// **A balance list is not a record of what happened.** Balances say who currently owes what, so a split
/// settled the same evening leaves nothing behind — and until now that meant no evidence it ever
/// happened. Somebody who divided a restaurant bill, was paid back in cash, and looked for it a week
/// later found an empty screen and had to trust their memory over the app.
///
/// It is also where a split with unnamed participants belongs. Those have real balances while money is
/// outstanding, but the *decision* — four ways, ₹800 of it somebody's sushi — is a fact about an evening
/// rather than about a debt, and this is the only surface that keeps it.
///
/// **It cost one provider.** `watchActivity` already took a nullable `groupId` and nothing ever passed
/// null, so the capability existed and had no caller. `v_split_activity` interleaves both tables as a
/// `UNION ALL` rather than an events table, because two subsystems writing into a shared feed is a
/// synchronisation-bug factory and a view has no synchronisation code to get wrong (anomaly A37).
class SplitHistoryList extends ConsumerWidget {
  /// Creates the list.
  ///
  /// [groupId] narrows it to one group; null shows everything, including splits filed under no group at
  /// all — which is most of them, since the bill screen makes a group optional.
  const SplitHistoryList({this.groupId, super.key});

  /// The group to restrict to, or null for everything.
  final String? groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final scope = groupId;
    final entries = scope == null
        ? ref.watch(splitHistoryProvider)
        : ref.watch(splitGroupHistoryProvider(scope));

    return entries.when(
      loading: () => AlayaListSkeleton(label: strings.loadingLabel),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: error.toString(),
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(
          scope == null
              ? splitHistoryProvider
              : splitGroupHistoryProvider(scope),
        ),
      ),
      data: (rows) {
        if (rows.isEmpty) {
          return EmptyState(
            // Names what would fill it rather than reporting a count of nothing. An empty history is the
            // normal state of a new install, not a problem to solve.
            title: strings.splitHistoryEmptyTitle,
            body: strings.splitHistoryEmptyBody,
            icon: Icons.history_outlined,
          );
        }

        final days = _groupByDay(rows);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          itemCount: days.length,
          itemBuilder: (context, index) {
            final day = days[index];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  label: day.date.fullLabel,
                  padding: EdgeInsets.only(
                    top: index == 0 ? AlayaSpacing.sm : AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                    left: AlayaSpacing.screenEdge,
                    right: AlayaSpacing.screenEdge,
                  ),
                ),
                for (final entry in day.entries) _HistoryRow(entry: entry),
              ],
            );
          },
        );
      },
    );
  }

  /// Groups [rows] into days, newest day first.
  ///
  /// The feed already arrives newest-first, so the days come out ordered by insertion and the entries
  /// within each keep the view's own ordering — no second sort, and therefore no chance of a second sort
  /// disagreeing with the first.
  static List<_Day> _groupByDay(List<SplitActivityEntry> rows) {
    final byDate = <int, List<SplitActivityEntry>>{};
    final order = <int>[];
    for (final row in rows) {
      final key = row.dateKey.value;
      if (!byDate.containsKey(key)) {
        byDate[key] = [];
        order.add(key);
      }
      byDate[key]!.add(row);
    }
    return [
      for (final key in order) _Day(date: DateKey(key), entries: byDate[key]!),
    ];
  }
}

class _Day {
  const _Day({required this.date, required this.entries});

  final DateKey date;
  final List<SplitActivityEntry> entries;
}

class _HistoryRow extends ConsumerWidget {
  const _HistoryRow({required this.entry});

  final SplitActivityEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final who =
        ref.watch(splitPayeeNameProvider(entry.payeeId)) ??
        strings.splitUnknownPerson;

    // Exhaustive over the kind, so a third activity kind fails to compile here rather than rendering the
    // wrong sentence (Law L13).
    final what = switch (entry.kind) {
      SplitActivityKind.expense => strings.splitHistoryPaidBy(who),
      SplitActivityKind.settlement => strings.splitHistorySettledBy(who),
    };
    // The label is whichever of title, occasion, place or note the view found — so a row is named by
    // whatever the user actually typed, and falls back to the sentence about the payer rather than to a
    // blank line.
    //
    // **When there is no label the sentence is the title and there is no subtitle**, because the first
    // version used it as both: an unlabelled row rendered "Ravi paid" at 15pt with "Ravi paid" in grey
    // underneath it. Two lines saying one thing reads as a rendering fault, and a caption only earns its
    // place when it adds something the line above does not already say.
    final label = entry.label?.trim();
    final named = label != null && label.isNotEmpty;
    final title = named ? label : what;

    return AlayaCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.sm,
        vertical: AlayaSpacing.xs,
      ),
      // **Only an expense opens.** A settlement is a single fact — this much moved, on this day, between
      // these two — and a sheet repeating the row it was opened from would be a tap that buys nothing. An
      // expense has shares, a payer and a method behind it, none of which fit on a row.
      onTap: entry.kind == SplitActivityKind.expense
          ? () => SplitExpenseDetailSheet.show(context, expenseId: entry.refId)
          : null,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              Icon(
                // A bill and a repayment are opposite events and the glyph says which without a word.
                switch (entry.kind) {
                  SplitActivityKind.expense => Icons.call_split_outlined,
                  SplitActivityKind.settlement => Icons.handshake_outlined,
                },
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              SizedBox(
                width: 150,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AlayaTypography.body,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (named)
                      Text(
                        what,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.muted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Unsigned, and deliberately. An expense is not necessarily an outflow from the user's
          // account — somebody else may have paid it — so a minus sign would assert something this row
          // does not know. The icon carries the direction.
          AmountText(entry.amount, showSign: false, decimalDigits: digits),
        ],
      ),
    );
  }
}
