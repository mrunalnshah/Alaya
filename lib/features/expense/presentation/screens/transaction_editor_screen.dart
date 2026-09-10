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
