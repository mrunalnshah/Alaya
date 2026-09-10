# F_EXPENSE

Transactions, lines, tags, payees, ledger, editor.

**40 files · 8,022 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/expense/presentation/screens/line_items_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Everything on one receipt, in one place (ARCH_5 §3 archetype D).
///
/// **A page rather than a sheet per line.** Itemising a fifteen-line grocery receipt through
/// `LineItemEditor` alone meant fifteen open-close cycles with no view of what had been entered, no
/// running total, and no way to correct line three without starting over. This keeps the list, the
/// figures and the add action on screen together; the sheet is still what edits one line, reached from
/// here. `LineItemDraft.addAnother` lets the sheet stay open across a whole receipt.
///
/// **It edits the editor's state, and writes nothing.** The lines belong to
/// `transactionEditorProvider`, which stays alive because the editor screen remains mounted beneath
/// this route — so Done simply pops, and nothing is committed until the user saves the transaction.
class LineItemsScreen extends ConsumerWidget {
  /// Shows the lines of [transactionId], or of a new transaction when null.
  const LineItemsScreen({this.transactionId, super.key});

  /// Which transaction's lines to show.
  final String? transactionId;

  Future<void> _addMany(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    int digits,
  ) async {
    final notifier = ref.read(transactionEditorProvider(transactionId).notifier);
    var another = true;
    while (another && context.mounted) {
      final draft = await LineItemEditor.show(
        context,
        currencyCode: state.currencyCode,
        decimalDigits: digits,
        defaultDestination: TransactionLineDestination.none,
      );
      if (draft == null) return;
      notifier.upsertLine(draft.line);
      another = draft.addAnother;
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    TransactionEditorState state,
    TransactionLine line,
    int digits,
  ) async {
    final draft = await LineItemEditor.show(
      context,
      currencyCode: state.currencyCode,
      decimalDigits: digits,
      defaultDestination: line.destination,
      line: line,
    );
    if (draft == null) return;
    ref.read(transactionEditorProvider(transactionId).notifier).upsertLine(draft.line);
  }

  void _remove(BuildContext context, WidgetRef ref, TransactionLine line) {
    final strings = AlayaStrings.of(context);
    ref.read(transactionEditorProvider(transactionId).notifier).removeLine(line.id);
    // No undo offered: nothing has been written, so re-adding the line is the same two taps that
    // created it, and a snack promising undo for an uncommitted edit would be lying (§5.4).
    showResultSnack(context, message: strings.lineRemoved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;

    return Scaffold(
      appBar: AppBar(title: Text(strings.lineItemsTitle)),
      body: async.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionEditorProvider(transactionId)),
        ),
        data: (state) => Column(
          children: [
            _Summary(state: state, decimalDigits: digits),
            Expanded(
              child: state.lines.isEmpty
                  ? EmptyState(
                      title: strings.emptyTitleNoLineItems,
                      body: strings.emptyBodyNoLineItems,
                      icon: Icons.receipt_long_outlined,
                      actionLabel: strings.lineItemsAdd,
                      onAction: () => _addMany(context, ref, state, digits),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                      itemCount: state.lines.length,
                      itemBuilder: (context, index) {
                        final line = state.lines[index];
                        return _LineTile(
                          line: line,
                          decimalDigits: digits,
                          onTap: () => _edit(context, ref, state, line, digits),
                          onRemove: () => _remove(context, ref, line),
                        );
                      },
                    ),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(AlayaSpacing.screenEdge),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.lines.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _addMany(context, ref, state, digits),
                      icon: const Icon(Icons.add, size: AlayaIconSize.md),
                      label: Text(strings.lineItemsAdd),
                    ),
                  const SizedBox(height: AlayaSpacing.xs),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(strings.actionDone),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.state, required this.decimalDigits});

  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final unallocated = state.unallocated;
    final allocated = state.lineTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.sm,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
      ),
      child: Wrap(
        spacing: AlayaSpacing.sm,
        runSpacing: AlayaSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            strings.lineItemsCount(state.lines.length),
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          if (allocated != null)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AlayaSpacing.xxs,
              children: [
                Text(
                  strings.lineItemsAllocated,
                  style: AlayaTypography.caption.copyWith(color: semantic.muted),
                ),
                AmountText(
                  allocated,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
              ],
            ),
          if (unallocated != null && !unallocated.isZero)
            StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
        ],
      ),
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({
    required this.line,
    required this.decimalDigits,
    required this.onTap,
    required this.onRemove,
  });

  final TransactionLine line;
  final int decimalDigits;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final amount = line.lineAmount;
    final quantity = line.quantity;

    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AlayaSpacing.minTapTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AlayaSpacing.screenEdge,
            vertical: AlayaSpacing.xs,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      line.description,
                      style: AlayaTypography.body
                          .copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                    // Quantity, amount and destination all wrap together: at a doubled text scale a
                    // Row of them would starve the description beside it (Law U21).
                    const SizedBox(height: AlayaSpacing.xxs),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xxs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (quantity != null) QtyText(quantity, muted: true),
                        if (amount != null)
                          AmountText(
                            amount,
                            size: AmountSize.small,
                            showSign: false,
                            decimalDigits: decimalDigits,
                          ),
                        if (line.destination == TransactionLineDestination.inventory)
                          StatusChip(
                            label: strings.destinationInventory,
                            icon: Icons.inventory_2_outlined,
                          ),
                        if (line.destination == TransactionLineDestination.asset)
                          StatusChip(
                            label: strings.destinationAsset,
                            icon: Icons.build_outlined,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onRemove,
                tooltip: strings.actionRemove,
                icon: Icon(
                  Icons.close,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/expense/presentation/screens/transaction_detail_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/sheets/delete_transaction_sheet.dart';
import 'package:alaya/features/expense/presentation/sheets/freeze_conversion_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// One transaction in full (ARCH_5 §3 archetype E).
///
/// Routed **outside** the drawer shell, so it gets a back arrow rather than a hamburger: `AppBar`
/// resolves `hasDrawer` before `canPop`, and a detail screen inside the shell leaves the system
/// gesture as the only way out (Law U18).
///
/// The hero answers the question the user opened the screen with. Everything below is a
/// [KeyValueRow], and a row with no value renders nothing at all — a screen of dashes reads as
/// broken data rather than as a record with optional fields.
///
/// **Delete is treated as the non-reversible tier of ARCH_5 §5.5**, which is a contract limitation
/// rather than a design choice: `TransactionRepository` exposes no `restore`, and `update()` cannot
/// stand in because it reads through `v_active_transactions` and so cannot see a deleted row. The
/// sheet therefore acts as the confirmation and captures the optional reason. When `restore` lands
/// with Phase 8B's trash, this becomes an immediate delete with an Undo snack.
class TransactionDetailScreen extends ConsumerWidget {
  /// Shows the transaction with [transactionId].
  const TransactionDetailScreen({required this.transactionId, super.key});

  /// Which transaction to show.
  final String transactionId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final reason = await DeleteTransactionSheet.show(context);
    if (reason == null) return;
    final detached = await ref
        .read(transactionActionsProvider)
        .delete(transactionId, reason: reason);
    if (!context.mounted) return;
    if (detached == null) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    showResultSnack(context, message: strings.transactionDeleted);
  }

  Future<void> _freeze(
    BuildContext context,
    WidgetRef ref,
    Transaction transaction,
  ) async {
    final strings = AlayaStrings.of(context);
    final code = await FreezeConversionSheet.show(
      context,
      excludeCode: transaction.originalAmount.currencyCode,
    );
    if (code == null || !context.mounted) return;
    final ok = await ref
        .read(transactionActionsProvider)
        .freezeConversion(
          transaction: transaction,
          toCurrencyCode: code,
        );
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.actionSaved)
        : showFailureSnack(context, message: strings.errorBodyGeneric);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionByIdProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.navExpenses),
        actions: [
          IconButton(
            onPressed: () =>
                context.push(Routes.transactionEdit(transactionId)),
            tooltip: strings.actionEdit,
            icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.lg),
          ),
        ],
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: strings.errorBodyGeneric,
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(transactionByIdProvider(transactionId)),
        ),
        data: (transaction) => transaction == null
            ? EmptyState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
                icon: Icons.search_off_outlined,
              )
            : _Body(
                transaction: transaction,
                onDelete: () => _delete(context, ref),
                onFreeze: () => _freeze(context, ref, transaction),
              ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.transaction,
    required this.onDelete,
    required this.onFreeze,
  });

  final Transaction transaction;
  final VoidCallback onDelete;
  final VoidCallback onFreeze;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final methods =
        ref.watch(paymentMethodsByIdProvider).valueOrNull ??
        const <String, PaymentMethod>{};
    final tags =
        ref.watch(transactionTagsProvider(transaction.id)).valueOrNull ??
        const [];
    final allocation = ref
        .watch(transactionAllocationProvider(transaction.id))
        .valueOrNull;
    final lines = ref.watch(transactionLinesProvider(transaction.id));
    final clock = ref.watch(clockProvider);

    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;
    final methodId = transaction.paymentMethodId;
    final frozen = transaction.frozenConversion;

    // `CustomScrollView`, not `ListView(children: [...])`. The lines list is fed by a repository
    // stream and U13 admits no row-count exemption — an itemised grocery receipt runs to dozens of
    // rows, so it is a `SliverList.builder` and the fixed sections around it are adapters.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: AlayaCard(
              tier: 2,
              padding: const EdgeInsets.all(AlayaSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AmountText(
                    transaction.signedAmount,
                    kind: transaction.kind,
                    size: AmountSize.large,
                    decimalDigits: digits,
                  ),
                  if (frozen != null) ...[
                    const SizedBox(height: AlayaSpacing.xxs),
                    AmountText(
                      frozen,
                      size: AmountSize.small,
                      showSign: false,
                      muted: true,
                    ),
                  ],
                  const SizedBox(height: AlayaSpacing.xs),
                  DateText.relative(transaction.dateKey, clock: clock),
                  if (transaction.needsReview ||
                      (allocation?.hasMismatch ?? false) ||
                      frozen != null) ...[
                    const SizedBox(height: AlayaSpacing.sm),
                    Wrap(
                      spacing: AlayaSpacing.xs,
                      runSpacing: AlayaSpacing.xs,
                      children: [
                        if (transaction.needsReview)
                          StatusChip(
                            label: strings.statusNeedsReview,
                            tone: StatusTone.info,
                          ),
                        if (allocation != null && allocation.hasMismatch)
                          StatusChip(
                            label: strings.statusUnallocated,
                            tone: StatusTone.warning,
                            trailing: AmountText(
                              allocation.unallocated.abs(),
                              size: AmountSize.small,
                              showSign: false,
                              decimalDigits: digits,
                            ),
                          ),
                        if (frozen != null)
                          StatusChip(label: strings.statusApproximate),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        SliverList.list(
          children: [
            SectionHeader(label: strings.detailSectionDetails),
            KeyValueRow(
              label: strings.labelKind,
              value: TransactionRow.kindLabel(strings, transaction.kind),
            ),
            KeyValueRow(
              label: strings.labelSubtype,
              value: TransactionRow.subtypeLabel(strings, transaction.subtype),
            ),
            KeyValueRow(
              label: strings.labelDate,
              valueWidget: DateText(
                transaction.dateKey,
                style: DateTextStyle.full,
              ),
            ),
            if (transaction.kind == TransactionKind.transfer) ...[
              KeyValueRow(
                label: strings.labelFrom,
                value: from == null ? null : accounts[from]?.name,
              ),
              KeyValueRow(
                label: strings.labelTo,
                value: to == null ? null : accounts[to]?.name,
              ),
            ] else
              KeyValueRow(
                label: strings.labelAccount,
                value: accounts[from ?? to ?? '']?.name,
              ),
            KeyValueRow(
              label: strings.labelPaymentMethod,
              value: methodId == null ? null : methods[methodId]?.name,
            ),
            KeyValueRow(
              label: strings.labelPayee,
              value: payeeId == null ? null : payees[payeeId]?.name,
            ),
            KeyValueRow(label: strings.labelNote, value: transaction.note),
            if (frozen != null)
              KeyValueRow(
                label: strings.actionFreezeConversion,
                value: strings.frozenConversionNote(
                  transaction.frozenConversionDateKey?.toIso() ?? '',
                  transaction.frozenConversionRateRaw ?? '',
                ),
              ),
            if (tags.isNotEmpty) ...[
              SectionHeader(label: strings.labelTags),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [for (final tag in tags) TagChip(tag: tag)],
                ),
              ),
            ],
            SectionHeader(label: strings.detailSectionLines),
          ],
        ),
        lines.when(
          loading: () => SliverToBoxAdapter(
            child: AlayaListSkeleton(label: strings.loadingLabel, rows: 2),
          ),
          error: (error, stack) => SliverToBoxAdapter(
            child: ErrorState(
              title: strings.errorTitleGeneric,
              body: strings.errorBodyGeneric,
            ),
          ),
          data: (rows) => rows.isEmpty
              ? SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AlayaSpacing.screenEdge,
                      vertical: AlayaSpacing.xs,
                    ),
                    child: Text(
                      strings.emptyBodyNoResults,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                  ),
                )
              : SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, index) =>
                      _LineRow(line: rows[index], decimalDigits: digits),
                ),
        ),
        SliverList.list(
          children: [
            const SizedBox(height: AlayaSpacing.xxl),
            if (frozen == null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: OutlinedButton(
                  onPressed: onFreeze,
                  child: Text(strings.actionFreezeConversion),
                ),
              ),
            const SizedBox(height: AlayaSpacing.sm),
            // Destructive last, quiet, and never a filled button: a red button at the top of a detail
            // screen is a mis-tap waiting to happen.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: TextButton(
                onPressed: onDelete,
                style: TextButton.styleFrom(foregroundColor: semantic.danger),
                child: Text(strings.actionDeleteTransaction),
              ),
            ),
            const SizedBox(height: AlayaSpacing.xxxl),
          ],
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.decimalDigits});

  final TransactionLine line;
  final int decimalDigits;

  /// Where this line's artefact lives, or null when it created nothing.
  ///
  /// Surfaces `transaction_lines.created*Id` (ARCH_5 §7.2): a purchase that produced a television
  /// or two kilos of potatoes should say so, and let the user walk to it.
  String? _artefactRoute() {
    final itemId = line.itemId;
    if (line.createdBatchId != null && itemId != null)
      return Routes.itemDetail(itemId);
    final assetId = line.createdAssetId;
    if (assetId != null) return Routes.assetDetail(assetId);
    final templateId = line.createdRecurringTemplateId;
    if (templateId != null) return Routes.recurringDetail(templateId);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final route = _artefactRoute();
    final quantity = line.quantity;
    final amount = line.lineAmount;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.description,
                  style: AlayaTypography.body.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (quantity != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  QtyText(quantity, muted: true),
                ],
                if (route != null) ...[
                  const SizedBox(height: AlayaSpacing.xxs),
                  InkWell(
                    onTap: () => context.push(route),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AlayaSpacing.xxs,
                      ),
                      child: Text(
                        strings.lineCreatedLink(line.description),
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.transfer,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(width: AlayaSpacing.sm),
            AmountText(
              amount,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: decimalDigits,
            ),
          ],
        ],
      ),
    );
  }
}
```

### `lib/features/expense/presentation/screens/transaction_editor_screen.dart`

```dart
import 'package:alaya/features/expense/presentation/widgets/split_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/bill_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/electronics_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/household_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/other_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_disclosure.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// The full transaction editor (ARCH_5 §3 archetype B).
///
/// Routed **outside** the drawer shell, and led by a close button rather than a back arrow: an
/// editor is a task, and ✕ says "abandon" where ← says "go up". Both route through
/// `AlayaFormScaffold`'s unsaved-changes guard (Law U10).
///
/// **Sections group by decision, not by table.** "What and how much" precedes "where it came from",
/// and the sub-form that appears depends on the subtype — never a screen listing every column the
/// `transactions` row happens to have.
class TransactionEditorScreen extends ConsumerWidget {
  /// Edits [transactionId], or creates a new transaction when it is null.
  const TransactionEditorScreen({this.transactionId, super.key});

  /// The transaction being edited, or null for a new one.
  final String? transactionId;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(transactionEditorProvider(transactionId).notifier)
        .save();
    if (!context.mounted) return;
    if (saved == null) {
      // The reason, not a stand-in for it (U9).
      final why = ref
          .read(transactionEditorProvider(transactionId))
          .valueOrNull
          ?.saveError;
      showFailureSnack(context, message: why ?? strings.errorBodyGeneric);
      return;
    }
    final after = ref
        .read(transactionEditorProvider(transactionId))
        .valueOrNull;
    final fanOutError = after?.fanOutError;
    // A line that asked to become recurring replaces this screen with the builder rather than popping,
    // so the draft it just offered is picked up on the next frame instead of going nowhere.
    // An asset the fan-out just created opens for the type and the warranty a receipt could not carry.
    // Checked before the recurring hand-off because a line cannot be both.
    final createdAsset = after?.createdAssetId;
    if (createdAsset != null) {
      // **The router is captured before the pop, not looked up inside the action.**
      //
      // A snack outlives the screen that showed it, so by the time the user taps its action this
      // `context` is a deactivated element — and `context.push` walks the ancestor tree to find the
      // router, which throws *"Looking up a deactivated widget's ancestor is unsafe"*. The `GoRouter`
      // itself survives the pop; holding a reference to it is what makes the action safe.
      //
      // The messenger is captured for the same reason: `ScaffoldMessenger.of` would fail too.
      final router = GoRouter.of(context);
      final target = Routes.assetEdit(createdAsset);
      if (context.canPop()) context.pop();
      if (!context.mounted) return;
      showResultSnack(
        context,
        message: strings.assetCreatedFromPurchase,
        actionLabel: strings.actionSetWarranty,
        onAction: () => router.push(target),
      );
      return;
    }
    if (after?.wantsTemplate ?? false) {
      context.pushReplacement(Routes.recurringNew);
      if (!context.mounted) return;
      showResultSnack(context, message: strings.recurringScheduleNext);
      return;
    }
    if (context.canPop()) context.pop();
    if (!context.mounted) return;
    // A half-succeeded write says which half. The transaction is saved either way; what failed is the
    // stock or asset a line asked for, and saying nothing is how a receipt silently fails to reach
    // the inventory (U9).
    fanOutError != null
        ? showFailureSnack(context, message: fanOutError)
        : showResultSnack(context, message: strings.actionSaved);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final async = ref.watch(transactionEditorProvider(transactionId));

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(
          transactionId == null
              ? strings.editorTitleNew
              : strings.editorTitleEdit,
        ),
      ),
      body: async.when(
        loading: () =>
            AlayaListSkeleton(label: strings.loadingLabel, hasLeading: false),
        // "It may have been deleted" only when it actually is. Anything else is a load failure and
        // says so, with a retry — reporting both the same way is what made four different bugs
        // arrive as one indistinguishable symptom.
        error: (error, stack) => error is TransactionNotFound
            ? ErrorState(
                title: strings.errorTitleNotFound,
                body: strings.errorBodyNotFound,
              )
            : ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () =>
                    ref.invalidate(transactionEditorProvider(transactionId)),
              ),
        data: (state) => AlayaFormScaffold(
          primaryLabel: _saveLabel(strings, state.kind),
          onPrimary: state.submitting ? null : () => _save(context, ref),
          isDirty: state.dirty,
          isSubmitting: state.submitting,
          discardTitle: strings.confirmDiscardTitle,
          discardBody: strings.confirmDiscardBody,
          discardConfirmLabel: strings.actionDiscard,
          discardCancelLabel: strings.actionKeepEditing,
          child: _Form(editorId: transactionId, state: state),
        ),
      ),
    );
  }

  static String _saveLabel(AlayaStrings strings, TransactionKind kind) =>
      switch (kind) {
        TransactionKind.deposit => strings.saveIncome,
        TransactionKind.transfer => strings.saveTransfer,
        TransactionKind.withdrawal => strings.saveExpense,
        TransactionKind.adjustmentIncrease => strings.saveIncome,
        TransactionKind.adjustmentDecrease => strings.saveExpense,
      };
}

class _Form extends ConsumerWidget {
  const _Form({required this.editorId, required this.state});

  final String? editorId;
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final methods =
        ref.watch(editorPaymentMethodsProvider).valueOrNull ??
        const <PaymentMethod>[];
    final tags =
        ref.watch(editorTagsProvider(state.kind)).valueOrNull ?? const <Tag>[];
    final localeTag = Localizations.localeOf(context).toString();

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.kindWithdrawal),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.kindDeposit),
            ),
            ButtonSegment(
              value: TransactionKind.transfer,
              label: Text(strings.kindTransfer),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        SectionHeader(
          label: strings.sectionWhatAndHowMuch,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: state.currencyCode,
            decimalDigits: digits,
            label: strings.labelAmount,
            initialValue: state.amount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.dateKey,
          label: strings.labelDate,
          formatted: (date) =>
              DateFormat.yMMMd(localeTag).format(date.toUtcMidnight()),
          onChanged: notifier.setDate,
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionSubtype>(
          key: ValueKey(state.subtype),
          initialValue: state.subtype,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelSubtype),
          items: [
            for (final subtype in state.availableSubtypes)
              DropdownMenuItem(
                value: subtype,
                child: Text(TransactionRow.subtypeLabel(strings, subtype)),
              ),
          ],
          onChanged: (value) =>
              value == null ? null : notifier.setSubtype(value),
        ),
        // **One door, not five collapsed sections** (Law U16). Amount, date and category are what a
        // purchase needs; account, payment method, tags, the note and the subtype-specific fields are
        // refinements. Eleven controls at once is what made this screen hard to read — none of them is
        // hard on its own.
        //
        // Opens itself whenever any of them already holds a value, so reopening a saved record shows
        // what that record actually contains rather than a chevron with something behind it.
        AlayaDisclosure(
          label: strings.sectionMoreDetails,
          summary: _detailSummary(strings, state, accounts, methods, tags),
          startExpanded: _hasDetails(state),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (state.kind != TransactionKind.transfer) ...[
                SectionHeader(
                  label: state.kind == TransactionKind.deposit
                      ? strings.sectionWhereItCameFrom
                      : strings.sectionWhereItWent,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
                if (state.kind != TransactionKind.deposit)
                  AccountPicker(
                    accounts: accounts,
                    selected: accountFor(state.fromAccountId),
                    label: strings.labelAccount,
                    hint: strings.hintSelectAccount,
                    onChanged: (account) => notifier.setFromAccount(account.id),
                  ),
                const SizedBox(height: AlayaSpacing.md),
                DropdownButtonFormField<String>(
                  key: ValueKey(state.paymentMethodId),
                  initialValue: state.paymentMethodId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: strings.labelPaymentMethod,
                  ),
                  items: [
                    for (final method in methods)
                      DropdownMenuItem(
                        value: method.id,
                        child: Text(method.name),
                      ),
                  ],
                  onChanged: notifier.setPaymentMethod,
                ),
                const SizedBox(height: AlayaSpacing.md),
              ],
              _SubtypeForm(
                editorId: editorId,
                state: state,
                decimalDigits: digits,
              ),
              // Only where a shared bill makes sense. A transfer between your own accounts has no
              // counterparty to owe anything, and a deposit is money arriving — neither is a bill
              // somebody could owe you a share of.
              if (state.kind == TransactionKind.withdrawal)
                SplitSection(
                  editorId: editorId,
                  state: state,
                  decimalDigits: digits,
                ),
              if (tags.isNotEmpty) ...[
                SectionHeader(
                  label: strings.labelTags,
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.xl,
                    bottom: AlayaSpacing.xs,
                  ),
                ),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final tag in tags)
                      TagChip(
                        tag: tag,
                        selected: state.tagIds.contains(tag.id),
                        onTap: () => notifier.toggleTag(tag.id),
                      ),
                  ],
                ),
              ],
              SectionHeader(
                label: strings.labelNote,
                padding: const EdgeInsets.only(
                  top: AlayaSpacing.xl,
                  bottom: AlayaSpacing.xs,
                ),
              ),
              TextFormField(
                initialValue: state.note,
                maxLines: 3,
                decoration: InputDecoration(hintText: strings.hintNote),
                onChanged: notifier.setNote,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Whether anything behind the door is set, so it should open on arrival.
  ///
  /// Account and payment method are excluded deliberately: both carry a default from settings, so
  /// treating them as content would open the door on every new record and the tiering would do nothing.
  /// A **user-chosen** account still shows in the summary — it is visible without being a reason to
  /// expand.
  static bool _hasDetails(TransactionEditorState state) =>
      state.tagIds.isNotEmpty ||
      (state.note ?? '').trim().isNotEmpty ||
      state.lines.isNotEmpty ||
      state.split != null;

  /// What is set behind the door, for the collapsed row.
  ///
  /// The values a user would go looking for, joined — not a field list. A collapsed section that gives
  /// no account of itself is where values go to hide.
  static String? _detailSummary(
    AlayaStrings strings,
    TransactionEditorState state,
    List<Account> accounts,
    List<PaymentMethod> methods,
    List<Tag> tags,
  ) {
    final parts = <String>[];
    for (final account in accounts) {
      if (account.id == state.fromAccountId) {
        parts.add(account.name);
        break;
      }
    }
    for (final method in methods) {
      if (method.id == state.paymentMethodId) {
        parts.add(method.name);
        break;
      }
    }
    if (state.tagIds.isNotEmpty)
      parts.add(strings.tagCount(state.tagIds.length));
    if ((state.note ?? '').trim().isNotEmpty) parts.add(strings.labelNote);
    if (state.lines.isNotEmpty)
      parts.add(strings.lineCount(state.lines.length));

    final split = state.split;
    if (split != null && split.isActive)
      parts.add(strings.splitPerPersonCount(split.inputs.length));

    return parts.isEmpty ? null : parts.join(' \u00B7 ');
  }
}

class _SubtypeForm extends StatelessWidget {
  const _SubtypeForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
  });

  final String? editorId;
  final TransactionEditorState state;
  final int decimalDigits;

  @override
  Widget build(BuildContext context) {
    if (state.kind == TransactionKind.transfer ||
        state.subtype == TransactionSubtype.transferOut) {
      return TransferForm(editorId: editorId, state: state);
    }
    return switch (state.subtype) {
      TransactionSubtype.grocery => GroceryForm(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
      ),
      TransactionSubtype.household => HouseholdForm(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
      ),
      TransactionSubtype.electronics => ElectronicsForm(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
      ),
      TransactionSubtype.bill => BillForm(editorId: editorId, state: state),
      TransactionSubtype.salaryIn || TransactionSubtype.otherIn => DepositForm(
        editorId: editorId,
        state: state,
      ),
      TransactionSubtype.transferSelf || TransactionSubtype.transferOut =>
        TransferForm(editorId: editorId, state: state),
      TransactionSubtype.otherOut => OtherForm(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
      ),
    };
  }
}
```

### `lib/features/expense/presentation/screens/transaction_list_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_filter_sheet.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/providers/transaction_search_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/filter_chip_bar.dart';

/// The transaction ledger (ARCH_5 §3 archetype C).
///
/// **Search and filter live in the body, not the app bar.** The drawer shell owns the `Scaffold` and
/// its `AppBar` for every top-level destination, so a destination cannot contribute app-bar actions —
/// and a nested `Scaffold` carrying a second app bar would be worse than none. Putting them in the
/// body also makes this screen and the catalogue archetype consistent, where ARCH_5 §3 archetype D
/// already says the search field is pinned rather than hidden behind a magnifying glass.
///
/// **No pull-to-refresh.** The data is local and streamed, so a refresh gesture cannot do anything;
/// offering one teaches the user the app is slow.
class TransactionListScreen extends ConsumerWidget {
  /// Creates the ledger.
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final searching = ref.watch(isSearchingProvider);

    return Scaffold(
      // A nested Scaffold with no app bar: the shell above supplies the bar and the drawer, this one
      // supplies the FAB slot and a snack-bar host for the delete-and-undo flow.
      body: Column(
        children: [
          const _Toolbar(),
          if (!searching) ...[
            const _NeedsReviewRow(),
            const _ActiveFilters(),
          ],
          Expanded(
            child: searching ? const _SearchResults() : const _GroupedList(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        // The sheet, not the editor. Capturing a purchase is the frequent act and wants five
        // controls; the eleven-control editor is where you go when five are not enough, reached
        // from the sheet's own "Add details".
        onPressed: () => QuickAddSheet.show(context),
        tooltip: strings.addExpense,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final narrowed = ref.watch(transactionFilterProvider).isNarrowed;
    final semantic = context.semantic;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.xs,
        AlayaSpacing.xxs,
      ),
      child: Row(
        children: [
          Expanded(
            child: AlayaSearchField(
              hintText: strings.searchTransactionsHint,
              clearLabel: strings.actionClearSearch,
              onChanged: ref.read(transactionSearchQueryProvider.notifier).set,
            ),
          ),
          IconButton(
            onPressed: () => TransactionFilterSheet.show(context),
            tooltip: strings.filterTitle,
            icon: Icon(
              narrowed ? Icons.filter_alt : Icons.filter_alt_outlined,
              size: AlayaIconSize.lg,
              color: narrowed ? semantic.transfer : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _NeedsReviewRow extends ConsumerWidget {
  const _NeedsReviewRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);
    // Hidden once the user has acted on it: a nudge that stays put while you are looking at exactly
    // what it pointed at reads as an instruction you have failed to follow.
    if (filter.needsReviewOnly) return const SizedBox.shrink();
    final count = ref.watch(needsReviewCountProvider).valueOrNull ?? 0;
    return NeedsReviewBanner(
      count: count,
      onTap: ref.read(transactionFilterProvider.notifier).showNeedsReviewOnly,
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    if (!filter.isNarrowed) return const SizedBox.shrink();

    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};

    return FilterChipBar(
      clearAllLabel: strings.actionClearAll,
      onClearAll: notifier.clear,
      filters: [
        if (filter.needsReviewOnly)
          ActiveFilter(
            label: strings.statusNeedsReview,
            onRemove: notifier.clearNeedsReviewOnly,
          ),
        if (filter.preset != DateRangePreset.last30Days)
          ActiveFilter(
            label: TransactionFilterSheet.rangeLabel(strings, filter.preset),
            onRemove: () => notifier.setPreset(DateRangePreset.last30Days),
          ),
        for (final kind in filter.kinds)
          ActiveFilter(
            label: TransactionRow.kindLabel(strings, kind),
            onRemove: () => notifier.toggleKind(kind),
          ),
        for (final subtype in filter.subtypes)
          ActiveFilter(
            label: TransactionRow.subtypeLabel(strings, subtype),
            onRemove: () => notifier.toggleSubtype(subtype),
          ),
        if (filter.accountId != null)
          ActiveFilter(
            label: strings.filterChipAccount(
              accounts[filter.accountId]?.name ?? filter.accountId!,
            ),
            onRemove: () => notifier.setAccount(null),
          ),
        if (filter.payeeId != null)
          ActiveFilter(
            label: strings.filterChipPayee(
              payees[filter.payeeId]?.name ?? filter.payeeId!,
            ),
            onRemove: () => notifier.setPayee(null),
          ),
      ],
    );
  }
}

class _GroupedList extends ConsumerWidget {
  const _GroupedList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final days = ref.watch(transactionDaysProvider);

    return days.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(filteredTransactionsProvider),
      ),
      data: (groups) {
        if (groups.isEmpty) {
          return EmptyState(
            title: strings.emptyTitleNoTransactions,
            body: strings.emptyBodyNoTransactions,
            icon: Icons.receipt_long_outlined,
            actionLabel: strings.addExpense,
            // **Deliberately still the full editor.** An empty ledger means somebody is setting up
            // rather than capturing at a till, and the full form is the better first experience. It
            // also keeps `Routes.transactionNew` reachable: a route nothing navigates to is the
            // failure this whole change is fixing, and swapping it for another instance of the same
            // mistake would be no improvement (ARCH_5 §9.2).
            onAction: () => context.push(Routes.transactionNew),
          );
        }
        final clock = ref.watch(clockProvider);
        final background = Theme.of(context).scaffoldBackgroundColor;
        return CustomScrollView(
          slivers: [
            for (final group in groups)
              SliverMainAxisGroup(
                slivers: [
                  SliverPersistentHeader(
                    pinned: true,
                    delegate: _DayHeader(
                      date: group.date,
                      clock: clock,
                      background: background,
                    ),
                  ),
                  SliverList.builder(
                    itemCount: group.transactions.length,
                    itemBuilder: (context, index) =>
                        _Row(transaction: group.transactions[index]),
                  ),
                ],
              ),
            const SliverToBoxAdapter(
              child: SizedBox(height: AlayaSpacing.xxxl),
            ),
          ],
        );
      },
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final results = ref.watch(transactionSearchResultsProvider);

    return results.when(
      loading: () => AlayaListSkeleton(label: strings.loadingTransactions),
      error: (error, stack) => ErrorState(
        title: strings.errorTitleGeneric,
        body: strings.errorBodyGeneric,
        retryLabel: strings.actionRetry,
        onRetry: () => ref.invalidate(transactionSearchResultsProvider),
      ),
      // Search results are ranked by relevance, so they are deliberately not grouped by day — a date
      // header over a relevance-ordered list asserts an order the list does not have.
      data: (rows) => rows.isEmpty
          ? EmptyState(
              title: strings.emptyTitleNoResults,
              body: strings.emptyBodyNoResults,
              icon: Icons.search_off_outlined,
            )
          : ListView.builder(
              itemCount: rows.length,
              itemBuilder: (context, index) => _Row(transaction: rows[index]),
            ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row({required this.transaction});

  final Transaction transaction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};
    final payees =
        ref.watch(payeesByIdProvider).valueOrNull ?? const <String, Payee>{};
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final from = transaction.fromAccountId;
    final to = transaction.toAccountId;
    final payeeId = transaction.payeeId;

    return TransactionRow(
      transaction: transaction,
      decimalDigits: digits,
      payee: payeeId == null ? null : payees[payeeId],
      fromAccount: from == null ? null : accounts[from],
      toAccount: to == null ? null : accounts[to],
      onTap: () => context.push(Routes.transactionDetail(transaction.id)),
    );
  }
}

class _DayHeader extends SliverPersistentHeaderDelegate {
  const _DayHeader({
    required this.date,
    required this.clock,
    required this.background,
  });

  final DateKey date;
  final Clock clock;
  final Color background;

  // The tap-target floor rather than a hand-picked figure: it is the one height token that stays
  // legible when the text scale doubles, which a guessed 36 would not.
  @override
  double get minExtent => AlayaSpacing.minTapTarget;

  @override
  double get maxExtent => AlayaSpacing.minTapTarget;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: background,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AlayaSpacing.screenEdge,
        vertical: AlayaSpacing.xs,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: DateText.relative(
          date,
          clock: clock,
          textStyle: AlayaTypography.sectionHeader,
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(_DayHeader oldDelegate) =>
      oldDelegate.date != date || oldDelegate.background != background;
}
```

### `lib/features/expense/presentation/sheets/delete_transaction_sheet.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Captures an optional reason before deleting (ARCH_5 §3 archetype A).
///
/// **This is not the primary delete.** Deleting a transaction is reversible, so the ordinary path
/// does it immediately and offers Undo — a confirmation dialog on an undoable action is friction
/// with no safety value, and it trains people to tap through the confirmations that do matter
/// (ARCH_5 §5.5).
///
/// This sheet exists only for the "delete with a reason" path, which is what surfaces
/// `transactions.deleteReason` (ARCH_5 §7.2). A household ledger genuinely needs "duplicate" or
/// "wrong account" recorded sometimes, and Phase 8B's trash screen shows it back. It still ends in
/// an Undo rather than a confirmation.
class DeleteTransactionSheet extends StatefulWidget {
  /// Creates the sheet. Prefer [show].
  const DeleteTransactionSheet({super.key});

  /// Opens the sheet, resolving to the typed reason, or null if the user backed out.
  ///
  /// An empty reason resolves to the empty string rather than null, so a caller can tell "deleted
  /// without saying why" from "changed their mind".
  static Future<String?> show(BuildContext context) =>
      AlayaBottomSheet.show<String>(
        context: context,
        builder: (context) => const DeleteTransactionSheet(),
      );

  @override
  State<DeleteTransactionSheet> createState() => _DeleteTransactionSheetState();
}

class _DeleteTransactionSheetState extends State<DeleteTransactionSheet> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionDeleteTransaction,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.confirmDeleteBody,
          style: AlayaTypography.body.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: strings.deleteReasonHint),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(strings.actionDelete),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/sheets/freeze_conversion_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Picks the currency to freeze a converted snapshot into (ARCH_5 §3 archetype A).
///
/// **A frozen snapshot, not a rewrite.** The original amount and its currency are immutable once
/// saved (Law L9); freezing writes `convertedAmountMinor`, `conversionRate`, `conversionRateRaw` and
/// `conversionDateKey` alongside them as a separate artefact that is never recomputed. The raw rate
/// string is stored so a figure the user later questions can be reproduced exactly.
///
/// The rate used is the one for the transaction's own date, resolved by the greatest
/// `rateDateKey <= D` rule — never interpolated, and marked approximate when only an earlier rate
/// exists (ARCH_3 §1.3).
class FreezeConversionSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const FreezeConversionSheet({required this.excludeCode, super.key});

  /// The transaction's own currency, which is never offered as a target.
  final String excludeCode;

  /// Opens the sheet, resolving to the chosen currency code or null.
  static Future<String?> show(
    BuildContext context, {
    required String excludeCode,
  }) => AlayaBottomSheet.show<String>(
    context: context,
    builder: (context) => FreezeConversionSheet(excludeCode: excludeCode),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final currencies = ref.watch(enabledCurrenciesProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.actionFreezeConversion,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        currencies.when(
          loading: () => AlayaListSkeleton(
            label: strings.loadingLabel,
            rows: 3,
            hasTrailing: false,
          ),
          error: (error, stack) => ErrorState(
            title: strings.errorTitleGeneric,
            body: strings.errorBodyGeneric,
            retryLabel: strings.actionRetry,
            onRetry: () => ref.invalidate(enabledCurrenciesProvider),
          ),
          data: (rows) {
            final options = rows.where((c) => c.code != excludeCode).toList();
            if (options.isEmpty) {
              return EmptyState(
                title: strings.emptyTitleNoResults,
                body: strings.errorBodyGeneric,
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final currency in options)
                  ListTile(
                    title: Text(currency.name),
                    trailing: Text(currency.code, style: AlayaTypography.label),
                    onTap: () => Navigator.of(context).pop(currency.code),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/sheets/line_item_editor.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/core/enums/inventory_enums.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/item.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/qty_field.dart';

/// Items the line editor can attach a quantity to.
final lineEditorItemsProvider = StreamProvider.autoDispose<List<Item>>(
  (ref) => ref.watch(itemRepositoryProvider).watchAll(),
);

/// Units in the category of the currently chosen item.
final lineEditorUnitsProvider = StreamProvider.autoDispose
    .family<List<Unit>, UnitCategory?>(
      (ref, category) => category == null
          ? Stream.value(const <Unit>[])
          : ref.watch(unitRepositoryProvider).watchByCategory(category),
    );

/// What [LineItemEditor] hands back: the line, and whether another should open straight away.
class LineItemDraft {
  /// Creates a result.
  const LineItemDraft({required this.line, this.addAnother = false});

  /// The line the user built.
  final TransactionLine line;

  /// Whether to reopen the editor blank once this one is stored.
  ///
  /// A grocery receipt is fifteen lines, and closing the sheet between each one made itemising an
  /// expense feel like fifteen separate tasks. The caller loops while this is true.
  final bool addAnother;
}

/// Edits one line of a transaction (ARCH_5 §3 archetype A).
///
/// **An Item can be created here, and that is what makes the receipt reach the inventory at all.**
/// `PurchaseFanOutService._planBatch` refuses a line without `itemId`, so without an inline create a
/// user on a fresh install itemises a grocery receipt, saves it, and nothing ever appears in the
/// inventory — the batch was never planned. The catalogue is discovered while typing the receipt,
/// exactly as a payee is.
///
/// **Quantity is offered only once an Item is chosen, and that is the schema talking rather than a
/// simplification.** A `Qty` is an integer plus a `UnitCategory`, and the category comes from the
/// Item — it is immutable per Item and cross-category conversion does not exist (Law L8). A free-text
/// line has no category, so a quantity on it would be a number whose meaning nothing records. It is
/// also exactly what the fan-out requires: `_planBatch` refuses a line without a catalogued item,
/// because a batch with a guessed quantity is stock the user never bought.
class LineItemEditor extends ConsumerStatefulWidget {
  /// Edits [line], or creates a new one when it is null.
  const LineItemEditor({
    required this.currencyCode,
    required this.decimalDigits,
    required this.defaultDestination,
    this.line,
    super.key,
  });

  /// The transaction's currency. A line cannot be denominated in another.
  final String currencyCode;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line should default to — inventory for a grocery or household purchase.
  final TransactionLineDestination defaultDestination;

  /// The line being edited, or null for a new one.
  final TransactionLine? line;

  /// Opens the sheet, resolving to the edited line or null.
  static Future<LineItemDraft?> show(
    BuildContext context, {
    required String currencyCode,
    required int decimalDigits,
    required TransactionLineDestination defaultDestination,
    TransactionLine? line,
  }) => AlayaBottomSheet.show<LineItemDraft>(
    context: context,
    builder: (context) => LineItemEditor(
      currencyCode: currencyCode,
      decimalDigits: decimalDigits,
      defaultDestination: defaultDestination,
      line: line,
    ),
  );

  @override
  ConsumerState<LineItemEditor> createState() => _LineItemEditorState();
}

class _LineItemEditorState extends ConsumerState<LineItemEditor> {
  late final TextEditingController _description = TextEditingController(
    text: widget.line?.description ?? '',
  );
  late TransactionLineDestination _destination =
      widget.line?.destination ?? widget.defaultDestination;
  late String? _itemId = widget.line?.itemId;
  late Qty? _quantity = widget.line?.quantity;

  /// The unit code the quantity is entered in.
  ///
  /// **Held as a code, seeded from the saved line.** `QtyField` formats its initial text against the
  /// `selectedUnit` it is handed, so a null here fell back to `units.first` — milligram — and a line
  /// saved as `50 kg` reopened as `50000000 mg`. The units list arrives asynchronously, so the code is
  /// what persists and the `Unit` is resolved from it on each build.
  late String? _unitCode = widget.line?.unitCode;
  late Money? _unitPrice = widget.line?.unitPrice;
  late Money? _lineAmount = widget.line?.lineAmount;
  bool _descriptionMissing = false;
  bool _creatingItem = false;
  UnitCategory _newItemCategory = UnitCategory.count;
  bool _createFailed = false;

  /// Whether the inventory fields were left incomplete on the last attempt.
  ///
  /// **Set on submit rather than watched continuously.** A line is incomplete for most of the time somebody is
  /// filling it in, and colouring it red from the first keystroke trains people to ignore the colour.
  bool _inventoryMissing = false;

  /// The value the "new item" row carries.
  ///
  /// **A sentinel rather than a nullable value.** `null` in this dropdown already means "nothing chosen", and a
  /// row that reused it could not be told apart from clearing the field. Item ids are UUIDv7, so nothing can
  /// collide with this.
  static const String _newItemValue = '__alaya_new_item__';

  Future<void> _createItem() async {
    final name = _description.text.trim();
    if (name.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    final item = Item(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: ref.read(normalizerProvider).normalize(name),
      unitCategory: _newItemCategory,
      defaultDisplayUnitCode: _newItemCategory.baseUnitCode,
      itemKind: ItemKind.generic,
      isFavorite: false,
    );
    final saved = await ref.read(itemRepositoryProvider).save(item);
    if (!mounted) return;
    final value = saved.valueOrNull;
    setState(() {
      _createFailed = value == null;
      if (value == null) return;
      _itemId = value.id;
      _creatingItem = false;
      _unitCode = value.defaultDisplayUnitCode;
      _quantity = null;
    });
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  /// What is still missing before this line can be saved, or null.
  ///
  /// **An inventory line needs an item, a quantity and a unit, and nothing here used to say so.** The line
  /// saved happily, `LineItemsScreen` accepted it, and `PurchaseFanOutService._planBatch` refused it on
  /// Continue — one screen further on, as a snackbar, about a line the user had stopped looking at. By then
  /// there was nothing on screen to correct.
  ///
  /// A quantity without a unit is not a partial answer, it is a number with no dimension: `QtyField` only
  /// appears once an item is chosen, so these three arrive together or not at all.
  String? _whatIsMissing(AlayaStrings strings) {
    if (_destination != TransactionLineDestination.inventory) return null;
    if (_itemId == null) return strings.lineItemRequired;
    if (_quantity == null || _unitCode == null) {
      return strings.lineQuantityRequired;
    }
    return null;
  }

  void _submit({bool addAnother = false}) {
    final strings = AlayaStrings.of(context);
    final description = _description.text.trim();
    if (description.isEmpty) {
      setState(() => _descriptionMissing = true);
      return;
    }
    // **Refused here rather than accepted and refused later.** Stopping at the field that is wrong, while the
    // field is still on screen, is the difference between a correction and a mystery.
    if (_whatIsMissing(strings) != null) {
      setState(() => _inventoryMissing = true);
      return;
    }
    final existing = widget.line;
    final line = TransactionLine(
      id: existing?.id ?? ref.read(uidGeneratorProvider).generate(),
      transactionId: existing?.transactionId ?? '',
      lineNo: existing?.lineNo ?? 1,
      description: description,
      destination: _destination,
      itemId: _itemId,
      quantity: _quantity,
      unitCode: _unitCode ?? existing?.unitCode,
      unitPrice: _unitPrice,
      lineAmount: _lineAmount,
      createdBatchId: existing?.createdBatchId,
      createdAssetId: existing?.createdAssetId,
      createdRecurringTemplateId: existing?.createdRecurringTemplateId,
      note: existing?.note,
    );
    Navigator.of(
      context,
    ).pop(LineItemDraft(line: line, addAnother: addAnother));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final items =
        ref.watch(lineEditorItemsProvider).valueOrNull ?? const <Item>[];
    Item? selectedItem;
    for (final item in items) {
      if (item.id == _itemId) {
        selectedItem = item;
        break;
      }
    }
    final units =
        ref
            .watch(lineEditorUnitsProvider(selectedItem?.unitCategory))
            .valueOrNull ??
        const <Unit>[];
    Unit? selectedUnit;
    for (final unit in units) {
      if (unit.code == _unitCode) selectedUnit = unit;
    }
    // Prefer the item's own display unit over the first in the list: a catalogue entry measured in
    // kilograms should not open in milligrams just because that sorts first.
    if (selectedUnit == null) {
      for (final unit in units) {
        if (unit.code == selectedItem?.defaultDisplayUnitCode)
          selectedUnit = unit;
      }
    }
    selectedUnit ??= units.isEmpty ? null : units.first;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.lineDescription,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _description,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: strings.lineDescription,
            errorText: _descriptionMissing ? strings.errorFieldRequired : null,
          ),
          onChanged: (_) {
            if (_descriptionMissing)
              setState(() => _descriptionMissing = false);
          },
        ),
        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<TransactionLineDestination>(
          key: ValueKey(_destination),
          initialValue: _destination,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelCategory),
          items: [
            for (final destination in TransactionLineDestination.values)
              DropdownMenuItem(
                value: destination,
                child: Text(_destinationLabel(strings, destination)),
              ),
          ],
          onChanged: (value) => value == null
              ? null
              : setState(() {
                  _destination = value;
                  // Cleared with the fields: a stale item link on an asset line would reach
                  // `_planBatch` and be refused, for a quantity the user was never shown.
                  if (value != TransactionLineDestination.inventory) {
                    _itemId = null;
                    _quantity = null;
                    _unitCode = null;
                    _creatingItem = false;
                  }
                }),
        ),
        // **The label alone never said which was which.** "Add to inventory" and "Add to services"
        // are indistinguishable to anyone who has not read the schema, so an iPhone went to inventory,
        // was refused for want of a quantity, and appeared in neither place. The helper names a real
        // example of each: consumed versus kept is the whole distinction.
        Padding(
          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
          child: Text(
            _destinationHelp(strings, _destination),
            style: AlayaTypography.caption.copyWith(
              color: context.semantic.muted,
            ),
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Only inventory needs an item, a quantity and a unit.** A television has no grams and a
        // recurring line has no stock; offering the fields anyway invited an iPhone to be filed as
        // measured stock, which `_planBatch` then refused for want of a quantity. The whole block is
        // gated on the destination rather than each field being individually pointless.
        if (_destination == TransactionLineDestination.inventory) ...[
          if (_creatingItem)
            _NewItemRow(
              category: _newItemCategory,
              onCategoryChanged: (category) =>
                  setState(() => _newItemCategory = category),
              onCreate: _createItem,
              onCancel: () => setState(() => _creatingItem = false),
            )
          else
            // **Always a dropdown, even with nothing in the catalogue.** It used to show a line of grey help
            // text instead, so somebody with no items yet had no control to press — they filled in the rest of
            // the line, hit Continue, and met a snackbar refusing it. The way to make an item was a separate
            // button beside a field that was not there.
            //
            // Now the list is never empty: it always ends with **New item**, so the first item is created from
            // the same control that picks the hundredth.
            Builder(
              builder: (context) => DropdownButtonFormField<String>(
                // **`selectedItem?.id`, not `_itemId`.** The items arrive from a stream, so on the frame
                // right after an inline create the state already names the new item while the list has
                // not re-emitted it — and a dropdown holding a value none of its items carry throws
                // "There should be exactly one item", which is a red screen. Deriving the value from the
                // list being rendered makes the mismatch unrepresentable.
                key: ValueKey(selectedItem?.id),
                initialValue: selectedItem?.id,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: strings.labelItem,
                  errorText: _inventoryMissing && _itemId == null
                      ? strings.lineItemRequired
                      : null,
                ),
                // **The closed field shows the name alone; the open menu shows what it is measured in.**
                // `selectedItemBuilder` exists for exactly this, and without it the two-line option would set
                // the height of the collapsed field as well.
                //
                // One entry per `DropdownMenuItem`, in the same order — including the trailing "new item" row,
                // which is why this list ends with it too.
                selectedItemBuilder: (context) => [
                  for (final item in items)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(strings.itemCreate),
                  ),
                ],
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.id,
                      // **The name is not enough to choose by.** An item's identity is
                      // `(normalized_name, unit_category)` — "Rice" by weight and "Rice" by count are two
                      // different rows — so a list of bare names cannot answer "is this the one I mean?", and
                      // the wrong answer costs a quantity in the wrong dimension.
                      child: _ItemOption(item: item),
                    ),
                  DropdownMenuItem(
                    value: _newItemValue,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AlayaSpacing.xs,
                      children: [
                        Icon(
                          Icons.add,
                          size: AlayaIconSize.sm,
                          color: context.semantic.muted,
                        ),
                        Text(strings.itemCreate),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  // Choosing the last row is not choosing an item — it swaps this control for the create form,
                  // and `_itemId` is deliberately left where it was so cancelling restores the old choice.
                  if (value == _newItemValue) {
                    setState(() => _creatingItem = true);
                    return;
                  }
                  setState(() {
                    // **Picking an item fills the description.** The two are different columns — the
                    // description is what the receipt said, `itemId` is what it stocks — but the receipt
                    // almost always says the item's name, and making the user retype "onion" after
                    // choosing Onion is friction with no purpose. An edit of their own is never
                    // overwritten: the fill only happens while the field is empty or still holds the
                    // previously-picked item's name.
                    final previous = _nameOf(items, _itemId);
                    _itemId = value;
                    final picked = _nameOf(items, value);
                    final typed = _description.text.trim();
                    if (picked != null &&
                        (typed.isEmpty || typed == previous)) {
                      _description.text = picked;
                      _descriptionMissing = false;
                    }
                    // The category changed, so any unit and quantity chosen against the old one is now
                    // meaningless rather than merely stale — Law L8 has no cross-category conversion.
                    _unitCode = null;
                    _quantity = null;
                    // Whatever was missing is now chosen, so the red goes rather than waiting for a second
                    // submit to clear it.
                    _inventoryMissing = false;
                  });
                },
              ),
            ),
          if (_createFailed) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              strings.errorBodyGeneric,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.danger,
              ),
            ),
          ],
          // The quantity half of the same rule. The item half rides on the dropdown's own `errorText`, where
          // the reader is already looking; this one has no single field to attach to, because a quantity and
          // its unit are one answer given through two controls.
          if (_inventoryMissing && _itemId != null) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            Text(
              strings.lineQuantityRequired,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.danger,
              ),
            ),
          ],
          if (selectedItem != null &&
              units.isNotEmpty &&
              selectedUnit != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            QtyField(
              key: ValueKey('${selectedItem.id}:${selectedUnit.code}'),
              category: selectedItem.unitCategory,
              units: units,
              selectedUnit: selectedUnit,
              label: strings.labelQuantity,
              unitLabel: strings.labelUnit,
              initialValue: _quantity,
              onChanged: (quantity) => _quantity = quantity,
              onUnitChanged: (unit) => setState(() => _unitCode = unit.code),
            ),
          ],
        ],
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineUnitPrice,
          initialValue: _unitPrice,
          onChanged: (value) => _unitPrice = value,
        ),
        const SizedBox(height: AlayaSpacing.md),
        AmountField(
          currencyCode: widget.currencyCode,
          decimalDigits: widget.decimalDigits,
          label: strings.lineAmount,
          initialValue: _lineAmount,
          onChanged: (value) => _lineAmount = value,
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(onPressed: _submit, child: Text(strings.actionDone)),
        const SizedBox(height: AlayaSpacing.xs),
        // The bulk path. Itemising a receipt should not mean opening and closing this sheet once per
        // line, so this commits and reopens blank; the caller keeps looping while it is asked to.
        TextButton.icon(
          onPressed: () => _submit(addAnother: true),
          icon: const Icon(Icons.add, size: AlayaIconSize.sm),
          label: Text(strings.lineItemsSaveAndAnother),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.actionCancel),
        ),
      ],
    );
  }

  static String? _nameOf(List<Item> items, String? id) {
    if (id == null) return null;
    for (final item in items) {
      if (item.id == id) return item.name;
    }
    return null;
  }

  static String _categoryLabel(AlayaStrings strings, UnitCategory category) =>
      switch (category) {
        UnitCategory.weight => strings.unitCategoryWeight,
        UnitCategory.volume => strings.unitCategoryVolume,
        UnitCategory.count => strings.unitCategoryCount,
      };

  static String _destinationLabel(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) => switch (destination) {
    TransactionLineDestination.none => strings.destinationNone,
    TransactionLineDestination.inventory => strings.destinationInventory,
    TransactionLineDestination.asset => strings.destinationAsset,
    TransactionLineDestination.recurring => strings.destinationRecurring,
  };

  static String _destinationHelp(
    AlayaStrings strings,
    TransactionLineDestination destination,
  ) => switch (destination) {
    TransactionLineDestination.none => strings.destinationHelpNone,
    TransactionLineDestination.inventory => strings.destinationHelpInventory,
    TransactionLineDestination.asset => strings.destinationHelpAsset,
    TransactionLineDestination.recurring => strings.destinationHelpRecurring,
  };
}

/// One item in the picker: what it is called, and what it is measured in.
///
/// **The second line is the point of this widget.** An item's identity in the schema is
/// `(normalized_name, unit_category)` — `idx_items_identity` is unique on the pair — so "Rice" measured by
/// weight and "Rice" counted in packets are two different rows that a list of names renders identically.
/// Picking the wrong one is not a cosmetic mistake: the quantity that follows is then in the wrong dimension,
/// and Law L8 has no conversion between categories to rescue it.
class _ItemOption extends StatelessWidget {
  const _ItemOption({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        Text(
          _LineItemEditorState._categoryLabel(strings, item.unitCategory),
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
      ],
    );
  }
}

class _NewItemRow extends StatelessWidget {
  const _NewItemRow({
    required this.category,
    required this.onCategoryChanged,
    required this.onCreate,
    required this.onCancel,
  });

  final UnitCategory category;
  final ValueChanged<UnitCategory> onCategoryChanged;
  final VoidCallback onCreate;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.itemCreateCategoryPrompt,
          style: AlayaTypography.label.copyWith(color: context.semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        SegmentedButton<UnitCategory>(
          segments: [
            for (final option in UnitCategory.values)
              ButtonSegment(
                value: option,
                label: Text(
                  _LineItemEditorState._categoryLabel(strings, option),
                ),
              ),
          ],
          selected: {category},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onCategoryChanged(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onCreate,
                child: Text(strings.itemCreate),
              ),
            ),
            const SizedBox(width: AlayaSpacing.xs),
            TextButton(onPressed: onCancel, child: Text(strings.actionCancel)),
          ],
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/sheets/quick_add_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';
import 'package:alaya/shared/widgets/tag_chip.dart';

/// Captures a transaction in one field (ARCH_5 §3 archetype A).
///
/// **The amount is the only required field, and everything else is a chip.** This sheet is used at a
/// till, one-handed, in under eight seconds — a column of dropdowns would make it a form nobody
/// fills in at a checkout, and the row would simply not get recorded. Every other field has a
/// defensible default and the row is saved `needsReview`, which is what makes the shortcut honest
/// rather than lossy (Law U11, ARCH_5 §7.2).
///
/// Chips rather than pickers for the same reason: a chip row shows the current choice *and* the
/// likely alternatives without a tap, where a dropdown hides both behind one.
class QuickAddSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const QuickAddSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => const QuickAddSheet(),
  );

  Future<void> _save(
    BuildContext context,
    WidgetRef ref, {
    required bool thenEdit,
  }) async {
    final strings = AlayaStrings.of(context);
    final navigator = Navigator.of(context);
    final messengerContext = context;
    final created = await ref.read(quickAddProvider.notifier).submit();
    if (created == null) return;
    if (navigator.canPop()) navigator.pop();
    if (!messengerContext.mounted) return;

    if (thenEdit) {
      messengerContext.push(Routes.transactionEdit(created.id));
      return;
    }
    showUndoSnack(
      messengerContext,
      message: strings.actionSaved,
      undoLabel: strings.actionUndo,
      onUndo: () => ref.read(quickAddProvider.notifier).undo(created.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final state = ref.watch(quickAddProvider);
    final notifier = ref.read(quickAddProvider.notifier);
    final currency = ref.watch(homeCurrencyCodeProvider).valueOrNull ?? 'INR';
    final digits = ref.watch(homeDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];
    final tags = ref.watch(quickAddTagsProvider).valueOrNull ?? const <Tag>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.quickAddTitle,
          style: AlayaTypography.cardTitle.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        SegmentedButton<TransactionKind>(
          segments: [
            ButtonSegment(
              value: TransactionKind.withdrawal,
              label: Text(strings.quickAddMoneyOut),
            ),
            ButtonSegment(
              value: TransactionKind.deposit,
              label: Text(strings.quickAddMoneyIn),
            ),
          ],
          selected: {state.kind},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => notifier.setKind(selection.first),
        ),
        const SizedBox(height: AlayaSpacing.md),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: AmountField(
            currencyCode: currency,
            decimalDigits: digits,
            label: strings.labelAmount,
            errorText: state.amountMissing ? strings.errorAmountInvalid : null,
            onChanged: notifier.setAmount,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Directly under the amount, because that is the order the thought arrives in:** two hundred,
        // for the birthday cake. A tag says *groceries* and is what you filter by later; this says which
        // row was which, and the only moment anybody knows it is now.
        //
        // One line, no label, hint as the question. A labelled multi-line box would be a fifth control
        // demanding attention in a sheet built to be finished in eight seconds — this one can be ignored
        // entirely without ever looking like an unanswered field.
        TextFormField(
          initialValue: state.note,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(hintText: strings.quickAddNoteHint),
          onChanged: notifier.setNote,
        ),
        if (accounts.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelAccount,
            children: [
              for (final account in accounts)
                _Choice(
                  label: account.name,
                  selected: state.accountId == account.id,
                  onTap: () => notifier.setAccount(account.id),
                ),
            ],
          ),
        ],
        if (tags.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          _ChipRow(
            label: strings.labelTags,
            children: [
              for (final tag in tags)
                TagChip(
                  tag: tag,
                  selected: state.tagId == tag.id,
                  onTap: () => notifier.toggleTag(tag.id),
                ),
            ],
          ),
        ],
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: state.submitting
              ? null
              : () => _save(context, ref, thenEdit: false),
          child: Text(strings.quickAddSave),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: state.submitting
              ? null
              : () => _save(context, ref, thenEdit: true),
          child: Text(strings.actionAddDetails),
        ),
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AlayaTypography.label.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: children,
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}
```

### `lib/features/expense/presentation/sheets/split_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/split_group.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';
import 'package:alaya/features/expense/state/split_draft.dart';
import 'package:alaya/features/settings/presentation/sheets/payee_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';

/// Splitting the expense the editor is already recording (ARCH_5 §3 archetype A).
///
/// **The second way in, not the only one.** `SplitBillScreen` is for "I want to split something";
/// this is for "I am recording an expense that happens to be shared", which is a different intent
/// arriving from a different place. Both produce the same rows.
///
/// **Both paths offer the same arithmetic, and for one release they did not.** This sheet could not
/// express an extra — "Ravi's drinks were ₹400" — while the split screen could, so the same bill
/// split differently depending on which door you came through. Two capabilities behind one model is
/// how a feature becomes folklore about which screen to use.
///
/// **Reads the split module's providers, not the expense editor's.** `transaction_editor_providers`
/// grew its own `splitPayeesProvider`, `splitGroupsProvider` and `splitSelfPayeeProvider` in session
/// 5, and session 6 added `splitPeopleProvider`, `splitAllGroupsProvider` and `splitSelfProvider`
/// without noticing — six providers answering three questions, which is the duplication ARCH_M §6
/// exists to forbid. The three in the expense feature have no callers now and should be deleted.
///
/// Returns content only — no `SafeArea`, no `viewInsets` padding, no scroll view. `AlayaBottomSheet`
/// owns all three, and its doc records that a sheet adding its own reintroduces an overflow that
/// appears the instant a keyboard opens.
class SplitSheet extends ConsumerStatefulWidget {
  /// Edits [draft], or starts a new split of [total].
  const SplitSheet({
    required this.total,
    required this.decimalDigits,
    this.draft,
    super.key,
  });

  /// What is being split. Null disables the sheet entirely — see [show].
  final Money? total;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// The split being edited, or null for a new one.
  final SplitDraft? draft;

  /// Opens the sheet, resolving to the edited draft or null when dismissed.
  static Future<SplitDraft?> show(
    BuildContext context, {
    required Money? total,
    required int decimalDigits,
    SplitDraft? draft,
  }) => AlayaBottomSheet.show<SplitDraft>(
    context: context,
    builder: (context) => SplitSheet(
      total: total,
      decimalDigits: decimalDigits,
      draft: draft,
    ),
  );

  @override
  ConsumerState<SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends ConsumerState<SplitSheet> {
  late SplitMethod _method = widget.draft?.method ?? SplitMethod.equal;
  late String? _groupId = widget.draft?.groupId;
  late DateKey? _settleBy = widget.draft?.settleByDateKey;

  /// Who is on the split, in the order they were added.
  late final List<String> _payeeIds = [...?widget.draft?.payeeIds];

  /// The typed value per person — a weight, basis points, or minor units, by method.
  ///
  /// **Kept across a method change rather than cleared.** Switching from shares to percent and back
  /// must not lose the weights somebody just entered; the values are only *interpreted* differently.
  late final Map<String, int> _values = {
    for (final input in widget.draft?.inputs ?? const <ShareInput>[])
      if (input.value != null && input.kind != ShareInputKind.extra)
        input.payeeId: input.value!,
  };

  /// What each person is charged on top of their share.
  late final Map<String, int> _extras = {
    for (final input in widget.draft?.inputs ?? const <ShareInput>[])
      if (input.kind == ShareInputKind.extra && input.value != null)
        input.payeeId: input.value!,
  };

  SplitDraft _draft(String selfPayeeId) => SplitDraft(
    paidByPayeeId: selfPayeeId,
    method: _method,
    groupId: _groupId,
    settleByDateKey: _settleBy,
    inputs: [for (final id in _payeeIds) _inputFor(id)],
  );

  ShareInput _inputFor(String payeeId) {
    // An extra wins over the method, and that is not a conflict: an extra says what somebody owes on
    // top, the method says how the rest divides, and `ShareInputKind.extra` means exactly "this plus
    // an ordinary share of the remainder".
    final extra = _extras[payeeId];
    if (extra != null && extra > 0) return ShareInput.extra(payeeId, extra);
    return switch (_method) {
      SplitMethod.equal => ShareInput.equal(payeeId),
      SplitMethod.shares => ShareInput.shares(payeeId, _values[payeeId] ?? 1),
      SplitMethod.percent => ShareInput.percent(payeeId, _values[payeeId] ?? 0),
      SplitMethod.exactAmounts => ShareInput.exact(
        payeeId,
        _values[payeeId] ?? 0,
      ),
      // Itemised splits are built from the transaction's own lines, not from this sheet. Named so
      // adding an enum member breaks here rather than falling through — Law L13.
      SplitMethod.perLine => ShareInput.equal(payeeId),
    };
  }

  /// Applies a group: its members become the participants, and its weights the values.
  void _applyGroup(SplitGroup? group) {
    setState(() {
      _groupId = group?.id;
      if (group == null) return;
      _payeeIds
        ..clear()
        ..addAll([for (final member in group.members) member.payeeId]);
      _extras.clear();
      final weights = group.defaultWeightsByPayee;
      if (weights == null) {
        // A partial set of weights prefills nothing: treating an unweighted member as weightless would
        // invent an instruction — "she did not eat" is a real thing to mean and must never be inferred
        // from a blank field.
        _method = SplitMethod.equal;
        _values.clear();
        return;
      }
      _method = SplitMethod.shares;
      _values
        ..clear()
        ..addAll(weights);
    });
  }

  void _toggle(String payeeId) => setState(() {
    if (_payeeIds.remove(payeeId)) {
      _values.remove(payeeId);
      _extras.remove(payeeId);
      return;
    }
    _payeeIds.add(payeeId);
  });

  /// Adds somebody and puts them on the split.
  ///
  /// `AddPersonSheet` rather than `PayeeSheet`: the shared sheet defaults to `PayeeKind.merchant`, so
  /// anybody added here was filed as a shop and never appeared in `splitPeopleProvider`. It also
  /// returns the id, which removes the diff-the-stream-afterwards race the old version had.
  Future<void> _addPerson() async {
    final created = await AddPersonSheet.show(context);
    if (created == null || !mounted) return;
    setState(() => _payeeIds.add(created));
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final total = widget.total;

    // The amount is what there is to divide, so without one there is nothing to do here. Said rather
    // than shown as a disabled form, because a screen full of inert controls explains nothing.
    if (total == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AlayaSpacing.xl),
        child: Text(
          strings.splitNeedsAmount,
          style: AlayaTypography.body.copyWith(color: semantic.muted),
        ),
      );
    }

    final people =
        ref.watch(splitPeopleProvider).valueOrNull ?? const <Payee>[];
    final groups =
        ref.watch(splitAllGroupsProvider).valueOrNull ?? const <SplitGroup>[];
    final self = ref.watch(splitSelfProvider).valueOrNull;

    final draft = self == null ? null : _draft(self);
    final resolution = draft?.resolve(total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(strings.splitSheetTitle, style: AlayaTypography.sectionHeader),

        if (groups.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          DropdownButtonFormField<String?>(
            key: ValueKey(_groupId),
            initialValue: _groupId,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.splitGroupLabel),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(strings.splitGroupNone),
              ),
              for (final group in groups)
                DropdownMenuItem(value: group.id, child: Text(group.name)),
            ],
            onChanged: (id) => _applyGroup(
              id == null ? null : groups.firstWhere((g) => g.id == id),
            ),
          ),
        ],

        SectionHeader(
          label: strings.splitPickPeople,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final payee in people)
              FilterChip(
                label: Text(payee.name),
                selected: _payeeIds.contains(payee.id),
                onSelected: (_) => _toggle(payee.id),
              ),
            ActionChip(
              avatar: const Icon(
                Icons.person_add_outlined,
                size: AlayaIconSize.sm,
              ),
              label: Text(strings.splitAddPerson),
              onPressed: _addPerson,
            ),
          ],
        ),

        if (_payeeIds.isNotEmpty) ...[
          const SizedBox(height: AlayaSpacing.md),
          DatePickerField(
            value: _settleBy,
            label: strings.splitSettleByLabel,
            hint: strings.splitSettleByHint,
            // A deadline in the past emits a calendar event that is overdue the moment it is created,
            // which `CalendarAggregator` renders as a warning on a split nobody has had a chance to
            // settle.
            firstDate: ref.read(splitTodayProvider),
            formatted: (date) => date.fullLabel,
            onChanged: (date) => setState(() => _settleBy = date),
          ),

          const SizedBox(height: AlayaSpacing.lg),
          SegmentedButton<SplitMethod>(
            segments: [
              ButtonSegment(
                value: SplitMethod.equal,
                label: Text(strings.splitMethodEqual),
              ),
              ButtonSegment(
                value: SplitMethod.shares,
                label: Text(strings.splitMethodShares),
              ),
              ButtonSegment(
                value: SplitMethod.percent,
                label: Text(strings.splitMethodPercent),
              ),
              ButtonSegment(
                value: SplitMethod.exactAmounts,
                label: Text(strings.splitMethodExact),
              ),
            ],
            selected: {_method},
            showSelectedIcon: false,
            onSelectionChanged: (choice) =>
                setState(() => _method = choice.first),
          ),

          const SizedBox(height: AlayaSpacing.md),
          for (final payeeId in _payeeIds)
            _ShareRow(
              name: _nameOf(people, payeeId, strings),
              method: _method,
              currencyCode: total.currencyCode,
              decimalDigits: widget.decimalDigits,
              value: _values[payeeId],
              extra: _extras[payeeId],
              resolved: _shareOf(resolution, payeeId),
              onValue: (value) => setState(() {
                value == null
                    ? _values.remove(payeeId)
                    : _values[payeeId] = value;
              }),
              onExtra: (value) => setState(() {
                value == null || value == 0
                    ? _extras.remove(payeeId)
                    : _extras[payeeId] = value;
              }),
            ),

          if (resolution != null && !resolution.isExact) ...[
            const SizedBox(height: AlayaSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // Never auto-balanced, exactly as `LineItemsSection` refuses to: forcing the shares to
                // equal the total would charge somebody for a discrepancy nobody told them about.
                label: resolution.isOverAllocated
                    ? strings.splitOverAllocated
                    : strings.splitUnallocated,
                tone: StatusTone.warning,
                trailing: AmountText(
                  resolution.unallocated.abs(),
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: widget.decimalDigits,
                ),
              ),
            ),
          ],
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          // Disabled until the module knows who the user is. Without `split.selfPayeeId` nothing can
          // say which side of the debt they are on, so every balance would be a guess.
          onPressed: draft == null
              ? null
              : () => Navigator.of(context).pop(draft),
          child: Text(strings.splitApply),
        ),
        if (self == null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Text(
            strings.splitSelfPayeeUnset,
            style: AlayaTypography.caption.copyWith(color: semantic.warning),
          ),
        ],
      ],
    );
  }

  static String _nameOf(
    List<Payee> people,
    String payeeId,
    AlayaStrings strings,
  ) {
    for (final payee in people) {
      if (payee.id == payeeId) return payee.name;
    }
    return strings.splitUnknownPerson;
  }

  static ResolvedShare? _shareOf(SplitResolution? r, String payeeId) {
    if (r == null) return null;
    for (final share in r.shares) {
      if (share.payeeId == payeeId) return share;
    }
    return null;
  }
}

/// One participant: their name, whatever the method asks for, their extra, and what it comes to.
class _ShareRow extends StatefulWidget {
  const _ShareRow({
    required this.name,
    required this.method,
    required this.currencyCode,
    required this.decimalDigits,
    required this.value,
    required this.extra,
    required this.resolved,
    required this.onValue,
    required this.onExtra,
  });

  final String name;
  final SplitMethod method;
  final String currencyCode;
  final int decimalDigits;
  final int? value;
  final int? extra;
  final ResolvedShare? resolved;
  final ValueChanged<int?> onValue;
  final ValueChanged<int?> onExtra;

  @override
  State<_ShareRow> createState() => _ShareRowState();
}

class _ShareRowState extends State<_ShareRow> {
  late bool _showExtra = (widget.extra ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final resolved = widget.resolved;

    return Padding(
      padding: const EdgeInsets.only(bottom: AlayaSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A `Wrap`, not a `Row`: a name, a field and an amount side by side overflow at 320dp with
          // the text scaler doubled, which is the gate every screen has to pass (Law U15).
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AlayaSpacing.sm,
            runSpacing: AlayaSpacing.xs,
            children: [
              SizedBox(
                width: 110,
                child: Text(
                  widget.name,
                  style: AlayaTypography.body,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.method == SplitMethod.exactAmounts)
                SizedBox(
                  width: 130,
                  child: AmountField(
                    currencyCode: widget.currencyCode,
                    decimalDigits: widget.decimalDigits,
                    label: strings.splitShareAmount,
                    initialValue: widget.value == null
                        ? null
                        : Money(widget.value!, widget.currencyCode),
                    onChanged: (money) => widget.onValue(money?.minor),
                  ),
                )
              else if (widget.method != SplitMethod.equal)
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: _weightText,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: widget.method == SplitMethod.percent
                          ? strings.splitSharePercent
                          : strings.splitShareWeight,
                      suffixText: widget.method == SplitMethod.percent
                          ? '%'
                          : null,
                    ),
                    onChanged: (text) => widget.onValue(_parseWeight(text)),
                  ),
                ),
              if (resolved != null)
                AmountText(
                  resolved.amount,
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: widget.decimalDigits,
                ),
              if (!_showExtra)
                TextButton.icon(
                  onPressed: () => setState(() => _showExtra = true),
                  icon: const Icon(Icons.add, size: AlayaIconSize.sm),
                  label: Text(strings.splitAddExtra),
                ),
            ],
          ),

          if (_showExtra)
            Padding(
              padding: const EdgeInsets.only(
                left: AlayaSpacing.md,
                top: AlayaSpacing.xs,
              ),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AlayaSpacing.sm,
                runSpacing: AlayaSpacing.xs,
                children: [
                  SizedBox(
                    width: 150,
                    child: AmountField(
                      currencyCode: widget.currencyCode,
                      decimalDigits: widget.decimalDigits,
                      label: strings.splitExtraLabel,
                      initialValue: widget.extra == null
                          ? null
                          : Money(widget.extra!, widget.currencyCode),
                      onChanged: (money) => widget.onExtra(money?.minor),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() => _showExtra = false);
                      widget.onExtra(null);
                    },
                    tooltip: strings.splitRemoveExtra,
                    icon: Icon(
                      Icons.close,
                      size: AlayaIconSize.md,
                      color: semantic.muted,
                    ),
                  ),
                ],
              ),
            ),

          // **The arithmetic, spelled out.** "₹1,150 + ₹400 just for them" rather than a bare ₹1,550 —
          // a total somebody cannot decompose is one they argue with.
          if (resolved?.extra != null && resolved?.fromRemainder != null)
            Padding(
              padding: const EdgeInsets.only(left: AlayaSpacing.md),
              child: Text(
                strings.splitShareBreakdown(
                  _plain(resolved!.fromRemainder!),
                  _plain(resolved.extra!),
                ),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
        ],
      ),
    );
  }

  /// Basis points shown as whole percent — 2500 reads as `25`.
  ///
  /// Basis points are what the schema stores, because an integer keeps Law L1 intact; a percent sign
  /// is what a person types. The conversion lives here, at the one boundary between them.
  String get _weightText {
    final value = widget.value;
    if (value == null) return '';
    return widget.method == SplitMethod.percent
        ? (value ~/ 100).toString()
        : value.toString();
  }

  int? _parseWeight(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null) return null;
    return widget.method == SplitMethod.percent ? parsed * 100 : parsed;
  }

  /// A bare figure for the breakdown sentence.
  ///
  /// The one place this sheet renders money without `AmountText`, because the string is interpolated
  /// into a sentence the ARB owns. Law U7's single path to pixels is for figures a reader compares;
  /// this is prose, and an `AmountText` inside it would fight the caption style around it.
  String _plain(Money money) {
    final divisor = widget.decimalDigits == 0 ? 1 : 100;
    final whole = money.minor ~/ divisor;
    final frac = money.minor % divisor;
    return widget.decimalDigits == 0
        ? '$whole'
        : '$whole.${frac.toString().padLeft(widget.decimalDigits, '0')}';
  }
}
```

### `lib/features/expense/presentation/widgets/line_items_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/sheets/line_item_editor.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/qty_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The "what you bought" section, shared by every sub-form that itemises (ARCH_5 §4).
///
/// One widget rather than one per sub-form: grocery, household, electronics and other all itemise
/// identically, and four copies is how one component becomes four that drift (ARCH_4 R25). Only the
/// default destination differs, so that is the parameter.
///
/// **The unallocated chip is never auto-balanced.** The transaction amount is the source of truth
/// and the lines are optional detail; forcing them equal would invent a line the user did not buy
/// (anomaly A11). Note the chip appears only when lines exist — with none at all, "unallocated"
/// equals the whole amount, which is not a mismatch.
class LineItemsSection extends ConsumerWidget {
  /// Creates the section for [state], defaulting new lines to [defaultDestination].
  const LineItemsSection({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    this.defaultDestination = TransactionLineDestination.inventory,
    super.key,
  });

  /// The editor family argument, so the section writes to the right notifier.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  /// What a new line starts as.
  final TransactionLineDestination defaultDestination;

  /// Opens the dedicated items page.
  ///
  /// **A page, not the sheet.** Adding one line at a time through a sheet meant a fifteen-item receipt
  /// was fifteen open-close cycles with no view of what had been entered. The page keeps the list, the
  /// running total and the add action on screen together; the sheet is still what edits a single line,
  /// reached from there.
  void _openItems(BuildContext context) =>
      context.push(Routes.transactionLines(state.id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final unallocated = state.unallocated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.sectionWhatYouBought,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        for (final line in state.lines)
          AlayaCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.sm,
              vertical: AlayaSpacing.xs,
            ),
            onTap: () async {
              final edited = await LineItemEditor.show(
                context,
                currencyCode: state.currencyCode,
                decimalDigits: decimalDigits,
                defaultDestination: defaultDestination,
                line: line,
              );
              if (edited != null) notifier.upsertLine(edited.line);
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.description, style: AlayaTypography.body),
                      if (line.quantity != null) ...[
                        const SizedBox(height: AlayaSpacing.xxs),
                        QtyText(line.quantity!, muted: true),
                      ],
                    ],
                  ),
                ),
                if (line.lineAmount != null)
                  AmountText(
                    line.lineAmount!,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                  ),
                IconButton(
                  onPressed: () => notifier.removeLine(line.id),
                  tooltip: strings.actionDelete,
                  icon: Icon(
                    Icons.close,
                    size: AlayaIconSize.md,
                    color: semantic.muted,
                  ),
                ),
              ],
            ),
          ),
        if (unallocated != null) ...[
          const SizedBox(height: AlayaSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: strings.statusUnallocated,
              tone: StatusTone.warning,
              // Through `AmountText`, not `minor.toString()`. `Money` is minor units, so the old call
              // put `200000` on screen for two thousand rupees (Law U7).
              trailing: AmountText(
                unallocated.abs(),
                size: AmountSize.small,
                showSign: false,
                decimalDigits: decimalDigits,
              ),
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _openItems(context),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(strings.lineAdd),
          ),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/needs_review_banner.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The nudge that surfaces `transactions.needsReview` (ARCH_5 §7.2).
///
/// Quick-add captures an amount and nothing else, which is the whole point of an optional-first
/// capture path (Law U11) — but a column that records "this is incomplete" and is never shown turns
/// a deliberate shortcut into silent data rot. This is the row that closes that loop.
///
/// Renders nothing at zero. A banner reading "0 transactions need details" is noise on every screen
/// where the user is already up to date.
class NeedsReviewBanner extends StatelessWidget {
  /// Creates the nudge for [count] transactions, opening the filtered list through [onTap].
  const NeedsReviewBanner({
    required this.count,
    required this.onTap,
    super.key,
  });

  /// How many transactions still need details.
  final int count;

  /// Shows them.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final strings = AlayaStrings.of(context);
    // Above roughly 1.5x, the message and the action cannot share a line at 320dp. The action is
    // non-flexible, so it takes its full natural width and leaves the message a column barely wider
    // than a character — which wrapped "2 transactions need details" to twenty-nine lines and made
    // this banner 1,084px tall, starving the ledger beneath it of every pixel (Law U15).
    //
    // Stacking is the fix rather than truncating: ellipsising the count is the one thing this nudge
    // cannot do, because the count *is* the message.
    final stacked = MediaQuery.textScalerOf(context).scale(1) >= 1.5;

    final message = Text(
      strings.needsReviewBanner(count),
      style: AlayaTypography.body.copyWith(color: theme.colorScheme.onSurface),
    );
    final action = Text(
      strings.needsReviewAction,
      style: AlayaTypography.button.copyWith(color: semantic.transfer),
    );
    final leading = Icon(
      Icons.edit_note,
      size: AlayaIconSize.md,
      color: semantic.transfer,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AlayaSpacing.screenEdge,
        AlayaSpacing.xs,
        AlayaSpacing.screenEdge,
        AlayaSpacing.xxs,
      ),
      child: Material(
        color: semantic.transfer.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: AlayaRadii.borderSm,
          side: BorderSide(color: semantic.transfer.withValues(alpha: 0.28)),
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
                vertical: AlayaSpacing.xs,
              ),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            leading,
                            const SizedBox(width: AlayaSpacing.xs),
                            Expanded(child: message),
                          ],
                        ),
                        const SizedBox(height: AlayaSpacing.xs),
                        action,
                      ],
                    )
                  : Row(
                      children: [
                        leading,
                        const SizedBox(width: AlayaSpacing.xs),
                        Expanded(child: message),
                        const SizedBox(width: AlayaSpacing.xs),
                        action,
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

### `lib/features/expense/presentation/widgets/payee_field.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// Picks a counterparty, and creates one inline when it does not exist yet.
///
/// **Inline creation rather than a trip to Settings.** A payee is discovered at the moment of
/// recording a purchase — you find out the shop is called "Reliance Fresh" while you are typing the
/// receipt, not before. Sending the user to a settings screen to add one guarantees the field is
/// left blank, and a blank payee is the column that makes "top payees by spend" useless.
///
/// One widget rather than one per sub-form: six of the seven need it, and six copies is how one
/// component becomes six that drift (ARCH_4 R25).
class PayeeField extends ConsumerStatefulWidget {
  /// Creates the field for the editor identified by [editorId].
  const PayeeField({
    required this.editorId,
    required this.selectedId,
    super.key,
  });

  /// The editor family argument, so the field writes to the right notifier.
  final String? editorId;

  /// The payee currently chosen.
  final String? selectedId;

  @override
  ConsumerState<PayeeField> createState() => _PayeeFieldState();
}

class _PayeeFieldState extends ConsumerState<PayeeField> {
  final TextEditingController _newName = TextEditingController();
  bool _creating = false;

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _newName.text.trim();
    if (name.isEmpty) return;
    final strings = AlayaStrings.of(context);
    final created = await ref
        .read(transactionEditorProvider(widget.editorId).notifier)
        .createPayee(name);
    if (!mounted) return;
    // **The field stays open on failure, holding what was typed.** Closing it and clearing the name
    // would discard the user's input and leave them with an empty picker and no explanation — which
    // reads as the app having quietly ignored them.
    if (!created) {
      showFailureSnack(context, message: strings.errorBodyGeneric);
      return;
    }
    _newName.clear();
    setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees =
        ref.watch(editorPayeesProvider).valueOrNull ?? const <Payee>[];
    final notifier = ref.read(
      transactionEditorProvider(widget.editorId).notifier,
    );

    Payee? current;
    for (final payee in payees) {
      if (payee.id == widget.selectedId) {
        current = payee;
        break;
      }
    }

    if (_creating) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: _newName,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(labelText: strings.labelPayee),
              onSubmitted: (_) => _create(),
            ),
          ),
          const SizedBox(width: AlayaSpacing.xs),
          TextButton(onPressed: _create, child: Text(strings.actionAdd)),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(current?.id),
            initialValue: current?.id,
            isExpanded: true,
            decoration: InputDecoration(labelText: strings.labelPayee),
            items: [
              for (final payee in payees)
                DropdownMenuItem(
                  value: payee.id,
                  child: Text(
                    payee.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: notifier.setPayee,
          ),
        ),
        const SizedBox(width: AlayaSpacing.xs),
        TextButton(
          onPressed: () => setState(() => _creating = true),
          child: Text(strings.actionAdd),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/split_section.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/sheets/split_sheet.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';
import 'package:alaya/features/split/providers/split_providers.dart';

/// The "who owes for this" section of the transaction editor.
///
/// **Built on `LineItemsSection`'s shape, not beside it.** That widget already solved this exact
/// problem for line items — a summary in the editor, a sheet for the detail, and a chip for what does
/// not add up — and its own doc records the rule this section inherits:
///
/// > The unallocated chip is **never auto-balanced**. The transaction amount is the source of truth
/// > and the lines are optional detail; forcing them equal would invent a line the user did not buy
/// > (anomaly A11).
///
/// Shares are the same problem with different nouns. Percentages that reach 90%, or a tip nobody
/// assigned, leave a remainder — and quietly rounding it onto the last participant would charge
/// somebody for a discrepancy nobody told them about.
///
/// **Not a second `AlayaDisclosure`.** `TransactionEditorScreen` carries a pointed comment about Law
/// U16 — *"one door, not five collapsed sections… eleven controls at once is what made this screen
/// hard to read"* — so this sits inline with a summary and puts its controls behind a sheet, which is
/// where line items already put theirs.
class SplitSection extends ConsumerWidget {
  /// Creates the section for [state].
  const SplitSection({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument, so the section writes to the right notifier.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final draft = await SplitSheet.show(
      context,
      total: state.amount,
      decimalDigits: decimalDigits,
      draft: state.split,
    );
    if (draft == null) return;
    ref
        .read(transactionEditorProvider(editorId).notifier)
        .setSplit(
          draft.isActive ? draft : null,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final split = state.split;
    final resolution = split?.resolve(state.amount);
    final people =
        ref.watch(splitParticipantsProvider).valueOrNull ?? const <Payee>[];

    String nameOf(String payeeId) {
      for (final payee in people) {
        if (payee.id == payeeId) return payee.name;
      }
      // A payee deleted while the editor was open. Better than a blank row, and rare enough that a
      // generic label is the right cost.
      return strings.splitUnknownPerson;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          label: strings.splitSectionHeader,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),

        if (resolution == null)
          // **Says what it does before it is used.** A bare "Split" button gives no account of itself,
          // and this is the one section of the editor whose purpose is not obvious from its label.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.amount == null
                  ? null
                  : () => _edit(context, ref),
              icon: const Icon(
                Icons.group_add_outlined,
                size: AlayaIconSize.md,
              ),
              label: Text(strings.splitAdd),
            ),
          )
        else ...[
          for (final share in resolution.shares)
            AlayaCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.sm,
                vertical: AlayaSpacing.xs,
              ),
              onTap: () => _edit(context, ref),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      nameOf(share.payeeId),
                      style: AlayaTypography.body,
                    ),
                  ),
                  // Through `AmountText`, never `minor.toString()` — Law U7, and the mistake
                  // `LineItemsSection` records having made, which put `200000` on screen for two
                  // thousand rupees.
                  AmountText(
                    share.amount,
                    size: AmountSize.small,
                    showSign: false,
                    decimalDigits: decimalDigits,
                  ),
                ],
              ),
            ),

          if (!resolution.isExact) ...[
            const SizedBox(height: AlayaSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: StatusChip(
                // Over-allocation and shortfall are different mistakes and read differently: "₹200
                // unassigned" is something to finish, "₹200 too much" is something to correct. One
                // label for both would describe neither.
                label: resolution.isOverAllocated
                    ? strings.splitOverAllocated
                    : strings.splitUnallocated,
                tone: StatusTone.warning,
                trailing: AmountText(
                  resolution.unallocated.abs(),
                  size: AmountSize.small,
                  showSign: false,
                  decimalDigits: decimalDigits,
                ),
              ),
            ),
          ],

          const SizedBox(height: AlayaSpacing.xs),
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _edit(context, ref),
                icon: const Icon(Icons.edit_outlined, size: AlayaIconSize.md),
                label: Text(strings.splitEdit),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => ref
                    .read(transactionEditorProvider(editorId).notifier)
                    .setSplit(null),
                tooltip: strings.splitRemove,
                icon: Icon(
                  Icons.close,
                  size: AlayaIconSize.md,
                  color: semantic.muted,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/bill_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/due_bills_providers.dart';
import 'package:alaya/features/recurring/providers/template_builder_providers.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_text.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// The bill payment sub-form.
///
/// A bill paid off-template is an ordinary withdrawal with `subtype = bill` and a null
/// `recurringTemplateId` — which is why this form never requires a template. Paying a bill you never
/// set up must not be harder than paying one you did.
///
/// **Selecting a due bill links this payment to it; it does not pay it here.** An earlier version
/// opened the pay sheet from this list, which left two write paths reachable at once: the sheet
/// recorded one transaction and then saving the editor recorded a second for the same payment. There
/// is now one amount field and one save — picking a bill routes that save through `payOccurrence`,
/// which settles the occurrence and writes the transaction together.
class BillForm extends ConsumerWidget {
  /// Creates the form.
  const BillForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final due = ref.watch(dueBillsProvider);
    final today = ref.watch(clockProvider).today();
    final digits = ref.watch(builderDecimalDigitsProvider).valueOrNull ?? 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.billDueSection,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        due.when(
          // A failed or pending schedule read costs the shortcut, never the ability to record a bill
          // by hand — which is what this form does without any of this.
          loading: () => Text(
            strings.loadingRecurring,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
          ),
          error: (error, stack) => Text(
            error.toString(),
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
          data: (rows) => rows.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.billNothingDue,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    TextButton.icon(
                      onPressed: () => context.push(Routes.recurringNew),
                      icon: const Icon(
                        Icons.event_repeat,
                        size: AlayaIconSize.sm,
                      ),
                      label: Text(strings.billSetUpAction),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.billSettleHelp,
                      style: AlayaTypography.caption.copyWith(
                        color: semantic.muted,
                      ),
                    ),
                    const SizedBox(height: AlayaSpacing.xs),
                    RadioGroup<String?>(
                      groupValue: state.recurringOccurrenceId,
                      onChanged: (value) {
                        if (value == null) {
                          notifier.setRecurringOccurrence();
                          return;
                        }
                        for (final row in rows) {
                          if (row.occurrence!.id != value) continue;
                          notifier.setRecurringOccurrence(
                            occurrenceId: value,
                            defaultAmount: row.template.defaultAmount,
                            accountId: ref.read(
                              resolvedBillAccountProvider(
                                row.template.defaultAccountId,
                              ),
                            ),
                          );
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          RadioListTile<String?>(
                            value: null,
                            contentPadding: EdgeInsets.zero,
                            title: Text(strings.billSettleNone),
                          ),
                          for (final row in rows)
                            RadioListTile<String?>(
                              value: row.occurrence!.id,
                              contentPadding: EdgeInsets.zero,
                              title: Text(row.template.name),
                              subtitle: Wrap(
                                spacing: AlayaSpacing.xs,
                                runSpacing: AlayaSpacing.xxs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  AmountText(
                                    row.template.defaultAmount,
                                    size: AmountSize.small,
                                    showSign: false,
                                    decimalDigits: digits,
                                  ),
                                  DateText(
                                    row.occurrence!.dueDateKey,
                                    style: DateTextStyle.medium,
                                    muted: true,
                                  ),
                                  if (row.occurrence!.isOverdue(today))
                                    StatusChip(
                                      label: strings.recurringOverdue,
                                      tone: StatusTone.danger,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.recurringOccurrenceId != null) ...[
                      const SizedBox(height: AlayaSpacing.xs),
                      Text(
                        strings.billAmountBecomesPaid,
                        style: AlayaTypography.caption.copyWith(
                          color: semantic.transfer,
                        ),
                      ),
                      // Only reached when the template, the app default and a sole account all failed
                      // to answer — so it is asked once and remembered on the bill, never per payment.
                      if (state.accountMissing) ...[
                        const SizedBox(height: AlayaSpacing.xs),
                        Text(
                          strings.billAccountAskOnce,
                          style: AlayaTypography.caption.copyWith(
                            color: semantic.danger,
                          ),
                        ),
                      ] else if (state.fromAccountId != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
                          child: Text(
                            strings.billAccountAuto,
                            style: AlayaTypography.caption.copyWith(
                              color: semantic.muted,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/deposit_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The deposit sub-form.
///
/// A deposit needs a destination account and no source — the mirror of a withdrawal, and the shape
/// the `transactions` CHECK constraint enforces (ARCH_2 §4.1). The payee is the *source* of the
/// money here rather than its recipient, which is why one `payees` table serves both directions.
class DepositForm extends ConsumerWidget {
  /// Creates the form.
  const DepositForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? selected;
    for (final account in accounts) {
      if (account.id == state.toAccountId) {
        selected = account;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: selected,
          label: strings.labelTo,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setToAccount(account.id),
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/electronics_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// The electronics purchase sub-form.
///
/// **Lines default to `destination = asset`, not inventory, and the inventory opt-in is explicit.**
/// A television is a durable, serviceable thing with a warranty and a service history — it is not
/// consumable stock. Pushing it to both modules is anomaly A12: neither then owns the truth about
/// what you actually have. The opt-in exists because a few things genuinely are both, and it is off
/// by default because most are not.
///
/// The warranty window is collected here rather than on the line, because `transaction_lines` has no
/// column for it. The editor applies it to the asset the fan-out plans.
class ElectronicsForm extends ConsumerWidget {
  /// Creates the form.
  const ElectronicsForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final localeTag = Localizations.localeOf(context).toString();
    String format(DateKey date) =>
        DateFormat.yMMMd(localeTag).format(date.toUtcMidnight());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PayeeField(editorId: editorId, selectedId: state.payeeId),
        SectionHeader(
          label: strings.sectionWarranty,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.xl,
            bottom: AlayaSpacing.xs,
          ),
        ),
        DatePickerField(
          value: state.warrantyStart,
          formatted: format,
          label: strings.labelFrom,
          hint: strings.hintSelectDate,
          onChanged: (date) =>
              notifier.setWarranty(start: date, end: state.warrantyEnd),
        ),
        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: state.warrantyEnd,
          formatted: format,
          label: strings.labelTo,
          hint: strings.hintSelectDate,
          onChanged: (date) =>
              notifier.setWarranty(start: state.warrantyStart, end: date),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        CheckboxListTile(
          value: state.alsoAddToInventory,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: Text(strings.alsoAddToInventory),
          onChanged: (value) =>
              notifier.setAlsoAddToInventory(value: value ?? false),
        ),
        LineItemsSection(
          editorId: editorId,
          state: state,
          decimalDigits: decimalDigits,
          defaultDestination: state.alsoAddToInventory
              ? TransactionLineDestination.inventory
              : TransactionLineDestination.asset,
        ),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/grocery_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The grocery purchase sub-form.
///
/// Lines default to `destination = inventory`: a grocery receipt is the single most common way stock
/// enters the house, and defaulting to anything else means the inventory module stays empty however
/// diligently the user records their spending.
class GroceryForm extends ConsumerWidget {
  /// Creates the form.
  const GroceryForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PayeeField(editorId: editorId, selectedId: state.payeeId),
      LineItemsSection(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
        defaultDestination: TransactionLineDestination.inventory,
      ),
    ],
  );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/household_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The household purchase sub-form.
///
/// Identical in shape to the grocery form, and deliberately a separate file rather than an alias:
/// the two subtypes exist because they land in different analytics buckets, and a single shared
/// widget invites the first divergence to be made by editing the other module's form.
class HouseholdForm extends ConsumerWidget {
  /// Creates the form.
  const HouseholdForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PayeeField(editorId: editorId, selectedId: state.payeeId),
      LineItemsSection(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
        defaultDestination: TransactionLineDestination.inventory,
      ),
    ],
  );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/other_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/features/expense/presentation/widgets/line_items_section.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// The catch-all withdrawal sub-form.
///
/// Lines default to `destination = none` and the chooser in the line editor is where the user says
/// otherwise. This is the form that can produce any of the three artefacts, which is why the
/// destination is a decision here rather than an assumption.
class OtherForm extends ConsumerWidget {
  /// Creates the form.
  const OtherForm({
    required this.editorId,
    required this.state,
    required this.decimalDigits,
    super.key,
  });

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  /// The currency's minor-unit precision.
  final int decimalDigits;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PayeeField(editorId: editorId, selectedId: state.payeeId),
      LineItemsSection(
        editorId: editorId,
        state: state,
        decimalDigits: decimalDigits,
        defaultDestination: TransactionLineDestination.none,
      ),
    ],
  );
}
```

### `lib/features/expense/presentation/widgets/subtype_forms/transfer_form.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/payee_field.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/account_picker.dart';

/// The transfer sub-form — and the one place in this app where the copy has to be exact.
///
/// **"To my own account" and "To someone else" are different transaction kinds, not two phrasings
/// of one.** Moving ₹5,000 from Cash to Bank must not reduce net worth: it is `kind = transfer`,
/// it appears in both accounts' ledgers with opposite signs, and it nets to zero by construction.
/// Sending ₹5,000 to your brother is a real withdrawal with `subtype = transferOut` and a payee.
///
/// Getting this wrong is anomaly A02, and the symptom is a net worth that falls every time the user
/// moves their own money between their own accounts — a number they cannot explain and will not
/// trust again.
class TransferForm extends ConsumerWidget {
  /// Creates the form.
  const TransferForm({required this.editorId, required this.state, super.key});

  /// The editor family argument.
  final String? editorId;

  /// The editor's current state.
  final TransactionEditorState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final notifier = ref.read(transactionEditorProvider(editorId).notifier);
    final accounts =
        ref.watch(selectableAccountsProvider).valueOrNull ?? const <Account>[];

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: true, label: Text(strings.transferOwnAccount)),
            ButtonSegment(
              value: false,
              label: Text(strings.transferSomeoneElse),
            ),
          ],
          selected: {state.toOwnAccount},
          showSelectedIcon: false,
          onSelectionChanged: (selection) =>
              notifier.setTransferTarget(toOwnAccount: selection.first),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          state.toOwnAccount
              ? strings.transferOwnAccountHelp
              : strings.transferSomeoneElseHelp,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.md),
        AccountPicker(
          accounts: accounts,
          selected: accountFor(state.fromAccountId),
          label: strings.labelFrom,
          hint: strings.hintSelectAccount,
          onChanged: (account) => notifier.setFromAccount(account.id),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.toOwnAccount)
          AccountPicker(
            accounts: accounts,
            selected: accountFor(state.toAccountId),
            label: strings.labelTo,
            hint: strings.hintSelectAccount,
            // Excluded so a transfer cannot have the same account on both sides, which the
            // transactions CHECK constraint rejects anyway (ARCH_2 §4.1).
            excludeId: state.fromAccountId,
            onChanged: (account) => notifier.setToAccount(account.id),
          )
        else
          PayeeField(editorId: editorId, selectedId: state.payeeId),
      ],
    );
  }
}
```

### `lib/features/expense/presentation/widgets/transaction_filter_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Narrows the transaction list (ARCH_5 §3 archetype A).
///
/// Chips rather than dropdowns throughout. A filter sheet is read at a glance and closed — a column
/// of dropdowns hides the current state behind six taps, which is the opposite of what a sheet whose
/// whole job is "show me what is on" should do.
///
/// **There is no tag filter.** No 3A contract exposes a tag-to-transactions reverse lookup, so it
/// would cost one query per visible row. Recorded as an ARCH_5 §7.3 gap owned by 7B, which builds
/// the analytics read model that needs the same join.
class TransactionFilterSheet extends ConsumerWidget {
  /// Creates the sheet. Prefer [show].
  const TransactionFilterSheet({super.key});

  /// Opens the sheet.
  static Future<void> show(BuildContext context) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) => const TransactionFilterSheet(),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final theme = Theme.of(context);
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final accounts =
        ref.watch(accountsByIdProvider).valueOrNull ??
        const <String, Account>{};

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                strings.filterTitle,
                style: AlayaTypography.cardTitle.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            if (filter.isNarrowed)
              TextButton(
                onPressed: notifier.clear,
                child: Text(strings.filterReset),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterDateRange,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final preset in DateRangePreset.values)
              if (preset != DateRangePreset.custom)
                _Choice(
                  label: rangeLabel(strings, preset),
                  selected: filter.preset == preset,
                  onTap: () => notifier.setPreset(preset),
                ),
          ],
        ),
        SectionHeader(
          label: strings.filterKind,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in TransactionKind.values)
              _Choice(
                label: TransactionRow.kindLabel(strings, kind),
                selected: filter.kinds.contains(kind),
                onTap: () => notifier.toggleKind(kind),
              ),
          ],
        ),
        SectionHeader(
          label: strings.filterSubtype,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final subtype in TransactionSubtype.values)
              _Choice(
                label: TransactionRow.subtypeLabel(strings, subtype),
                selected: filter.subtypes.contains(subtype),
                onTap: () => notifier.toggleSubtype(subtype),
              ),
          ],
        ),
        SectionHeader(
          label: strings.labelAccount,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.md,
            bottom: AlayaSpacing.xs,
          ),
        ),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final account in accounts.values)
              _Choice(
                label: account.name,
                selected: filter.accountId == account.id,
                onTap: () => notifier.setAccount(
                  filter.accountId == account.id ? null : account.id,
                ),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.xl),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.filterApply),
        ),
      ],
    );
  }

  /// The localised name of a range preset. Static so the chip bar reads the same mapping.
  static String rangeLabel(AlayaStrings strings, DateRangePreset preset) =>
      switch (preset) {
        DateRangePreset.today => strings.rangeToday,
        DateRangePreset.last7Days => strings.rangeLast7Days,
        DateRangePreset.last30Days => strings.rangeLast30Days,
        DateRangePreset.thisMonth => strings.rangeThisMonth,
        DateRangePreset.lastMonth => strings.rangeLastMonth,
        DateRangePreset.thisYear => strings.rangeThisYear,
        DateRangePreset.allTime => strings.rangeAllTime,
        DateRangePreset.custom => strings.rangeCustom,
      };
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
  );
}
```

### `lib/features/expense/presentation/widgets/transaction_row.dart`

```dart
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
```

### `lib/features/expense/providers/quick_add_providers.dart`

```dart
/// View-model state for the quick-add sheet (ARCH_5 U19).
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// What the quick-add sheet is holding.
class QuickAddState {
  /// Creates the sheet's state.
  const QuickAddState({
    this.kind = TransactionKind.withdrawal,
    this.amount,
    this.accountId,
    this.tagId,
    this.note,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
  });

  /// Money out by default: an expense tracker is opened to record spending far more often than
  /// income, and defaulting to the rarer case costs a tap every single time.
  final TransactionKind kind;

  /// The typed amount, null while it does not parse. The one required field (Law U11).
  final Money? amount;

  /// The chosen account. Null lets the repository fill it from last-used, then the default.
  final String? accountId;

  /// An optional tag.
  final String? tagId;

  /// What the money was for, in the user's own words.
  ///
  /// **Optional, and the reason it belongs in a five-control sheet.** A tag says *groceries*; a note says
  /// *the birthday cake*. Three months later the tag is what you filter by and the note is what tells you
  /// which row was which — and the moment you actually know is at the till, not when you come back to tidy
  /// up. Law U11 keeps it optional; leaving it out of the quick path would mean the one detail nobody can
  /// reconstruct later is the one the fast route drops.
  final String? note;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field. An int rather than a bool so two consecutive rejections
  /// shake twice — a bool already true produces no change and reads as the app ignoring the tap.
  final int shakeTrigger;

  /// Whether the sheet holds anything worth confirming before a dismissal.
  bool get isDirty => amount != null || tagId != null;

  /// Returns a copy with the supplied changes.
  QuickAddState copyWith({
    TransactionKind? kind,
    Money? amount,
    bool clearAmount = false,
    String? accountId,
    String? tagId,
    bool clearTag = false,
    String? note,
    bool clearNote = false,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
  }) => QuickAddState(
    kind: kind ?? this.kind,
    amount: clearAmount ? null : (amount ?? this.amount),
    accountId: accountId ?? this.accountId,
    tagId: clearTag ? null : (tagId ?? this.tagId),
    note: clearNote ? null : (note ?? this.note),
    submitting: submitting ?? this.submitting,
    amountMissing: amountMissing ?? this.amountMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
  );
}

/// The quick-add sheet's view model.
final quickAddProvider =
    NotifierProvider.autoDispose<QuickAddNotifier, QuickAddState>(
      QuickAddNotifier.new,
    );

/// Captures an amount and as little else as the user is willing to give (Law U11).
class QuickAddNotifier extends AutoDisposeNotifier<QuickAddState> {
  @override
  QuickAddState build() => const QuickAddState();

  /// Switches between money in and money out.
  void setKind(TransactionKind kind) => state = state.copyWith(kind: kind);

  /// Records the parsed amount, clearing any outstanding "enter an amount" message.
  void setAmount(Money? amount) => state = amount == null
      ? state.copyWith(clearAmount: true)
      : state.copyWith(amount: amount, amountMissing: false);

  /// Chooses the account the money moves through.
  void setAccount(String accountId) =>
      state = state.copyWith(accountId: accountId);

  /// Sets what the money was for. Empty clears it.
  void setNote(String value) {
    final trimmed = value.trim();
    state = trimmed.isEmpty
        ? state.copyWith(clearNote: true)
        : state.copyWith(note: trimmed);
  }

  /// Applies or removes the optional tag.
  void toggleTag(String tagId) => state = state.tagId == tagId
      ? state.copyWith(clearTag: true)
      : state.copyWith(tagId: tagId);

  /// Saves, returning the created transaction, or null when the form was rejected.
  ///
  /// Marks the row `needsReview` so the nudge can offer it back later: capturing an amount and
  /// nothing else is the point of this sheet, and the flag is what stops that shortcut becoming
  /// silent data rot (ARCH_5 §7.2).
  Future<Transaction?> submit() async {
    final amount = state.amount;
    if (amount == null) {
      state = state.copyWith(
        amountMissing: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return null;
    }
    state = state.copyWith(submitting: true);

    final clock = ref.read(clockProvider);
    final isDeposit = state.kind == TransactionKind.deposit;
    final transaction = Transaction(
      id: ref.read(uidGeneratorProvider).generate(),
      kind: state.kind,
      subtype: isDeposit
          ? TransactionSubtype.otherIn
          : TransactionSubtype.otherOut,
      occurredAtUtc: clock.now().toUtc(),
      dateKey: clock.today(),
      originalAmount: amount,
      needsReview: true,
      fromAccountId: isDeposit ? null : state.accountId,
      toAccountId: isDeposit ? state.accountId : null,
      note: state.note,
    );

    final tagId = state.tagId;
    final result = await ref
        .read(transactionRepositoryProvider)
        .create(
          transaction: transaction,
          tagIds: [if (tagId != null) tagId],
        );
    state = state.copyWith(submitting: false);
    return result.valueOrNull;
  }

  /// Removes a transaction this sheet created, for the snack bar's Undo.
  Future<void> undo(String id) async {
    await ref.read(transactionRepositoryProvider).delete(id: id);
  }
}

/// Tags offered in the sheet, scoped to the direction the user has chosen.
///
/// A tag scoped to withdrawals must not appear while the toggle says money in — "Kitchen" in the
/// deposit picker is the spec's own test case for the scoping matrix (ARCH_2 §14).
final quickAddTagsProvider = StreamProvider.autoDispose<List<Tag>>((ref) {
  final kind = ref.watch(quickAddProvider.select((s) => s.kind));
  final scope = kind == TransactionKind.deposit
      ? TagScope.deposit
      : TagScope.withdrawal;
  return ref.watch(tagRepositoryProvider).watchByScope(scope);
});
```

### `lib/features/expense/providers/transaction_detail_providers.dart`

```dart
/// View-model providers for one transaction's detail screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/repositories/transaction_repository.dart';

/// One transaction, re-read whenever it changes.
///
/// A `StreamProvider` over the date-range watch would be the wrong shape here — the detail screen
/// wants one row, and `byId` is a future. It is invalidated explicitly after a write instead.
final transactionByIdProvider = FutureProvider.autoDispose
    .family<Transaction?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).byId(id),
    );

/// The lines itemising one transaction, in entry order.
final transactionLinesProvider = StreamProvider.autoDispose
    .family<List<TransactionLine>, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).watchLines(id),
    );

/// One transaction's allocation summary, for the unallocated chip.
final transactionAllocationProvider = StreamProvider.autoDispose
    .family<TransactionAllocation?, String>(
      (ref, id) => ref.watch(transactionRepositoryProvider).watchAllocation(id),
    );

/// The tags applied to one transaction.
final transactionTagsProvider = StreamProvider.autoDispose
    .family<List<Tag>, String>(
      (ref, id) => ref.watch(tagRepositoryProvider).watchForTransaction(id),
    );

/// Payment methods by id, so a detail row can name one without a query per row.
final paymentMethodsByIdProvider = StreamProvider<Map<String, PaymentMethod>>(
  (ref) => ref
      .watch(paymentMethodRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// The currencies a conversion may be frozen into.
final enabledCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// Writes for the detail screen, so the widget holds no repository call of its own.
final transactionActionsProvider = Provider<TransactionActions>(
  (ref) => TransactionActions(ref),
);

/// Delete, undo and freeze, with the invalidations each one implies.
class TransactionActions {
  /// Creates the action set.
  const TransactionActions(this._ref);

  final Ref _ref;

  /// Deletes [id], optionally recording [reason], and reports what it detached.
  ///
  /// Never cascades to the batches or assets the transaction's lines created — you deleted a
  /// receipt, not the groceries (anomaly A10). The returned report is what lets the screen offer to
  /// remove a provably untouched batch as a separate, explicit action.
  Future<DetachedArtefacts?> delete(String id, {String? reason}) async {
    final result = await _ref
        .read(transactionRepositoryProvider)
        .delete(id: id, reason: reason);
    _ref.invalidate(transactionByIdProvider(id));
    return result.valueOrNull;
  }

  // There is deliberately no undoDelete here, and it is a contract gap rather than an omission.
  //
  // `TransactionRepository` exposes exactly one deletion method and no `restore`. `update()` cannot
  // stand in for one: it reads `TransactionDao.byId` first, that DAO selects from
  // `v_active_transactions`, and the view filters `deleted_at IS NULL` — so a deleted row is
  // invisible to it and `update()` returns `NotFoundFailure`. An Undo wired to `update()` would
  // fail silently, which is the worst outcome Law U9 exists to prevent.
  //
  // Until `restore(String id)` is added to the 3A contract, deletion is treated as the
  // non-reversible tier of ARCH_5 §5.5: a sheet that names the consequence, not a snack with Undo.

  /// Freezes a converted snapshot of [id] into [toCurrencyCode], on the transaction's own date.
  ///
  /// A separate, frozen artefact that is never recomputed. It cannot touch the original amount or
  /// its currency — those are immutable once saved (Law L9) and the signature has no parameter for
  /// them.
  Future<bool> freezeConversion({
    required Transaction transaction,
    required String toCurrencyCode,
  }) async {
    final result = await _ref
        .read(transactionRepositoryProvider)
        .freezeConversion(
          id: transaction.id,
          on: transaction.dateKey,
          toCurrencyCode: toCurrencyCode,
        );
    _ref.invalidate(transactionByIdProvider(transaction.id));
    return result.isOk;
  }
}
```

### `lib/features/expense/providers/transaction_draft_provider.dart`

```dart
/// The one-shot channel a module uses to hand the expense editor a pre-filled transaction.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/features/expense/state/transaction_draft.dart';

/// A draft waiting to be picked up by the next new-transaction editor.
///
/// **Set immediately before pushing the editor, consumed by its first load, then cleared.** A
/// `go_router` `extra` cannot reach the notifier that builds the editor's state, and widening the
/// family argument to carry a `List<TransactionLine>` would break its structural equality — a list
/// compares by identity, so every rebuild would allocate a fresh provider. A single-slot channel
/// that empties on read is the smaller compromise, and `take()` makes the one-shot explicit rather
/// than leaving a stale draft to ambush the next blank editor.
final transactionDraftProvider =
    NotifierProvider<TransactionDraftNotifier, TransactionDraft?>(
      TransactionDraftNotifier.new,
    );

/// Holds at most one pending draft.
class TransactionDraftNotifier extends Notifier<TransactionDraft?> {
  @override
  TransactionDraft? build() => null;

  /// Offers a draft to the next editor that opens.
  void offer(TransactionDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TransactionDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
```

### `lib/features/expense/providers/transaction_editor_providers.dart`

```dart
/// View-model state for the transaction editor (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/core/logging/logger.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/domain/services/purchase_fan_out_service.dart';
import 'package:alaya/features/expense/providers/transaction_draft_provider.dart';
import 'package:alaya/features/expense/state/transaction_draft.dart';
import 'package:alaya/features/expense/state/split_draft.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/features/recurring/providers/bill_account_providers.dart';
import 'package:alaya/features/recurring/providers/template_draft_provider.dart';

/// Raised when a transaction genuinely is not there, as opposed to failing to load.
class TransactionNotFound implements Exception {
  /// Creates the marker.
  const TransactionNotFound(this.id);

  /// The transaction that is not there.
  final String id;

  @override
  String toString() => 'Transaction $id not found.';
}

/// The editor for one transaction, or for a new one when the argument is null.
///
/// The family argument arrives as a `build` parameter against `AutoDisposeFamilyNotifier`, which is
/// the shape this project's Riverpod actually resolves to. Riverpod 3.0's published guide describes
/// a fused `Notifier` taking the argument in its constructor; that does not compile here, and
/// checking the changelog instead of the analyzer is how Phase 6A got it wrong once already
/// (ARCH_1 §7.3, ARCH_4 R22).
final transactionEditorProvider = NotifierProvider.autoDispose
    .family<
      TransactionEditorNotifier,
      AsyncValue<TransactionEditorState>,
      String?
    >(
      TransactionEditorNotifier.new,
    );

/// Loads, edits and saves one transaction.
class TransactionEditorNotifier
    extends
        AutoDisposeFamilyNotifier<AsyncValue<TransactionEditorState>, String?> {
  @override
  AsyncValue<TransactionEditorState> build(String? arg) {
    unawaited(_load(arg));
    return const AsyncValue.loading();
  }

  Future<void> _load(String? id) async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final code = await settings.readHomeCurrencyCode() ?? 'INR';
      if (id == null) {
        // A draft another module prepared, if one is waiting. `take()` clears it, so a draft is
        // applied exactly once and a stale one cannot ambush the next blank editor.
        final draft = ref.read(transactionDraftProvider.notifier).take();
        state = AsyncValue.data(
          TransactionEditorState(
            currencyCode: code,
            dateKey: ref.read(clockProvider).today(),
            kind: draft?.kind ?? TransactionKind.withdrawal,
            subtype: draft?.subtype ?? TransactionSubtype.otherOut,
            lines: draft?.lines ?? const [],
            note: draft?.note,
            sourceEntryIds: draft?.sourceEntryIds ?? const [],
          ),
        );
        return;
      }
      final repository = ref.read(transactionRepositoryProvider);
      final transaction = await repository.byId(id);
      if (transaction == null) {
        state = AsyncValue.error(TransactionNotFound(id), StackTrace.current);
        return;
      }
      // `_firstOrEmpty`, not `.first`. `watchLines` returns without emitting when it cannot resolve
      // the parent's currency, and `.first` on a stream that closes empty throws `StateError: No
      // element` — which the editor then reported as "this may have been deleted".
      final lines = await _firstOrEmpty(repository.watchLines(id));
      final tags = await _firstOrEmpty(
        ref.read(tagRepositoryProvider).watchForTransaction(id),
      );
      state = AsyncValue.data(
        TransactionEditorState.fromTransaction(
          transaction,
          lines: lines,
          tagIds: {for (final tag in tags) tag.id},
        ),
      );
    } on Object catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  void _edit(TransactionEditorState Function(TransactionEditorState) change) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncValue.data(change(current));
  }

  /// Switches the flow type, keeping every field the new shape still has.
  ///
  /// **Nothing is cleared that the new shape can hold.** Changing withdrawal to deposit must not
  /// wipe the amount the user has already typed; only the accounts move, because a deposit needs a
  /// destination and no source and a withdrawal is the mirror of that (ARCH_2 §4.1).
  void setKind(TransactionKind kind) => _edit((s) {
    // Against the **new** kind, not the state's current one: `s` is the pre-change state, so
    // `s.availableSubtypes` would answer for the kind being replaced.
    final subtype = TransactionEditorState.subtypesFor(kind).contains(s.subtype)
        ? s.subtype
        : _defaultSubtypeFor(kind);
    return s.copyWith(
      kind: kind,
      subtype: subtype,
      fromAccountId: kind == TransactionKind.deposit
          ? null
          : s.fromAccountId ?? s.toAccountId,
      clearFromAccount: kind == TransactionKind.deposit,
      toAccountId: kind == TransactionKind.deposit
          ? s.toAccountId ?? s.fromAccountId
          : null,
      clearToAccount: kind == TransactionKind.withdrawal,
    );
  });

  /// Switches the visible sub-form.
  void setSubtype(TransactionSubtype subtype) =>
      _edit((s) => s.copyWith(subtype: subtype));

  /// Records the parsed amount, in the record's own currency.
  ///
  /// There is no currency setter anywhere on this notifier, and that is Law L9 rather than an
  /// oversight.
  void setAmount(Money? amount) => _edit(
    (s) => amount == null
        ? s.copyWith(clearAmount: true)
        : s.copyWith(amount: amount, amountMissing: false),
  );

  /// Sets the civil date the money moved.
  void setDate(DateKey date) => _edit((s) => s.copyWith(dateKey: date));

  /// Sets the source account.
  void setFromAccount(String? id) => _edit(
    (s) => id == null
        ? s.copyWith(clearFromAccount: true)
        : s.copyWith(fromAccountId: id),
  );

  /// Sets the destination account.
  void setToAccount(String? id) => _edit(
    (s) => id == null
        ? s.copyWith(clearToAccount: true)
        : s.copyWith(toAccountId: id),
  );

  /// Sets the rail the money travelled on.
  void setPaymentMethod(String? id) => _edit(
    (s) => id == null
        ? s.copyWith(clearPaymentMethod: true)
        : s.copyWith(paymentMethodId: id),
  );

  /// Replaces the split draft, or removes it when [draft] is null.
  ///
  /// Clearing `splitError` on every change is deliberate: a message from a previous save describes a
  /// draft the user has just replaced, and leaving it up is the defect `copyWith`'s own comment
  /// records — a stale reason outliving the thing it was about.
  void setSplit(SplitDraft? draft) => _edit(
    (s) => draft == null
        ? s.copyWith(clearSplit: true, splitError: null)
        : s.copyWith(split: draft, splitError: null),
  );

  /// Sets the counterparty.
  void setPayee(String? id) => _edit(
    (s) => id == null ? s.copyWith(clearPayee: true) : s.copyWith(payeeId: id),
  );

  /// Sets the free note.
  void setNote(String note) => _edit((s) => s.copyWith(note: note));

  /// Sets which recurring occurrence this payment settles, or clears the link.
  ///
  /// Selecting one also adopts the template's usual amount, because that is the figure the user is
  /// about to confirm or correct — leaving the field blank would make the common case extra typing.
  void setRecurringOccurrence({
    String? occurrenceId,
    Money? defaultAmount,
    String? accountId,
  }) => _edit(
    (s) => occurrenceId == null
        ? s.copyWith(clearOccurrence: true)
        : s.copyWith(
            recurringOccurrenceId: occurrenceId,
            amount: defaultAmount ?? s.amount,
            // The account comes across too, so the common path is one tap and not two. It is
            // whatever the template, the app default or a sole account already says.
            fromAccountId: accountId ?? s.fromAccountId,
            amountMissing: false,
            accountMissing: false,
          ),
  );

  /// Applies or removes a tag.
  void toggleTag(String tagId) => _edit((s) {
    final next = {...s.tagIds};
    if (next.contains(tagId)) {
      next.remove(tagId);
    } else {
      next.add(tagId);
    }
    return s.copyWith(tagIds: next);
  });

  /// Chooses between a transfer between the user's own accounts and a withdrawal to someone else.
  ///
  /// The whole point of anomaly A02: moving money between your own accounts must not reduce net
  /// worth, so it is `kind = transfer` with both accounts. Sending it to someone else is a real
  /// withdrawal with `subtype = transferOut` and a payee.
  void setTransferTarget({required bool toOwnAccount}) => _edit(
    (s) => s.copyWith(
      toOwnAccount: toOwnAccount,
      kind: toOwnAccount
          ? TransactionKind.transfer
          : TransactionKind.withdrawal,
      subtype: toOwnAccount
          ? TransactionSubtype.transferSelf
          : TransactionSubtype.transferOut,
      clearToAccount: !toOwnAccount,
      clearPayee: toOwnAccount,
    ),
  );

  /// Sets the warranty window for the asset an electronics line will create.
  void setWarranty({DateKey? start, DateKey? end}) =>
      _edit((s) => s.copyWith(warrantyStart: start, warrantyEnd: end));

  /// Opts an electronics purchase into also producing an inventory batch.
  void setAlsoAddToInventory({required bool value}) =>
      _edit((s) => s.copyWith(alsoAddToInventory: value));

  /// Adds or replaces a line, keyed on its id.
  void upsertLine(TransactionLine line) => _edit((s) {
    final next = [...s.lines];
    final index = next.indexWhere((existing) => existing.id == line.id);
    if (index >= 0) {
      next[index] = line;
    } else {
      next.add(line.copyWith(lineNo: next.length + 1));
    }
    return s.copyWith(lines: next);
  });

  /// Removes a line.
  void removeLine(String lineId) => _edit((s) {
    final next = [...s.lines.where((line) => line.id != lineId)];
    return s.copyWith(
      lines: [
        for (var i = 0; i < next.length; i++) next[i].copyWith(lineNo: i + 1),
      ],
    );
  });

  /// Creates a payee inline and selects it, so the editor never sends the user to Settings.
  ///
  /// Returns whether it worked. **The result is reported rather than dropped**: a save that fails
  /// silently leaves the user typing the same name again, wondering why it never appears, with
  /// nothing on screen to tell them the write was refused.
  Future<bool> createPayee(String name) async {
    final normalizer = ref.read(normalizerProvider);
    final payee = Payee(
      id: ref.read(uidGeneratorProvider).generate(),
      name: name,
      normalizedName: normalizer.normalize(name),
      kind: PayeeKind.merchant,
    );
    final saved = await ref.read(payeeRepositoryProvider).save(payee);
    final value = saved.valueOrNull;
    if (value == null) return false;
    setPayee(value.id);
    return true;
  }

  /// Saves the transaction and everything its lines produce.
  ///
  /// **Idempotent rather than atomic, and that is a recorded deviation from Law L14.** Atomicity is
  /// unavailable from here: three repositories are written and no repository may own another's
  /// transaction (ARCH_4 §5.1 item 17). What is achievable is that re-running is a no-op —
  /// `PurchaseFanOutService.planAll` skips any line that already carries a `created*Id`, and the
  /// ids are written back to the lines before this returns. Without that write-back, re-saving an
  /// edited transaction would create a second television every time.
  ///
  /// Returns the transaction's id on success, or null when the form was rejected or a write failed.
  Future<String?> save() async {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.amount == null) {
      _edit(
        (s) =>
            s.copyWith(amountMissing: true, shakeTrigger: s.shakeTrigger + 1),
      );
      return null;
    }

    _edit((s) => s.copyWith(submitting: true, clearErrors: true));
    // **`finally`, not a clear on each early return.** A `SqliteException` thrown anywhere below used
    // to propagate out of `save`, leaving `submitting: true` forever — the footer button stayed in its
    // progress state and the only way out of the screen was to kill the app.
    try {
      return await _write(current);
    } on Object catch (error, stack) {
      _edit((s) => s.copyWith(saveError: error.toString()));
      ref
          .read(loggerProvider)
          .log(
            'Transaction save failed',
            level: LogLevel.error,
            tag: 'expense.editor',
            error: error,
            stackTrace: stack,
          );
      return null;
    } finally {
      _edit((s) => s.copyWith(submitting: false));
    }
  }

  /// Commits [current], and is safe to call again after a failure partway through.
  ///
  /// **Five writes, no outer transaction — by design, and this is what makes that safe.** The
  /// sequence spans three repositories, and ARCH_4 §5.1 item 17 already ruled that none of them may
  /// own another's transaction; idempotency is the sanctioned answer instead. `planAll` supplies half
  /// of it by skipping any line that already carries a `created*Id`. This supplies the other half.
  ///
  /// Once the transaction row exists, its id is written back into the editor's state. A retry then
  /// sees `isEditing` and takes the update path, so a save that got as far as `create` and then threw
  /// is resumed rather than duplicated. Without this, `current.id` stayed null and every retry minted
  /// a second transaction — which is how a failed save left orphans in the ledger.
  Future<String?> _write(TransactionEditorState current) async {
    final uids = ref.read(uidGeneratorProvider);
    final clock = ref.read(clockProvider);
    final repository = ref.read(transactionRepositoryProvider);

    final amount = current.amount!;
    final id = current.id ?? uids.generate();
    // **Every line gets a fresh id on every attempt, create or edit.**
    //
    // Two reasons, and the second is the one that bit. `replaceLines` soft-deletes the existing rows
    // rather than removing them (Law L6), so an edit reusing an id collides with the row still
    // physically there. And a line id held in state — one a shopping draft minted, or one a previous
    // failed attempt already inserted — is reused verbatim by the next attempt, so any save that got
    // as far as writing lines makes every retry fail with `UNIQUE constraint failed:
    // transaction_lines.id` and mask whatever actually went wrong the first time.
    //
    // A line id has no meaning outside its row: nothing references it but the batch it produced, and
    // that link is written after the insert. So it is assigned here, at write time, never carried in.
    final lines = [
      for (final line in current.lines)
        line.copyWith(id: uids.generate(), transactionId: id),
    ];
    final transaction = current.toTransaction(
      newId: id,
      occurredAtUtc: clock.now().toUtc(),
    );

    // **A bill settling a recurring occurrence has exactly one write, and it is not this one.**
    // `payOccurrence` creates the transaction *and* marks the occurrence paid in the same call, so
    // going through `create` as well produced two transactions for one payment — the amount typed
    // here and the amount confirmed in a sheet both landed. The editor's amount is now the only
    // figure, and this is the only save.
    final settling = current.recurringOccurrenceId;
    if (settling != null && !current.isEditing) {
      // Resolved rather than demanded: the template's default, then the app default, then a sole
      // account. Only a genuine ambiguity — several accounts and no default anywhere — reaches the
      // rejection, and `payOccurrence` cannot take null because a withdrawal with no source account
      // makes every balance and every insight quietly wrong.
      final account =
          current.fromAccountId ??
          current.toAccountId ??
          ref.read(resolvedBillAccountProvider(null));
      if (account == null) {
        _edit((s) => s.copyWith(accountMissing: true));
        return null;
      }
      final paid = await ref
          .read(recurringRepositoryProvider)
          .payOccurrence(
            occurrenceId: settling,
            amount: amount,
            paidOn: current.dateKey,
            accountId: account,
            paymentMethodId: current.paymentMethodId,
          );
      final failure = paid.failureOrNull;
      if (failure != null) {
        _edit((s) => s.copyWith(saveError: failure.message));
        return null;
      }
      _edit((s) => s.copyWith(dirty: false, clearOccurrence: true));
      return paid.valueOrNull?.id;
    }

    final written = current.isEditing
        ? await repository.update(transaction)
        : await repository.create(
            transaction: transaction,
            lines: lines,
            tagIds: current.tagIds.toList(),
          );
    if (written.isFailure) {
      // The repository says what it refused — an account a withdrawal needs, a currency that is not
      // enabled, a line that will not validate. Discarding that is what made a save unfixable.
      _edit((s) => s.copyWith(saveError: written.failureOrNull?.message));
      return null;
    }

    // The row is committed. From here on this is an edit, whatever happens next.
    if (!current.isEditing) {
      _edit((s) => s.copyWith(id: id));
    }

    if (current.isEditing) {
      final replaced = await repository.replaceLines(
        transactionId: id,
        lines: lines,
      );
      if (replaced.isFailure) {
        _edit((s) => s.copyWith(saveError: replaced.failureOrNull?.message));
        return null;
      }
    }

    final fanned = await _fanOut(
      transaction: transaction,
      lines: lines,
      state: current,
    );
    // One column per line, through the write built for it — never `replaceLines`, which would insert
    // rows whose ids already exist.
    for (final line in fanned.lines) {
      if (line.createdBatchId == null &&
          line.createdAssetId == null &&
          line.createdRecurringTemplateId == null) {
        continue;
      }
      await repository.recordCreatedArtefact(
        lineId: line.id,
        createdBatchId: line.createdBatchId,
        createdAssetId: line.createdAssetId,
        createdRecurringTemplateId: line.createdRecurringTemplateId,
      );
    }
    // The loop closes here. `markPurchased` exists for exactly this and takes the ids the draft
    // carried across, so the shopping entries stop being outstanding the moment the expense that
    // fulfils them is committed (anomaly A25). Guarded, so an ordinary expense never touches it.
    if (current.sourceEntryIds.isNotEmpty) {
      await ref
          .read(shoppingRepositoryProvider)
          .markPurchased(
            entryIds: current.sourceEntryIds,
            transactionId: id,
          );
    }
    // **The split, after everything else.** It needs the transaction id, which is why it cannot run
    // earlier; and it runs last so a split that fails never stops a batch or an asset from being
    // created. The transaction is committed either way — what failed is the debt a step asked for,
    // and `splitError` says so exactly as `fanOutError` does for stock (Law U9).
    final splitError = await _applySplit(current, transactionId: id);

    // `clearErrors` first so a previous attempt's message cannot outlive it, then the new one.
    _edit((s) => s.copyWith(dirty: false, clearErrors: true));
    _edit(
      (s) => s.copyWith(
        fanOutError: fanned.error,
        wantsTemplate: fanned.wantsTemplate,
        createdAssetId: fanned.createdAsset,
        splitError: splitError,
      ),
    );
    return id;
  }

  /// Writes the drafted split against a transaction that now exists, and returns why it could not.
  ///
  /// **Idempotent, because `_write` is.** That method's own doc records the rule: five writes, no
  /// outer transaction, and ARCH_4 §5.1 item 17 forbids one repository owning another's — so
  /// idempotency is the sanctioned answer, and every step has to supply its own half of it.
  ///
  /// Here that means looking up the split already attached to this transaction and reusing its id.
  /// Without it, a save that got this far and then threw would mint a second `SplitExpense` on the
  /// retry and the debt would double — the same defect the line-id comment above records, in a
  /// different table. A transaction carries at most one split, so `expenseForTransaction` is an exact
  /// answer rather than a heuristic.
  Future<String?> _applySplit(
    TransactionEditorState current, {
    required String transactionId,
  }) async {
    final draft = current.split;
    if (draft == null || !draft.isActive) return null;
    final amount = current.amount;
    if (amount == null) return null;

    final existing = await ref
        .read(splitLedgerRepositoryProvider)
        .expenseForTransaction(transactionId);

    final result = await ref
        .read(splitExpenseServiceProvider)
        .record(
          id: existing?.id,
          total: amount,
          paidByPayeeId: draft.paidByPayeeId,
          inputs: draft.inputs,
          method: draft.method,
          transactionId: transactionId,
          groupId: draft.groupId,
          // The note doubles as the split's title. A shared bill wants a name — "Dinner at Olive" —
          // and asking for one twice on the same screen is how a field gets left blank.
          title: current.note,
          on: current.dateKey,
          settleBy: draft.settleByDateKey,
        );
    return result.failureOrNull?.message;
  }

  /// Creates the batches, assets and template names the lines call for, and writes their ids back.
  ///
  /// **Reports whether anything was refused.** `_planBatch` rejects a line with no `itemId` or no
  /// quantity, and an earlier version dropped that failure on the floor — the transaction saved, the
  /// snack said so, and the stock never appeared in the inventory with nothing on screen to explain
  /// why. A write that half-succeeds must say which half (U9).
  Future<
    ({
      List<TransactionLine> lines,
      String? error,
      bool wantsTemplate,
      String? createdAsset,
    })
  >
  _fanOut({
    required Transaction transaction,
    required List<TransactionLine> lines,
    required TransactionEditorState state,
  }) async {
    if (lines.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    final uids = ref.read(uidGeneratorProvider);
    final planned = ref
        .read(purchaseFanOutServiceProvider)
        .planAll(
          lines: lines,
          transaction: transaction,
          newArtefactIds: [
            for (var i = 0; i < lines.length; i++) uids.generate(),
          ],
        );
    final plans = planned.valueOrNull;
    if (plans == null) {
      // Every line that asked for an artefact was refused — almost always a line marked for
      // inventory with no catalogued item behind it.
      final wanted = lines.any(
        (line) => line.destination != TransactionLineDestination.none,
      );
      return (
        lines: const <TransactionLine>[],
        error: wanted ? planned.failureOrNull?.message : null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }
    if (plans.isEmpty) {
      return (
        lines: const <TransactionLine>[],
        error: null,
        wantsTemplate: false,
        createdAsset: null,
      );
    }

    String? refused;
    var requestedTemplate = false;
    String? createdAsset;
    final updated = [...lines];
    for (final plan in plans) {
      final index = updated.indexWhere((line) => line.id == plan.lineId);
      if (index < 0) continue;
      switch (plan.target) {
        case FanOutTarget.batch:
          final batch = plan.batch;
          if (batch == null) continue;
          final saved = await ref.read(batchRepositoryProvider).create(batch);
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdBatchId: value.id);
          }
        case FanOutTarget.asset:
          final asset = plan.asset;
          if (asset == null) continue;
          // The warranty window lives on the form rather than on the line, because a receipt line
          // has no column for it — so it is applied to the planned asset here.
          final saved = await ref
              .read(assetRepositoryProvider)
              .save(
                asset.copyWith(
                  warrantyStartDateKey: state.warrantyStart,
                  warrantyEndDateKey: state.warrantyEnd,
                ),
              );
          final value = saved.valueOrNull;
          if (value == null) {
            refused = saved.failureOrNull?.message;
          } else {
            updated[index] = updated[index].copyWith(createdAssetId: value.id);
            // Carried out so the editor can open the asset it just made. It is typed `other` with no
            // warranty, because a receipt line has no way to say otherwise — which is exactly why the
            // user needs to land on it rather than go hunting.
            createdAsset ??= value.id;
          }
        case FanOutTarget.recurringTemplate:
          // A schedule needs an interval and an anchor a receipt line does not contain, so the name
          // and amount are handed to Phase 6D's builder and the user supplies the rest. Inventing a
          // monthly-on-the-1st default would create an obligation nobody agreed to.
          //
          // **This branch used to `break` and do nothing at all** — the control was tickable, saved
          // cleanly, and produced no template and no message.
          ref
              .read(templateDraftProvider.notifier)
              .offer(
                TemplateDraft(
                  name:
                      plan.recurringTemplateName ?? updated[index].description,
                  amount: updated[index].lineAmount ?? state.amount,
                ),
              );
          requestedTemplate = true;
        case FanOutTarget.none:
          break;
      }
    }
    return (
      lines: updated,
      error: refused,
      wantsTemplate: requestedTemplate,
      createdAsset: createdAsset,
    );
  }

  static TransactionSubtype _defaultSubtypeFor(TransactionKind kind) =>
      switch (kind) {
        TransactionKind.deposit => TransactionSubtype.otherIn,
        TransactionKind.withdrawal => TransactionSubtype.otherOut,
        TransactionKind.transfer => TransactionSubtype.transferSelf,
        TransactionKind.adjustmentIncrease => TransactionSubtype.otherIn,
        TransactionKind.adjustmentDecrease => TransactionSubtype.otherOut,
      };
}

/// Payment methods offered in the editor.
final editorPaymentMethodsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Payees offered in the editor.
final editorPayeesProvider = StreamProvider<List<Payee>>(
  (ref) => ref.watch(payeeRepositoryProvider).watchAll(),
);

/// Tags offered for a given flow direction.
final editorTagsProvider = StreamProvider.autoDispose
    .family<List<Tag>, TransactionKind>(
      (ref, kind) => ref
          .watch(tagRepositoryProvider)
          .watchByScope(
            kind == TransactionKind.deposit
                ? TagScope.deposit
                : TagScope.withdrawal,
          ),
    );

/// The first event of [stream], or an empty list when it closes without emitting one.
Future<List<T>> _firstOrEmpty<T>(Stream<List<T>> stream) async {
  await for (final value in stream) {
    return value;
  }
  return <T>[];
}
```

### `lib/features/expense/providers/transaction_list_providers.dart`

```dart
/// View-model providers for the transaction list (ARCH_5 U19).
///
/// **Not one repository or engine provider here.** Every dependency is watched from
/// `app/providers/`, which is what stops one repository acquiring three providers and
/// `ItemCategoryResolver` — which caches — being constructed once per feature.
library;

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/services/date_range_service.dart';
import 'package:alaya/features/expense/state/transaction_filter.dart';

// **`homeCurrencyCodeProvider` and `homeDecimalDigitsProvider` moved to `app/providers/`.**
//
// Neither was ever about a transaction list: the split module, the analytics cards and the dashboard
// all needed a decimal precision and had to import this file to get one. The split module nearly
// declared its own instead, which would have been two sources for one fact — the failure that makes
// JPY render with 0 digits on some screens and 2 on others.
//
// Re-exported so every existing import of this file keeps resolving them. New code should import
// `package:alaya/app/providers/currency_providers.dart`; this line can go once a grep for the two
// names finds nothing pointing here.
export 'package:alaya/app/providers/currency_providers.dart'
    show homeCurrencyCodeProvider, homeDecimalDigitsProvider;

/// The list's active filter.
///
/// A plain `Notifier` rather than a family: there is one transaction list, and giving it a family
/// argument it never varies over would create a second instance the first time a caller passed a
/// different key.
final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
      TransactionFilterNotifier.new,
    );

/// Mutates the transaction list's filter.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  /// Sets the reporting window to a named preset, dropping any hand-picked range.
  void setPreset(DateRangePreset preset) =>
      state = state.copyWith(preset: preset, clearCustomRange: true);

  /// Sets a hand-picked window.
  void setCustomRange(DateRange range) => state = state.copyWith(
    preset: DateRangePreset.custom,
    customRange: range,
  );

  /// Adds or removes a kind from the filter.
  void toggleKind(TransactionKind kind) {
    final next = {...state.kinds};
    if (next.contains(kind)) {
      next.remove(kind);
    } else {
      next.add(kind);
    }
    state = state.copyWith(kinds: next);
  }

  /// Adds or removes a subtype from the filter.
  void toggleSubtype(TransactionSubtype subtype) {
    final next = {...state.subtypes};
    if (next.contains(subtype)) {
      next.remove(subtype);
    } else {
      next.add(subtype);
    }
    state = state.copyWith(subtypes: next);
  }

  /// Restricts to one account, or clears the restriction when [accountId] is null.
  void setAccount(String? accountId) => state = accountId == null
      ? state.copyWith(clearAccount: true)
      : state.copyWith(accountId: accountId);

  /// Restricts to one payee, or clears the restriction when [payeeId] is null.
  void setPayee(String? payeeId) => state = payeeId == null
      ? state.copyWith(clearPayee: true)
      : state.copyWith(payeeId: payeeId);

  /// Shows only the transactions the needs-review nudge is counting.
  ///
  /// Widens the window to all time at the same time: a flagged transaction from six weeks ago is
  /// exactly the one the nudge exists to surface, and leaving the default thirty-day window on
  /// would hide it behind the very count that pointed at it.
  void showNeedsReviewOnly() => state = state.copyWith(
    needsReviewOnly: true,
    preset: DateRangePreset.allTime,
    clearCustomRange: true,
  );

  /// Stops restricting to flagged transactions.
  void clearNeedsReviewOnly() => state = state.copyWith(needsReviewOnly: false);

  /// Returns to the default window with nothing else narrowed.
  void clear() => state = const TransactionFilter();
}

/// The date window the current filter resolves to.
///
/// Resolved through `DateRangeService` against the injected clock, never `DateTime.now()`, so a
/// date-sensitive widget test is reproducible.
final transactionRangeProvider = Provider<DateRange>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final service = ref.watch(dateRangeServiceProvider);
  final today = ref.watch(clockProvider).today();
  if (filter.preset == DateRangePreset.custom) {
    return filter.customRange ?? (from: DateRangeService.earliest, to: today);
  }
  return service.resolve(filter.preset, today) ??
      (from: DateRangeService.earliest, to: today);
});

/// The filtered transactions, newest first.
///
/// The date window is applied by the indexed query; the rest is applied in Dart, because those
/// predicates are over a page of rows rather than the whole table.
final filteredTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final range = ref.watch(transactionRangeProvider);
  return ref
      .watch(transactionRepositoryProvider)
      .watchByDateRange(from: range.from, to: range.to)
      .map(
        (rows) => rows
            .where(
              (t) => filter.admits(
                kind: t.kind,
                subtype: t.subtype,
                fromAccountId: t.fromAccountId,
                toAccountId: t.toAccountId,
                transactionPayeeId: t.payeeId,
                needsReview: t.needsReview,
              ),
            )
            .toList(),
      );
});

/// One day's transactions, for a sticky header.
class TransactionDayGroup {
  /// Creates a day group.
  const TransactionDayGroup({required this.date, required this.transactions});

  /// The civil date these share.
  final DateKey date;

  /// The transactions on [date], newest first.
  final List<Transaction> transactions;
}

/// The filtered transactions grouped into days, newest day first.
final transactionDaysProvider = Provider<AsyncValue<List<TransactionDayGroup>>>(
  (ref) => ref.watch(filteredTransactionsProvider).whenData(_groupByDay),
);

List<TransactionDayGroup> _groupByDay(List<Transaction> rows) {
  final groups = <int, List<Transaction>>{};
  for (final row in rows) {
    groups.putIfAbsent(row.dateKey.value, () => <Transaction>[]).add(row);
  }
  final dates = groups.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final date in dates)
      TransactionDayGroup(date: DateKey(date), transactions: groups[date]!),
  ];
}

/// How many transactions still need details, for the nudge.
final needsReviewCountProvider = StreamProvider<int>(
  (ref) => ref.watch(transactionRepositoryProvider).watchNeedsReviewCount(),
);

/// Accounts by id, so a row can name one without a query per row.
final accountsByIdProvider = StreamProvider<Map<String, Account>>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((rows) => {for (final row in rows) row.id: row}),
);

/// Selectable accounts in sort order, for a picker or a chip row.
final selectableAccountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchSelectable(),
);

/// Payees by id, so a row can name one without a query per row.
final payeesByIdProvider = StreamProvider<Map<String, Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((rows) => {for (final row in rows) row.id: row}),
);
```

### `lib/features/expense/providers/transaction_search_providers.dart`

```dart
/// Full-text search over transaction notes, kept separate from the filter providers.
///
/// A different concern with a different shape: the filter narrows a live stream, search resolves a
/// one-shot query against FTS5. Folding them into one provider would mean a stream that sometimes
/// is not one.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/domain/entities/transaction.dart';

/// The current search query, empty when the user is not searching.
final transactionSearchQueryProvider =
    NotifierProvider<TransactionSearchQueryNotifier, String>(
      TransactionSearchQueryNotifier.new,
    );

/// Holds the search box's settled query.
class TransactionSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Replaces the query. Already debounced by `AlayaSearchField`.
  void set(String query) => state = query;

  /// Clears the query, returning the list to its filtered view.
  void clear() => state = '';
}

/// Whether the list is showing search results rather than the filtered window.
final isSearchingProvider = Provider<bool>(
  (ref) => ref.watch(transactionSearchQueryProvider).isNotEmpty,
);

/// Search results for the current query, best match first.
///
/// Capped rather than unbounded: FTS over ten thousand notes can match most of them, and a list the
/// user has to scroll for a minute is not a search result.
final transactionSearchResultsProvider = FutureProvider<List<Transaction>>((
  ref,
) async {
  final query = ref.watch(transactionSearchQueryProvider);
  if (query.isEmpty) return const <Transaction>[];
  return ref.watch(transactionRepositoryProvider).search(query, limit: 100);
});
```

### `lib/features/expense/providers/unit_providers.dart`

```dart
/// Unit reference data for the expense forms.
///
/// Watches `unitRepositoryProvider` from `app/providers/` — no repository is declared here.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Every unit, for the quantity field's picker.
final unitsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// Units within one category.
///
/// `UnitPicker` also filters, deliberately — a picker that trusts its input to be category-correct is
/// one bad call site away from breaking Law L8. This provider narrows the stream so the common case
/// does not ship every unit to the widget.
final unitsInCategoryProvider = StreamProvider.family<List<Unit>, UnitCategory>(
  (ref, category) =>
      ref.watch(unitRepositoryProvider).watchByCategory(category),
);
```

### `lib/features/expense/state/split_draft.dart`

```dart
import 'package:alaya/core/enums/split_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/split/split_resolver.dart';

/// The split the transaction editor is holding, before anything is saved.
///
/// **A draft, not the entity.** A `SplitExpense` needs a transaction id, and there is no transaction
/// until the editor saves — so the editor carries the *instructions* and the service turns them into
/// shares afterwards. That ordering is forced and it is the safe one: an expense saved without its
/// split leaves a transaction the user can see and re-split, while the reverse would be a debt
/// against a payment that does not exist.
///
/// It rides the same save flow the purchase fan-out already uses: held in editor state, applied after
/// the transaction commits, and any failure surfaced through `splitError` exactly as `fanOutError`
/// reports a batch that could not be created.
class SplitDraft {
  /// Creates a draft.
  const SplitDraft({
    required this.paidByPayeeId,
    required this.method,
    this.inputs = const [],
    this.groupId,
    this.settleByDateKey,
  });

  /// Who fronted the money.
  ///
  /// The user themselves in the ordinary case — you paid, and the transaction being edited is that
  /// payment. Somebody else when the expense is being recorded on their behalf, in which case the
  /// editor is not the right entry point and the split module's own screen is.
  final String paidByPayeeId;

  /// How the shares were specified.
  final SplitMethod method;

  /// One instruction per participant.
  final List<ShareInput> inputs;

  /// The group this belongs to, or null for a one-off split.
  final String? groupId;

  /// An optional date to settle by, which feeds the calendar and the daily digest.
  ///
  /// **Typed, having been `Object?` since session 5b.** That was laziness — a way to avoid one import
  /// on a field nothing read yet — and it would have silently accepted anything the moment something
  /// did. It now feeds `v_calendar_events`' `splitSettleBy` arm and the `settlementDue` reminder, so a
  /// wrong type here would reach a notification.
  final DateKey? settleByDateKey;

  /// Whether anything is actually being split.
  bool get isActive => inputs.isNotEmpty;

  /// The people on this split.
  List<String> get payeeIds => [for (final input in inputs) input.payeeId];

  /// Resolves the draft against [total], or null when nothing is being split.
  ///
  /// **Called on every rebuild, deliberately.** The resolver is pure and cheap, and recomputing is
  /// what keeps the per-person amounts on screen equal to the ones that will be written — a cached
  /// resolution would be a second source for the same fact, which ARCH_M §6 forbids for exactly the
  /// reason it would show one number and save another.
  ///
  /// Returns null rather than throwing on a malformed draft: the resolver refuses things a user
  /// cannot cause (no participants, the same person twice, percent mixed with weights), and the
  /// editor's job is to make those unreachable rather than to catch them.
  SplitResolution? resolve(Money? total) {
    if (total == null || inputs.isEmpty) return null;
    try {
      return const SplitResolver().resolve(total: total, inputs: inputs);
    } on ArgumentError {
      return null;
    }
  }

  /// A copy with the supplied changes.
  SplitDraft copyWith({
    String? paidByPayeeId,
    SplitMethod? method,
    List<ShareInput>? inputs,
    String? groupId,
    bool clearGroup = false,
    DateKey? settleByDateKey,
    bool clearSettleBy = false,
  }) => SplitDraft(
    paidByPayeeId: paidByPayeeId ?? this.paidByPayeeId,
    method: method ?? this.method,
    inputs: inputs ?? this.inputs,
    groupId: clearGroup ? null : (groupId ?? this.groupId),
    settleByDateKey: clearSettleBy
        ? null
        : (settleByDateKey ?? this.settleByDateKey),
  );
}
```

### `lib/features/expense/state/transaction_draft.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/transaction_line.dart';

/// A transaction another module has prepared for the user to confirm.
///
/// **Carries lines, not a saved transaction.** `ShoppingRepository.buildPurchaseDraft` deliberately
/// returns drafts rather than writing anything, because the amount, the account and the payee are
/// decisions only the expense editor can collect. Handing them over as a draft is what lets the
/// shopping module close the loop without reimplementing the editor (anomaly A25).
class TransactionDraft {
  /// Creates a draft.
  const TransactionDraft({
    required this.lines,
    required this.kind,
    required this.subtype,
    this.note,
    this.sourceEntryIds = const <String>[],
    this.sourceListId,
  });

  /// The lines the editor should open with.
  final List<TransactionLine> lines;

  /// The flow type the editor should open on.
  final TransactionKind kind;

  /// The subtype the editor should open on.
  final TransactionSubtype subtype;

  /// A note to seed, if the origin has something worth saying.
  final String? note;

  /// Which shopping entries these lines came from, so they can be marked purchased on save.
  final List<String> sourceEntryIds;

  /// Which shopping list they came from.
  final String? sourceListId;
}
```

### `lib/features/expense/state/transaction_editor_state.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/state/split_draft.dart';

/// Everything the transaction editor is holding (ARCH_5 §3 archetype B).
///
/// **The currency is here and has no setter.** Law L9 makes `originalCurrencyCode` immutable once
/// saved: changing it would reinterpret the stored minor units against a different precision and
/// symbol, silently and unrecoverably. The amount *is* editable — forbidding that would make a
/// mistyped figure permanent with delete-and-recreate as the only remedy, which loses the batch and
/// asset links the fan-out created (ARCH_4 §5.1 item 18).
class TransactionEditorState {
  /// Creates the editor's state.
  const TransactionEditorState({
    required this.currencyCode,
    required this.dateKey,
    this.id,
    this.kind = TransactionKind.withdrawal,
    this.subtype = TransactionSubtype.otherOut,
    this.amount,
    this.fromAccountId,
    this.toAccountId,
    this.paymentMethodId,
    this.payeeId,
    this.note,
    this.tagIds = const <String>{},
    this.lines = const <TransactionLine>[],
    this.warrantyStart,
    this.warrantyEnd,
    this.alsoAddToInventory = false,
    this.toOwnAccount = true,
    this.needsReview = false,
    this.submitting = false,
    this.amountMissing = false,
    this.shakeTrigger = 0,
    this.dirty = false,
    this.fanOutError,
    this.saveError,
    this.wantsTemplate = false,
    this.recurringOccurrenceId,
    this.accountMissing = false,
    this.createdAssetId,
    this.sourceEntryIds = const <String>[],
    this.split,
    this.splitError,
  });

  /// The transaction being edited, or null when this is a new one.
  final String? id;

  /// The flow type. Drives which accounts the shape requires (ARCH_2 §4.1).
  final TransactionKind kind;

  /// The structural subtype. Decides which sub-form is visible.
  final TransactionSubtype subtype;

  /// The amount. The one required field.
  final Money? amount;

  /// The currency, fixed for the life of the record (Law L9).
  final String currencyCode;

  /// The civil date the money moved.
  final DateKey dateKey;

  /// Where the money came from.
  final String? fromAccountId;

  /// Where the money went.
  final String? toAccountId;

  /// The rail it travelled on.
  final String? paymentMethodId;

  /// The counterparty.
  final String? payeeId;

  /// A free note, searchable through FTS.
  final String? note;

  /// The tags applied.
  final Set<String> tagIds;

  /// The lines itemising this transaction.
  final List<TransactionLine> lines;

  /// Warranty start for the asset an electronics line will create.
  final DateKey? warrantyStart;

  /// Warranty end for the asset an electronics line will create.
  final DateKey? warrantyEnd;

  /// Whether an electronics purchase should also produce an inventory batch.
  ///
  /// Off by default: a television is an Asset, not consumable stock, and pushing it to both is
  /// anomaly A12 — neither module then owns the truth.
  final bool alsoAddToInventory;

  /// For the transfer form: whether the money is going to the user's own account.
  ///
  /// True means `kind = transfer` and both accounts are the user's. False means a real withdrawal
  /// with `subtype = transferOut` and a payee — the distinction anomaly A02 exists for, because
  /// treating a self-transfer as a withdrawal destroys net worth.
  final bool toOwnAccount;

  /// Whether the record is still flagged as needing details.
  final bool needsReview;

  /// Whether a save is in flight.
  final bool submitting;

  /// Whether submit was pressed with no parseable amount.
  final bool amountMissing;

  /// Incremented to shake the amount field.
  final int shakeTrigger;

  /// Whether anything has been edited, for the unsaved-changes guard (Law U10).
  final bool dirty;

  /// Why the last save wrote the transaction but could not create the stock or assets its lines
  /// asked for, or null when it created them all.
  final String? fanOutError;

  /// Why the last save was refused outright, or null when it committed.
  ///
  /// The repository's own message. A withdrawal with no account and a line that will not validate
  /// fail for entirely different reasons, and reporting both as "something went wrong" is why neither
  /// was diagnosable from the screen.
  final String? saveError;

  /// Whether a line asked to become a recurring template, so the editor hands the user to the builder
  /// instead of dropping the request on the floor.
  final bool wantsTemplate;

  /// The recurring occurrence this payment settles, or null for an ordinary bill.
  ///
  /// **When set, saving goes through `payOccurrence` instead of `create`.** That call writes the
  /// transaction *and* settles the occurrence together, so there is exactly one write and exactly one
  /// record — an editor that created its own transaction as well would produce two for one payment.
  final String? recurringOccurrenceId;

  /// The asset a line just created, so the editor can hand the user to it.
  ///
  /// **The fan-out was already creating it.** A line marked for assets produces an `Asset` named after
  /// the description, typed `other`, with no warranty — because a receipt line carries none of that.
  /// Nothing then said so, so a television bought as an expense appeared under "Other" with no cover
  /// dates and looked like the feature had not worked. The id travels out and the editor opens on it.
  final String? createdAssetId;

  /// Whether a bill payment could not resolve an account and needs one chosen.
  ///
  /// A field-level error rather than a snack: the choice is made in the form, so the message belongs
  /// beside it (§5.5). It is only ever set when the template, the app default and a sole account all
  /// failed to answer.
  final bool accountMissing;

  /// Shopping entries this transaction fulfils, carried in from a draft and marked purchased on save.
  final List<String> sourceEntryIds;

  /// The split being drafted, or null when this expense is not shared.
  ///
  /// **Held here rather than in its own provider**, because it is part of *this* draft: abandoning the
  /// editor abandons the split with it, and `AlayaFormScaffold`'s unsaved-changes guard (Law U10) then
  /// covers both without a second thing to remember.
  ///
  /// A draft rather than a `SplitExpense`, because that entity needs a transaction id and there is no
  /// transaction until this editor saves. The service turns instructions into shares afterwards — the
  /// same ordering the purchase fan-out already uses.
  final SplitDraft? split;

  /// Why the split could not be saved, when the transaction itself did.
  ///
  /// The exact shape of [fanOutError], and for the same reason: the transaction is saved either way,
  /// and what failed is the artefact a step asked for. Saying nothing is how a shared bill silently
  /// fails to become a debt (Law U9).
  final String? splitError;

  /// Whether this is editing an existing record rather than creating one.
  bool get isEditing => id != null;

  /// The subtypes offered for the current [kind].
  List<TransactionSubtype> get availableSubtypes => subtypesFor(kind);

  /// The subtypes a given [kind] may take.
  ///
  /// **Static, and taking the kind explicitly, because callers need to ask about a kind the state
  /// does not have yet.** `setKind` must decide whether the current subtype survives the switch, and
  /// an instance getter can only answer for the kind already applied — which silently answers the
  /// wrong question and leaves the record in a shape the subtype picker cannot render. That defect
  /// showed up as a red screen the moment the user chose Income.
  ///
  /// A deposit cannot be a grocery purchase, and offering the full list would let a user save a
  /// shape the schema's CHECK constraints reject at write time rather than at choose time.
  static List<TransactionSubtype> subtypesFor(
    TransactionKind kind,
  ) => switch (kind) {
    TransactionKind.deposit => const [
      TransactionSubtype.salaryIn,
      TransactionSubtype.otherIn,
    ],
    TransactionKind.transfer => const [TransactionSubtype.transferSelf],
    TransactionKind.withdrawal => const [
      TransactionSubtype.grocery,
      TransactionSubtype.household,
      TransactionSubtype.electronics,
      TransactionSubtype.bill,
      TransactionSubtype.transferOut,
      TransactionSubtype.otherOut,
    ],
    TransactionKind.adjustmentIncrease => const [TransactionSubtype.otherIn],
    TransactionKind.adjustmentDecrease => const [TransactionSubtype.otherOut],
  };

  /// The sum of the lines, or null when there are none.
  Money? get lineTotal {
    if (lines.isEmpty) return null;
    var total = Money.zero(currencyCode);
    for (final line in lines) {
      final lineAmount = line.lineAmount;
      if (lineAmount != null) total += lineAmount;
    }
    return total;
  }

  /// The difference between the transaction amount and its lines.
  ///
  /// Surfaced as an "unallocated" chip and **never auto-balanced**: the transaction amount is the
  /// source of truth and the lines are optional detail, so forcing them equal would silently invent
  /// a line the user did not buy (anomaly A11).
  Money? get unallocated {
    final total = lineTotal;
    final value = amount;
    if (total == null || value == null) return null;
    final difference = value - total;
    return difference.isZero ? null : difference;
  }

  /// Returns a copy with the supplied changes, marked dirty unless told otherwise.
  TransactionEditorState copyWith({
    String? id,
    TransactionKind? kind,
    TransactionSubtype? subtype,
    Money? amount,
    bool clearAmount = false,
    DateKey? dateKey,
    String? fromAccountId,
    bool clearFromAccount = false,
    String? toAccountId,
    bool clearToAccount = false,
    String? paymentMethodId,
    bool clearPaymentMethod = false,
    String? payeeId,
    bool clearPayee = false,
    String? note,
    Set<String>? tagIds,
    List<TransactionLine>? lines,
    DateKey? warrantyStart,
    DateKey? warrantyEnd,
    bool? alsoAddToInventory,
    bool? toOwnAccount,
    bool? needsReview,
    bool? submitting,
    bool? amountMissing,
    int? shakeTrigger,
    bool? dirty,
    String? fanOutError,
    String? saveError,
    bool? wantsTemplate,
    String? recurringOccurrenceId,
    bool? accountMissing,
    String? createdAssetId,
    bool clearOccurrence = false,
    bool clearErrors = false,
    List<String>? sourceEntryIds,
    SplitDraft? split,
    bool clearSplit = false,
    String? splitError,
  }) => TransactionEditorState(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    subtype: subtype ?? this.subtype,
    amount: clearAmount ? null : (amount ?? this.amount),
    currencyCode: currencyCode,
    dateKey: dateKey ?? this.dateKey,
    fromAccountId: clearFromAccount
        ? null
        : (fromAccountId ?? this.fromAccountId),
    toAccountId: clearToAccount ? null : (toAccountId ?? this.toAccountId),
    paymentMethodId: clearPaymentMethod
        ? null
        : (paymentMethodId ?? this.paymentMethodId),
    payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
    note: note ?? this.note,
    tagIds: tagIds ?? this.tagIds,
    lines: lines ?? this.lines,
    warrantyStart: warrantyStart ?? this.warrantyStart,
    warrantyEnd: warrantyEnd ?? this.warrantyEnd,
    alsoAddToInventory: alsoAddToInventory ?? this.alsoAddToInventory,
    toOwnAccount: toOwnAccount ?? this.toOwnAccount,
    needsReview: needsReview ?? this.needsReview,
    submitting: submitting ?? this.submitting,
    amountMissing: amountMissing ?? this.amountMissing,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    dirty: dirty ?? true,
    // **Preserved unless explicitly cleared.** These were written as `fanOutError: fanOutError`,
    // so every later `copyWith` that did not mention them — including the `submitting: false` in
    // `save`'s `finally` — wiped the reason microseconds before the screen read it. Two separate
    // attempts to surface a real failure produced "something went wrong" because of this line.
    fanOutError: clearErrors ? null : (fanOutError ?? this.fanOutError),
    saveError: clearErrors ? null : (saveError ?? this.saveError),
    wantsTemplate: wantsTemplate ?? this.wantsTemplate,
    recurringOccurrenceId: clearOccurrence
        ? null
        : (recurringOccurrenceId ?? this.recurringOccurrenceId),
    accountMissing: accountMissing ?? this.accountMissing,
    createdAssetId: createdAssetId ?? this.createdAssetId,
    sourceEntryIds: sourceEntryIds ?? this.sourceEntryIds,
    split: clearSplit ? null : (split ?? this.split),
    // Cleared by `clearErrors` alongside the other two, so `save`'s `finally` does not leave a stale
    // reason on screen — the defect the `fanOutError` comment above records having been caught twice.
    splitError: clearErrors ? null : (splitError ?? this.splitError),
  );

  /// Builds the entity this state describes.
  ///
  /// [occurredAtUtc] comes from the caller's clock rather than `DateTime.now()`, so a save is
  /// reproducible in a test.
  Transaction toTransaction({
    required String newId,
    required DateTime occurredAtUtc,
  }) => Transaction(
    id: id ?? newId,
    kind: kind,
    subtype: subtype,
    occurredAtUtc: occurredAtUtc,
    dateKey: dateKey,
    originalAmount: amount ?? Money.zero(currencyCode),
    needsReview: needsReview,
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    paymentMethodId: paymentMethodId,
    payeeId: payeeId,
    note: note,
  );

  /// Loads an existing transaction into an editor state.
  static TransactionEditorState fromTransaction(
    Transaction transaction, {
    required List<TransactionLine> lines,
    required Set<String> tagIds,
  }) => TransactionEditorState(
    id: transaction.id,
    kind: transaction.kind,
    subtype: transaction.subtype,
    amount: transaction.originalAmount,
    currencyCode: transaction.originalAmount.currencyCode,
    dateKey: transaction.dateKey,
    fromAccountId: transaction.fromAccountId,
    toAccountId: transaction.toAccountId,
    paymentMethodId: transaction.paymentMethodId,
    payeeId: transaction.payeeId,
    note: transaction.note,
    tagIds: tagIds,
    lines: lines,
    needsReview: transaction.needsReview,
    toOwnAccount: transaction.kind == TransactionKind.transfer,
  );
}
```

### `lib/features/expense/state/transaction_filter.dart`

```dart
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/services/date_range_service.dart';

/// What is currently narrowing the transaction list.
///
/// Immutable, and every field is one the user can see as a chip. A filter the user cannot see is a
/// bug report waiting to happen: a list quietly constrained by a filter set on a previous visit is
/// indistinguishable from a list that lost its data (ARCH_5 §3 archetype C).
///
/// **There is deliberately no tag field.** No 3A contract exposes a tag-to-transactions reverse
/// lookup, so filtering by tag would mean one query per visible row. Recorded as an ARCH_5 §7.3 gap
/// owned by 7B, which builds the analytics read model that needs the same join.
class TransactionFilter {
  /// Creates a filter. The default is the last thirty days, unfiltered otherwise.
  const TransactionFilter({
    this.preset = DateRangePreset.last30Days,
    this.customRange,
    this.kinds = const <TransactionKind>{},
    this.subtypes = const <TransactionSubtype>{},
    this.accountId,
    this.payeeId,
    this.needsReviewOnly = false,
  });

  /// The reporting window, resolved against the clock by `DateRangeService`.
  final DateRangePreset preset;

  /// The window the user picked by hand. Only meaningful when [preset] is custom.
  final DateRange? customRange;

  /// Which kinds to show. Empty means all of them.
  final Set<TransactionKind> kinds;

  /// Which subtypes to show. Empty means all of them.
  final Set<TransactionSubtype> subtypes;

  /// Restrict to transactions touching this account on either side.
  final String? accountId;

  /// Restrict to one counterparty.
  final String? payeeId;

  /// Show only transactions still flagged as needing details.
  ///
  /// What the needs-review nudge switches on. Without it the banner would have nowhere real to
  /// send the user: widening the date window shows the flagged rows *somewhere* in the list rather
  /// than showing the user the work they were just told they had.
  final bool needsReviewOnly;

  /// Whether anything is narrowing the list beyond the default window.
  bool get isNarrowed =>
      preset != DateRangePreset.last30Days ||
      kinds.isNotEmpty ||
      subtypes.isNotEmpty ||
      accountId != null ||
      payeeId != null ||
      needsReviewOnly;

  /// True when [transaction] survives the non-date parts of this filter.
  ///
  /// The date window is applied by the query rather than here — `watchByDateRange` is indexed and
  /// re-filtering its output by date in Dart would be doing the work twice.
  bool admits({
    required TransactionKind kind,
    required TransactionSubtype subtype,
    required String? fromAccountId,
    required String? toAccountId,
    required String? transactionPayeeId,
    required bool needsReview,
  }) {
    if (needsReviewOnly && !needsReview) return false;
    if (kinds.isNotEmpty && !kinds.contains(kind)) return false;
    if (subtypes.isNotEmpty && !subtypes.contains(subtype)) return false;
    if (accountId != null &&
        fromAccountId != accountId &&
        toAccountId != accountId)
      return false;
    if (payeeId != null && transactionPayeeId != payeeId) return false;
    return true;
  }

  /// Returns a copy with the supplied changes.
  ///
  /// The nullable fields take an explicit `clear` flag rather than relying on a null argument, which
  /// would be indistinguishable from "leave it alone" and is the standard way a copyWith quietly
  /// refuses to let a user clear a filter.
  TransactionFilter copyWith({
    DateRangePreset? preset,
    DateRange? customRange,
    bool clearCustomRange = false,
    Set<TransactionKind>? kinds,
    Set<TransactionSubtype>? subtypes,
    String? accountId,
    bool clearAccount = false,
    String? payeeId,
    bool clearPayee = false,
    bool? needsReviewOnly,
  }) => TransactionFilter(
    preset: preset ?? this.preset,
    customRange: clearCustomRange ? null : (customRange ?? this.customRange),
    kinds: kinds ?? this.kinds,
    subtypes: subtypes ?? this.subtypes,
    accountId: clearAccount ? null : (accountId ?? this.accountId),
    payeeId: clearPayee ? null : (payeeId ?? this.payeeId),
    needsReviewOnly: needsReviewOnly ?? this.needsReviewOnly,
  );

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.preset == preset &&
      other.customRange == customRange &&
      other.kinds.length == kinds.length &&
      other.kinds.containsAll(kinds) &&
      other.subtypes.length == subtypes.length &&
      other.subtypes.containsAll(subtypes) &&
      other.accountId == accountId &&
      other.payeeId == payeeId &&
      other.needsReviewOnly == needsReviewOnly;

  @override
  int get hashCode => Object.hash(
    preset,
    customRange,
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(subtypes),
    accountId,
    payeeId,
    needsReviewOnly,
  );
}
```

### `test/features/expense/line_items_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/line_items_screen.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, 320dp at a doubled text scale, and both accessibility floors (ARCH_5 §9.1).
void main() {
  TransactionLine line({
    String id = 'line-1',
    String description = 'Onion',
    int? amountMinor = 4000,
    Qty? quantity,
    TransactionLineDestination destination = TransactionLineDestination.none,
  }) =>
      TransactionLine(
        id: id,
        transactionId: '',
        lineNo: 1,
        description: description,
        destination: destination,
        quantity: quantity,
        lineAmount: amountMinor == null ? null : Money(amountMinor, 'INR'),
      );

  TransactionEditorState state({List<TransactionLine> lines = const [], int? amountMinor = 20000}) =>
      TransactionEditorState(
        currencyCode: 'INR',
        dateKey: kToday,
        amount: amountMinor == null ? null : Money(amountMinor, 'INR'),
        lines: lines,
      );

  // The override goes on the **family**: a NotifierProvider family instance has no `overrideWith`.
  List<Override> overrides(AsyncValue<TransactionEditorState> value) => [
        transactionEditorProvider.overrideWith(() => _StubEditor(value)),
        homeDecimalDigitsProvider.overrideWith((ref) async => 2),
      ];

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the first item and says what happens if you skip it',
      (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Nothing itemised yet'), findsOneWidget);
    // Itemising is optional (anomaly A11), and the empty state has to say so or it reads as a
    // required step blocking the save.
    expect(find.textContaining('Anything you leave out still counts'), findsOneWidget);
  });

  testWidgets('error shows the real reason with a retry', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.error(StateError('boom'), StackTrace.empty)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated lists every line with its figure', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(lines: [line(), line(id: 'line-2', description: 'Tomato', amountMinor: 6000)]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Onion'), findsOneWidget);
    expect(find.text('Tomato'), findsOneWidget);
    expect(find.text('2 items'), findsOneWidget);
  });

  testWidgets('the running figures show what is itemised and what is not', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line()], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    // 200.00 entered, 40.00 itemised. The gap is shown, never auto-balanced (anomaly A11).
    expect(find.text('Itemised'), findsOneWidget);
    expect(find.text('Unallocated'), findsOneWidget);
  });

  testWidgets('a fully itemised transaction shows no unallocated chip', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(state(lines: [line(amountMinor: 20000)], amountMinor: 20000)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Unallocated'), findsNothing);
  });

  testWidgets('an inventory line is marked as one', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('500 g'), findsOneWidget);
  });

  testWidgets('removing a line reports it', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump();
    // No Undo: nothing has been written, so a snack promising undo for an uncommitted edit would be
    // lying (§5.4). It confirms, and stops there.
    expect(find.text('Item removed'), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
  });

  testWidgets('Done leaves without committing anything', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    // The page edits editor state; the transaction is written by the editor's own save.
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsNothing);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(
        AsyncValue.data(
          state(
            lines: [
              line(
                destination: TransactionLineDestination.inventory,
                quantity: const Qty(500000, UnitCategory.weight),
              ),
              line(id: 'line-2', description: 'Tomato', amountMinor: 6000),
            ],
          ),
        ),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const LineItemsScreen(),
      overrides: overrides(AsyncValue.data(state(lines: [line()]))),
    );
    await tester.pumpAndSettle();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}

/// A notifier reporting a fixed state, so each branch can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._value);

  final AsyncValue<TransactionEditorState> _value;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _value;
}
```

### `test/features/expense/overflow_diagnostic_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';

import '../../support/expense_harness.dart';

/// **Throwaway.** Delete this file once the 524px overflow is identified.
///
/// Reading every widget in the offending `Column` accounts for roughly 260px of non-flex height
/// against a 640px viewport, so the reported 1,164px cannot come from where the stack trace points.
/// That means an assumption about the *test* is wrong rather than an assumption about the widgets —
/// so this measures instead of reasoning.
void main() {
  testWidgets('measure the list screen body at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: [
        clockProvider.overrideWithValue(kTestClock),
        transactionDaysProvider.overrideWith(
          (ref) => AsyncValue.data([
            TransactionDayGroup(date: kToday, transactions: [sampleTransaction()]),
          ]),
        ),
        needsReviewCountProvider.overrideWith((ref) => Stream.value(2)),
        accountsByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
        ),
        payeesByIdProvider.overrideWith(
          (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
        ),
        homeDecimalDigitsProvider.overrideWith((ref) => 2),
      ],
      textScale: 2,
    );

    debugPrint('=== ALAYA OVERFLOW DIAGNOSTIC ===');

    // Every direct child of the body Column, in order, with its laid-out size. Whichever of these is
    // not ~60-160px tall is the culprit.
    for (final name in const [
      '_Toolbar',
      '_NeedsReviewRow',
      '_ActiveFilters',
      '_GroupedList',
      '_SearchResults',
    ]) {
      final found = find.byWidgetPredicate((w) => w.runtimeType.toString() == name);
      if (found.evaluate().isEmpty) {
        debugPrint('$name: ABSENT from the tree');
        continue;
      }
      try {
        debugPrint('$name: ${tester.getSize(found.first)}');
      } on Object catch (error) {
        debugPrint('$name: present but unmeasurable -> $error');
      }
    }

    // The Column itself: what it was offered, and what it took.
    final column = find
        .byWidgetPredicate((w) => w is Column && w.children.length >= 2)
        .evaluate()
        .map((e) => e.renderObject)
        .whereType<RenderFlex>()
        .toList();
    for (final flex in column) {
      debugPrint(
        'Column direction=${flex.direction} '
        'constraints=${flex.constraints} '
        'size=${flex.hasSize ? flex.size : "MISSING"}',
      );
    }

    // Which widget actually reported the overflow, and how far.
    final exception = tester.takeException();
    debugPrint('exception: ${exception ?? "none"}');
    debugPrint('=== END DIAGNOSTIC ===');
  });
}
```

### `test/features/expense/quick_add_sheet_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/sheets/quick_add_sheet.dart';
import 'package:alaya/features/expense/providers/quick_add_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/expense_harness.dart';

/// The capture path's contract: one required field, everything else optional, and a rejection that
/// says so out loud rather than doing nothing (Laws U9 and U11).
void main() {
  List<Override> overrides({List<Account> accounts = const [kAccount]}) => [
    homeCurrencyCodeProvider.overrideWith((ref) => 'INR'),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
    selectableAccountsProvider.overrideWith((ref) => Stream.value(accounts)),
    quickAddTagsProvider.overrideWith((ref) => Stream.value(const <Tag>[])),
  ];

  Widget host() => Scaffold(
    body: AlayaBottomSheet(child: const QuickAddSheet()),
  );

  testWidgets('renders with exactly one required field', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('Quick add'), findsOneWidget);
  });

  testWidgets('offers accounts as chips, never a dropdown', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides());
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(find.byType(DropdownButtonFormField<Account>), findsNothing);
  });

  testWidgets('an empty account list simply omits the chip row', (
    tester,
  ) async {
    await pumpExpense(tester, host(), overrides: overrides(accounts: const []));
    expect(find.text('Account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'saving with no amount shakes and says why, rather than doing nothing',
    (tester) async {
      await pumpExpense(tester, host(), overrides: overrides());
      final before = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();

      final after = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;
      expect(after, greaterThan(before));
      expect(find.text('Enter an amount'), findsOneWidget);
    },
  );

  testWidgets('offers a note, and it stays optional', (tester) async {
    // The one detail nobody can reconstruct three months later is what the money was for. A tag says
    // *groceries*; this says *the birthday cake*. It belongs on the fast path because the only moment
    // anybody knows it is at the till.
    await pumpExpense(tester, host(), overrides: overrides());
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'What for? (optional)'),
      findsOneWidget,
    );

    // Still one required field (Law U11): saving with the note untouched must work.
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(tester, host(), overrides: overrides(), textScale: 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target floor', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(tester, host(), overrides: overrides());
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });
}
```

### `test/features/expense/transaction_detail_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_detail_screen.dart';
import 'package:alaya/features/expense/providers/transaction_detail_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/key_value_row.dart';

import '../../support/expense_harness.dart';

/// Four states, plus the two rules this screen exists to demonstrate: a null value renders no row,
/// and the destructive action sits last.
void main() {
  const id = 'tx-1';

  List<Override> overrides(AsyncValue<Transaction?> transaction) => [
    clockProvider.overrideWithValue(kTestClock),
    transactionByIdProvider(
      id,
    ).overrideWith((ref) async => transaction.valueOrNull),
    transactionLinesProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <TransactionLine>[])),
    transactionAllocationProvider(id).overrideWith((ref) => Stream.value(null)),
    transactionTagsProvider(
      id,
    ).overrideWith((ref) => Stream.value(const <Tag>[])),
    paymentMethodsByIdProvider.overrideWith(
      (ref) => Stream.value(const <String, PaymentMethod>{}),
    ),
    accountsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
    ),
    payeesByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
    ),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(
          id,
        ).overrideWith((ref) => pendingFuture<Transaction?>()),
      ],
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('a missing transaction reads as not found, not as a crash', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(const AsyncValue.data(null)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EmptyState), findsOneWidget);
    expect(find.text('Not found'), findsOneWidget);
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: [
        ...overrides(const AsyncValue.loading()),
        transactionByIdProvider(
          id,
        ).overrideWith((ref) async => throw StateError('boom')),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('populated renders the hero and hides rows with no value', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reliance Fresh'), findsOneWidget);
    // The sample has no note and no payment method, so neither row exists at all — a screen of
    // dashes reads as broken data rather than as a record with optional fields.
    expect(find.text('Note'), findsNothing);
    expect(find.text('Payment method'), findsNothing);
    expect(find.byType(KeyValueRow), findsWidgets);
  });

  testWidgets('the destructive action is present and is not a filled button', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(AsyncValue.data(sampleTransaction())),
    );
    await tester.pumpAndSettle();
    // The screen is a ListView and the destructive action is deliberately its last child, so on a
    // 320x640 viewport it is not built until scrolled to. That it sits below everything else is the
    // point (ARCH_5 §5.5) — the test travels to it rather than assuming it is on screen.
    await tester.scrollUntilVisible(
      find.text('Delete transaction'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextButton, 'Delete transaction'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Delete transaction'),
      findsNothing,
    );
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionDetailScreen(transactionId: id),
      overrides: overrides(
        AsyncValue.data(sampleTransaction(needsReview: true)),
      ),
      textScale: 2,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
```

### `test/features/expense/transaction_editor_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_editor_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/deposit_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/grocery_form.dart';
import 'package:alaya/features/expense/presentation/widgets/subtype_forms/transfer_form.dart';
import 'package:alaya/features/expense/providers/transaction_editor_providers.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// The editor's four states, and the two behaviours the phase brief singles out: the sub-form
/// switches on subtype, and the commit lives in the footer rather than the app bar.
void main() {
  TransactionEditorState seed({
    TransactionKind kind = TransactionKind.withdrawal,
    TransactionSubtype subtype = TransactionSubtype.grocery,
    Set<String> tagIds = const {},
    String? note,
    String? fromAccountId,
  }) => TransactionEditorState(
    currencyCode: 'INR',
    dateKey: kToday,
    kind: kind,
    subtype: subtype,
    tagIds: tagIds,
    note: note,
    fromAccountId: fromAccountId,
  );

  // The override goes on the **family**, not on an instance of it. A NotifierProvider family
  // instance has no `overrideWith` — unlike a FutureProvider or StreamProvider instance, which do.
  // Overriding the family replaces every instance, which is what this test wants anyway.
  List<Override> overrides(AsyncValue<TransactionEditorState> state) => [
    transactionEditorProvider.overrideWith(() => _StubEditor(state)),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
    selectableAccountsProvider.overrideWith(
      (ref) => Stream.value(const [kAccount]),
    ),
    editorPaymentMethodsProvider.overrideWith(
      (ref) => Stream.value(const <PaymentMethod>[]),
    ),
    editorPayeesProvider.overrideWith((ref) => Stream.value(const [kPayee])),
    for (final kind in TransactionKind.values)
      editorTagsProvider(
        kind,
      ).overrideWith((ref) => Stream.value(const <Tag>[])),
  ];

  testWidgets('loading shows a skeleton', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
  });

  testWidgets('error reads as not found rather than as a blank form', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('a new transaction opens on the form, which is its empty state', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(find.byType(AlayaFormScaffold), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save expense'), findsOneWidget);
  });

  group('more details', () {
    testWidgets('a blank record shows the door closed', (tester) async {
      // Amount, date and category are what a purchase needs. The rest is behind one row — the
      // eleven-controls-at-once density is what made this screen hard to read (ARCH_5 §2.6b).
      await pumpExpense(
        tester,
        const TransactionEditorScreen(),
        overrides: overrides(AsyncValue.data(seed())),
      );
      await tester.pumpAndSettle();
      expect(find.text('More details'), findsOneWidget);
      // 'NOTE', not 'Note': `SectionHeader` renders `label.toUpperCase()`. My first version of this
      // assertion looked for 'Note' and therefore passed whether the door was open or shut — a
      // vacuous check dressed as a real one.
      expect(find.text('NOTE'), findsNothing);
    });

    testWidgets('tapping the row reveals every field, none removed', (
      tester,
    ) async {
      // The functionality is unchanged — this asserts it. Nothing was deleted to make the screen
      // calmer; it is one tap further away.
      await pumpExpense(
        tester,
        const TransactionEditorScreen(),
        overrides: overrides(AsyncValue.data(seed())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('More details'));
      await tester.pumpAndSettle();
      expect(find.text('NOTE'), findsOneWidget);
      expect(find.text('WHERE IT WENT'), findsOneWidget);
    });

    testWidgets('a record with a note opens the door on arrival', (
      tester,
    ) async {
      // **The rule that makes collapsing honest.** Without it somebody sets a note, saves, reopens,
      // and their note is behind a chevron with nothing to suggest it exists.
      await pumpExpense(
        tester,
        const TransactionEditorScreen(),
        overrides: overrides(AsyncValue.data(seed(note: 'paid in cash'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('NOTE'), findsOneWidget);
    });

    testWidgets('a closed door says what is behind it', (tester) async {
      // **An account, not tags.** Tags count as content and open the door, so a summary test seeded
      // with them can never observe the collapsed row — my first version asserted a string that only
      // renders while closed, on a state that guarantees it is open.
      //
      // An account carries a settings default, so it deliberately does *not* open the door — and it
      // still appears in the summary. That combination is exactly what this test needs.
      await pumpExpense(
        tester,
        const TransactionEditorScreen(),
        overrides: overrides(
          AsyncValue.data(seed(fromAccountId: kAccount.id)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NOTE'), findsNothing, reason: 'the door must be shut');
      expect(find.textContaining(kAccount.name), findsWidgets);
    });
  });

  testWidgets('a grocery withdrawal shows the grocery form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    // The subtype form moved behind the door in the density pass. The behaviour is unchanged —
    // it is one tap further in, and this asserts both that the tap works and that the form is intact.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.byType(GroceryForm), findsOneWidget);
    expect(find.byType(DepositForm), findsNothing);
  });

  testWidgets('a salary deposit shows the deposit form', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(
            kind: TransactionKind.deposit,
            subtype: TransactionSubtype.salaryIn,
          ),
        ),
      ),
    );
    // The subtype form moved behind the door in the density pass. The behaviour is unchanged —
    // it is one tap further in, and this asserts both that the tap works and that the form is intact.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.byType(DepositForm), findsOneWidget);
    expect(find.byType(GroceryForm), findsNothing);
  });

  testWidgets('a transfer shows the two-option toggle, not a payee-only form', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(
        AsyncValue.data(
          seed(
            kind: TransactionKind.transfer,
            subtype: TransactionSubtype.transferSelf,
          ),
        ),
      ),
    );
    // The subtype form moved behind the door in the density pass. The behaviour is unchanged —
    // it is one tap further in, and this asserts both that the tap works and that the form is intact.
    await tester.tap(find.text('More details'));
    await tester.pumpAndSettle();
    expect(find.byType(TransferForm), findsOneWidget);
    expect(find.text('To my own account'), findsOneWidget);
    expect(find.text('To someone else'), findsOneWidget);
    // The copy states the consequence rather than the mechanism — anomaly A02's whole point.
    expect(
      find.text(
        'Moves money between your accounts. Your total does not change.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the commit lives in the footer, never in the app bar', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
    );
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithText(TextButton, 'Save expense'),
      ),
      findsNothing,
    );
    expect(find.byType(CloseButton), findsOneWidget);
  });

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionEditorScreen(),
      overrides: overrides(AsyncValue.data(seed())),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}

/// A notifier reporting a fixed state, so each of the four branches can be pumped directly.
class _StubEditor extends TransactionEditorNotifier {
  _StubEditor(this._state);

  final AsyncValue<TransactionEditorState> _state;

  @override
  AsyncValue<TransactionEditorState> build(String? arg) => _state;
}
```

### `test/features/expense/transaction_editor_state_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/transaction.dart';
import 'package:alaya/domain/entities/transaction_line.dart';
import 'package:alaya/features/expense/state/transaction_editor_state.dart';

/// Pure unit tests for the editor's state — no widgets, no providers, no database.
///
/// This is where the rules that would otherwise only be visible through the UI get asserted: the
/// subtypes a kind may take, the unallocated arithmetic that must never auto-balance, and the
/// copyWith clear flags that are the difference between "leave it alone" and "the user cleared it".
void main() {
  const inr = 'INR';
  const today = DateKey(20260801);

  TransactionEditorState seed({
    TransactionKind kind = TransactionKind.withdrawal,
    TransactionSubtype subtype = TransactionSubtype.grocery,
    Money? amount,
    List<TransactionLine> lines = const [],
  }) => TransactionEditorState(
    currencyCode: inr,
    dateKey: today,
    kind: kind,
    subtype: subtype,
    amount: amount,
    lines: lines,
  );

  TransactionLine line(String id, int minor) => TransactionLine(
    id: id,
    transactionId: 'tx-1',
    lineNo: 1,
    description: 'Potatoes',
    destination: TransactionLineDestination.inventory,
    lineAmount: Money(minor, inr),
  );

  group('availableSubtypes', () {
    test('a deposit cannot be a grocery purchase', () {
      final subtypes = seed(kind: TransactionKind.deposit).availableSubtypes;
      expect(subtypes, contains(TransactionSubtype.salaryIn));
      expect(subtypes, isNot(contains(TransactionSubtype.grocery)));
    });

    test('a transfer has exactly one', () {
      expect(
        seed(kind: TransactionKind.transfer).availableSubtypes,
        [TransactionSubtype.transferSelf],
      );
    });

    test('a withdrawal offers the six spending shapes', () {
      final subtypes = seed().availableSubtypes;
      expect(subtypes, hasLength(6));
      expect(subtypes, contains(TransactionSubtype.electronics));
      expect(subtypes, contains(TransactionSubtype.transferOut));
    });

    test('every kind offers at least one, so the picker is never empty', () {
      for (final kind in TransactionKind.values) {
        expect(
          seed(kind: kind).availableSubtypes,
          isNotEmpty,
          reason: kind.name,
        );
      }
    });
  });

  group('allocation', () {
    test('no lines means no total and nothing unallocated', () {
      final state = seed(amount: const Money(50000, inr));
      expect(state.lineTotal, isNull);
      // With no lines at all the difference equals the whole amount, which is not a mismatch —
      // showing a chip here would accuse the user of an error they have not made (anomaly A11).
      expect(state.unallocated, isNull);
    });

    test('lines that sum to the amount leave nothing unallocated', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [line('l1', 30000), line('l2', 20000)],
      );
      expect(state.lineTotal, const Money(50000, inr));
      expect(state.unallocated, isNull);
    });

    test('a shortfall is reported and never balanced away', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [line('l1', 48000)],
      );
      expect(state.unallocated, const Money(2000, inr));
      // The lines are untouched: the transaction amount is the source of truth and the lines are
      // optional detail, so forcing them equal would invent a purchase.
      expect(state.lineTotal, const Money(48000, inr));
    });

    test(
      'lines exceeding the amount give a negative difference rather than zero',
      () {
        final state = seed(
          amount: const Money(50000, inr),
          lines: [line('l1', 60000)],
        );
        expect(state.unallocated, const Money(-10000, inr));
      },
    );

    test('a line with no amount contributes nothing', () {
      final state = seed(
        amount: const Money(50000, inr),
        lines: [
          const TransactionLine(
            id: 'l1',
            transactionId: 'tx-1',
            lineNo: 1,
            description: 'Unpriced',
            destination: TransactionLineDestination.none,
          ),
        ],
      );
      expect(state.lineTotal, Money.zero(inr));
      expect(state.unallocated, const Money(50000, inr));
    });
  });

  group('copyWith', () {
    test('marks the state dirty by default, for the unsaved-changes guard', () {
      expect(seed().dirty, isFalse);
      expect(seed().copyWith(subtype: TransactionSubtype.bill).dirty, isTrue);
    });

    test(
      'an explicit dirty:false wins, so a completed save can clear the guard',
      () {
        expect(seed().copyWith(dirty: false).dirty, isFalse);
      },
    );

    test('a null argument leaves a nullable field alone', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith().amount, const Money(1000, inr));
    });

    test('a clear flag is what actually clears one', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith(clearAmount: true).amount, isNull);
    });

    test('clearing one nullable does not disturb the others', () {
      final state = seed().copyWith(
        fromAccountId: 'acc-1',
        payeeId: 'pay-1',
        paymentMethodId: 'pm-1',
      );
      final cleared = state.copyWith(clearPayee: true);
      expect(cleared.payeeId, isNull);
      expect(cleared.fromAccountId, 'acc-1');
      expect(cleared.paymentMethodId, 'pm-1');
    });

    test('the currency survives every copy — Law L9 has no setter for it', () {
      final state = seed(amount: const Money(1000, inr));
      expect(state.copyWith(amount: const Money(2000, inr)).currencyCode, inr);
    });
  });

  group('toTransaction', () {
    test(
      'uses the supplied id when creating and keeps its own when editing',
      () {
        final when = DateTime.utc(2026, 8, 1, 4);
        final created = seed(
          amount: const Money(1000, inr),
        ).toTransaction(newId: 'new-1', occurredAtUtc: when);
        expect(created.id, 'new-1');

        final editing = seed(
          amount: const Money(1000, inr),
        ).copyWith(id: 'tx-9');
        expect(
          editing.toTransaction(newId: 'new-1', occurredAtUtc: when).id,
          'tx-9',
        );
      },
    );

    test('a missing amount becomes zero rather than throwing', () {
      // save() rejects a null amount before ever calling this, but the entity cannot hold null —
      // so the fallback exists and is asserted rather than left to chance.
      final built = seed().toTransaction(
        newId: 'new-1',
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      );
      expect(built.originalAmount, Money.zero(inr));
    });

    test('the date carries through as a civil date', () {
      final built = seed(amount: const Money(1000, inr)).toTransaction(
        newId: 'new-1',
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      );
      expect(built.dateKey, today);
      expect(built.monthKey, 202608);
    });
  });

  group('fromTransaction', () {
    final source = Transaction(
      id: 'tx-1',
      kind: TransactionKind.transfer,
      subtype: TransactionSubtype.transferSelf,
      occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
      dateKey: today,
      originalAmount: const Money(500000, inr),
      needsReview: true,
      fromAccountId: 'acc-1',
      toAccountId: 'acc-2',
    );

    test('round trips the fields the editor owns', () {
      final state = TransactionEditorState.fromTransaction(
        source,
        lines: const [],
        tagIds: const {'tag-1'},
      );
      expect(state.id, 'tx-1');
      expect(state.amount, const Money(500000, inr));
      expect(state.currencyCode, inr);
      expect(state.needsReview, isTrue);
      expect(state.tagIds, {'tag-1'});
      expect(state.isEditing, isTrue);
    });

    test(
      'opens clean, so loading a record does not trip the unsaved guard',
      () {
        final state = TransactionEditorState.fromTransaction(
          source,
          lines: const [],
          tagIds: const {},
        );
        expect(state.dirty, isFalse);
      },
    );

    test('a transfer loads with the own-account toggle already set', () {
      final state = TransactionEditorState.fromTransaction(
        source,
        lines: const [],
        tagIds: const {},
      );
      expect(state.toOwnAccount, isTrue);
    });

    test('a withdrawal does not', () {
      final withdrawal = Transaction(
        id: 'tx-2',
        kind: TransactionKind.withdrawal,
        subtype: TransactionSubtype.grocery,
        occurredAtUtc: DateTime.utc(2026, 8, 1, 4),
        dateKey: today,
        originalAmount: const Money(1000, inr),
        needsReview: false,
        fromAccountId: 'acc-1',
      );
      final state = TransactionEditorState.fromTransaction(
        withdrawal,
        lines: const [],
        tagIds: const {},
      );
      expect(state.toOwnAccount, isFalse);
    });
  });
}
```

### `test/features/expense/transaction_list_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/expense/presentation/screens/transaction_list_screen.dart';
import 'package:alaya/features/expense/presentation/widgets/needs_review_banner.dart';
import 'package:alaya/features/expense/presentation/widgets/transaction_row.dart';
import 'package:alaya/features/expense/providers/transaction_list_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/expense_harness.dart';

/// Four states, a narrow viewport at a doubled text scale, and the tap-target floor (ARCH_5 §9.1).
void main() {
  List<Override> overrides(
    AsyncValue<List<TransactionDayGroup>> days, {
    int needsReview = 0,
  }) => [
    clockProvider.overrideWithValue(kTestClock),
    transactionDaysProvider.overrideWith((ref) => days),
    needsReviewCountProvider.overrideWith((ref) => Stream.value(needsReview)),
    accountsByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Account>{kAccount.id: kAccount}),
    ),
    payeesByIdProvider.overrideWith(
      (ref) => Stream.value(<String, Payee>{kPayee.id: kPayee}),
    ),
    homeDecimalDigitsProvider.overrideWith((ref) => 2),
  ];

  final populated = AsyncValue.data([
    TransactionDayGroup(date: kToday, transactions: [sampleTransaction()]),
  ]);

  testWidgets('loading shows a skeleton, not a spinner', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.loading()),
    );
    expect(find.byType(AlayaListSkeleton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('empty invites the user to act rather than reporting emptiness', (
    tester,
  ) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(const AsyncValue.data([])),
    );
    expect(find.byType(EmptyState), findsOneWidget);
    expect(
      find.text('Add your first expense and it will appear here.'),
      findsOneWidget,
    );
  });

  testWidgets('error offers a retry', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(
        AsyncValue.error(StateError('boom'), StackTrace.empty),
      ),
    );
    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('populated renders a row per transaction', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(TransactionRow), findsOneWidget);
    expect(find.text('Reliance Fresh'), findsOneWidget);
  });

  testWidgets('the needs-review nudge is absent at zero', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    expect(find.byType(NeedsReviewBanner), findsOneWidget);
    // The banner widget is present but renders nothing: a nudge that says "0 need details" is
    // noise, and hiding it is the widget's own job rather than the screen's.
    expect(find.text('Review'), findsNothing);
  });

  testWidgets(
    'the needs-review nudge counts and offers the action above zero',
    (tester) async {
      await pumpExpense(
        tester,
        const TransactionListScreen(),
        overrides: overrides(populated, needsReview: 3),
      );
      expect(find.text('3 transactions need details'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
    },
  );

  testWidgets('survives 320dp at a doubled text scale', (tester) async {
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated, needsReview: 2),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every target meets the tap-target and labelling floors', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpExpense(
      tester,
      const TransactionListScreen(),
      overrides: overrides(populated),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
```
