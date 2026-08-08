import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money_formatter.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// One transaction in the ledger (ARCH_5 §3 archetype C).
///
/// **At most three lines**: a title with the amount, one line of metadata, and chips only when there
/// is something abnormal to say. A ledger row that grows to five lines stops being scannable, and
/// scanning is the only thing a ledger list is for.
///
/// The amount is right-aligned and tabular; everything else is left. That is what lets the eye run
/// down the decimal point instead of hunting for each figure.
class TransactionRow extends StatelessWidget {
  /// Creates a row for [transaction].
  const TransactionRow({
    required this.transaction,
    required this.decimalDigits,
    required this.onTap,
    this.payee,
    this.fromAccount,
    this.toAccount,
    super.key,
  });

  /// The transaction to render.
  final Transaction transaction;

  /// The currency's minor-unit precision, from the `currencies` row. Never hardcoded.
  final int decimalDigits;

  /// Opens the detail screen.
  final VoidCallback onTap;

  /// The counterparty, when the transaction names one.
  final Payee? payee;

  /// The source account, when there is one.
  final Account? fromAccount;

  /// The destination account, when there is one.
  final Account? toAccount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final strings = AlayaStrings.of(context);

    final title = payee?.name ?? _subtypeLabel(strings, transaction.subtype);
    final metadata = _metadata(strings);
    // Above roughly 1.5x, the amount and the title cannot share a line at 320dp. The amount is not
    // flexible, so it takes its full natural width and starves the title beside it — and
    // `AmountText` clips rather than ellipsises, so constraining it would silently show a wrong
    // number. Stacking keeps the figure whole (Law U15).
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final amount = AmountText(
      transaction.signedAmount,
      kind: transaction.kind,
      decimalDigits: decimalDigits,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
    );

    // **ARCH_5 §6: a ledger row reads as one thing, not five fragments.**
    //
    // Without this, TalkBack announces the icon, the payee, the metadata line, the amount and the date as five
    // separate stops — so moving through a month of transactions takes five swipes per row and the amount is
    // read with no idea which transaction it belongs to. `container: true` makes the row a single node;
    // `excludeSemantics` stops the children announcing themselves again underneath it.
    //
    // The label is assembled in the reading order a person would say it: what it was, how much, and when.
    // `AmountText` and `DateText` own their own formatting, so this reuses their strings rather than building a
    // second, divergent way of saying the same figure.
    return Semantics(
      container: true,
      button: onTap != null,
      excludeSemantics: true,
      label: _semanticLabel(context, title, metadata),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AlayaSpacing.minTapTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
                vertical: AlayaSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _iconFor(transaction.kind),
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                  const SizedBox(width: AlayaSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AlayaTypography.cardTitle.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (metadata != null) ...[
                          const SizedBox(height: AlayaSpacing.xxs),
                          Text(
                            metadata,
                            style: AlayaTypography.caption.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        if (transaction.needsReview) ...[
                          const SizedBox(height: AlayaSpacing.xxs),
                          StatusChip(
                            label: strings.statusNeedsReview,
                            tone: StatusTone.info,
                          ),
                        ],
                        if (stacked) ...[
                          const SizedBox(height: AlayaSpacing.xs),
                          amount,
                        ],
                      ],
                    ),
                  ),
                  if (!stacked) ...[
                    const SizedBox(width: AlayaSpacing.sm),
                    amount,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _metadata(AlayaStrings strings) {
    final parts = <String>[];
    if (transaction.isTransfer) {
      final from = fromAccount?.name;
      final to = toAccount?.name;
      if (from != null && to != null) parts.add('$from → $to');
    } else {
      final account = (fromAccount ?? toAccount)?.name;
      if (account != null) parts.add(account);
    }
    if (payee != null) parts.add(_subtypeLabel(strings, transaction.subtype));
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static IconData _iconFor(TransactionKind kind) => switch (kind) {
    TransactionKind.deposit => Icons.south_west,
    TransactionKind.withdrawal => Icons.north_east,
    TransactionKind.transfer => Icons.swap_horiz,
    TransactionKind.adjustmentIncrease => Icons.tune,
    TransactionKind.adjustmentDecrease => Icons.tune,
  };

  /// The localised name of a subtype. Public so the filter sheet reads from one mapping.
  static String subtypeLabel(
    AlayaStrings strings,
    TransactionSubtype subtype,
  ) => _subtypeLabel(strings, subtype);

  static String _subtypeLabel(
    AlayaStrings strings,
    TransactionSubtype subtype,
  ) => switch (subtype) {
    TransactionSubtype.grocery => strings.subtypeGrocery,
    TransactionSubtype.household => strings.subtypeHousehold,
    TransactionSubtype.electronics => strings.subtypeElectronics,
    TransactionSubtype.bill => strings.subtypeBill,
    TransactionSubtype.transferSelf => strings.subtypeTransferSelf,
    TransactionSubtype.transferOut => strings.subtypeTransferOut,
    TransactionSubtype.salaryIn => strings.subtypeSalaryIn,
    TransactionSubtype.otherIn => strings.subtypeOtherIn,
    TransactionSubtype.otherOut => strings.subtypeOtherOut,
  };

  /// The localised name of a kind. Public so the filter sheet reads from one mapping.
  static String kindLabel(AlayaStrings strings, TransactionKind kind) =>
      switch (kind) {
        TransactionKind.deposit => strings.kindDeposit,
        TransactionKind.withdrawal => strings.kindWithdrawal,
        TransactionKind.transfer => strings.kindTransfer,
        TransactionKind.adjustmentIncrease => strings.kindAdjustmentIncrease,
        TransactionKind.adjustmentDecrease => strings.kindAdjustmentDecrease,
      };

  /// The row as one sentence, for a screen reader.
  ///
  /// Assembled rather than concatenated from the visible widgets, because the visible row abbreviates for a
  /// glance and a listener has no column headings to lean on.
  ///
  /// The date is deliberately absent: the ledger groups rows under a date header, so speaking it on every row
  /// would repeat the same words twenty times down a day.
  String _semanticLabel(BuildContext context, String title, String? metadata) {
    final strings = AlayaStrings.of(context);
    // **`MoneyFormatter` directly, because `AmountText` exposes no label helper.** I reached for
    // `AmountText.semanticsLabel` first; it does not exist. Formatting through the same `MoneyFormatter` the
    // widget uses means the spoken figure and the drawn one cannot diverge, which a second hand-rolled format
    // string would eventually allow.
    const formatter = MoneyFormatter();
    // `signedAmount`, not `originalAmount`: the entity applies the sign from `kind`, and a spoken figure with no
    // sign cannot distinguish money in from money out — which is the one thing §6's "colour is never alone" rule
    // is protecting, carried over to a listener who has no colour at all.
    final amount = formatter.format(
      transaction.signedAmount,
      decimalDigits: decimalDigits,
      symbol: transaction.signedAmount.currencyCode,
      showPlusSign: transaction.signedAmount.isPositive,
    );
    return metadata == null || metadata.isEmpty
        ? strings.ledgerRowSemantics(title, amount)
        : strings.ledgerRowSemanticsDetailed(title, amount, metadata);
  }
}
