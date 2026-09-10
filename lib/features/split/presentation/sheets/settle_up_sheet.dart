import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/core/time/date_key_labels.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/split/providers/settle_up_provider.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/account_picker.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Records money changing hands to settle a debt (ARCH_5 §3 archetype A).
///
/// **The account is required, and that is the module's central claim made concrete.** A settlement you
/// are part of moved your money, so it writes a real `transactions` row in the same database
/// transaction as the settlement itself — the deposit lands in an account you choose and is spendable
/// from that instant, with no separate split wallet to reconcile. Splitwise's "settle up" is a
/// bookkeeping marker it cannot back with anything; this one has to name where the money went.
///
/// **The amount defaults to the whole balance and stays editable**, which is what makes partial
/// settlement work: "keep adding as they keep paying" needs no special mode, only more rows, because
/// what remains outstanding is derived rather than decremented (Law L3).
///
/// **The ledger row now says what it was for.** A settlement writes an ordinary deposit or withdrawal, and it
/// used to carry whatever note the user typed — which was nothing, because this sheet has no note field. So a
/// month later the ledger held an unexplained ₹1,850 arriving in a bank account, and the only way to find out
/// what it was involved opening the split module and matching amounts by eye. See [_noteFor].
class SettleUpSheet extends ConsumerStatefulWidget {
  /// Settles with [payeeId] for [outstanding].
  const SettleUpSheet({
    required this.payeeId,
    required this.payeeName,
    required this.outstanding,
    required this.theyOweMe,
    this.groupId,
    super.key,
  });

  /// The counterparty.
  final String payeeId;

  /// Their display name, resolved by the caller.
  final String payeeName;

  /// What is outstanding, without its direction.
  final Money outstanding;

  /// Whether they owe the user, rather than the other way round.
  final bool theyOweMe;

  /// The group this settles within, or null for a one-off debt.
  final String? groupId;

  /// Opens the sheet, resolving to true when a settlement was recorded.
  static Future<bool?> show(
    BuildContext context, {
    required String payeeId,
    required String payeeName,
    required Money outstanding,
    required bool theyOweMe,
    String? groupId,
  }) => AlayaBottomSheet.show<bool>(
    context: context,
    builder: (context) => SettleUpSheet(
      payeeId: payeeId,
      payeeName: payeeName,
      outstanding: outstanding,
      theyOweMe: theyOweMe,
      groupId: groupId,
    ),
  );

  @override
  ConsumerState<SettleUpSheet> createState() => _SettleUpSheetState();
}

class _SettleUpSheetState extends ConsumerState<SettleUpSheet> {
  late Money? _amount = widget.outstanding;
  String? _error;
  String? _accountId;
  String? _paymentMethodId;
  DateKey? _on;
  bool _submitting = false;

  /// What the ledger row will say.
  ///
  /// **Composed here because this is the only layer that has both halves.** The words need the ARB, which needs
  /// a `BuildContext`; the counterparty's name is already on this widget. `SettleUp` has neither, and
  /// `SettlementService` has payee *ids* and a group repository rather than names — so anything either of them
  /// produced would be an id or a placeholder.
  ///
  /// **The direction is stated in words, not implied by a sign.** A ledger shows a deposit and a withdrawal
  /// differently already, but "Ravi paid you back" and "You paid Ravi back" are the sentences somebody scanning
  /// a month of transactions actually reads, and they answer the question the amount cannot.
  ///
  /// **The group is named when there is one**, because *"Ravi paid you back — Flatmates"* separates the rent
  /// from the dinner without opening anything. It is read from the group already loaded for this module rather
  /// than fetched: `splitAllGroupsProvider` is watched by every split screen, so this costs no query.
  ///
  /// A stored sentence freezes in the language it was written in — switch to Hindi next year and old notes stay
  /// English. Accepted deliberately: the alternative is a note with no words, and an unreadable ledger row is
  /// the thing this exists to fix.
  String _noteFor(AlayaStrings strings) {
    final group = widget.groupId == null
        ? null
        : ref.read(splitGroupProvider(widget.groupId!)).valueOrNull?.name;

    if (group == null || group.trim().isEmpty) {
      return widget.theyOweMe
          ? strings.splitSettleNoteFrom(widget.payeeName)
          : strings.splitSettleNoteTo(widget.payeeName);
    }
    return widget.theyOweMe
        ? strings.splitSettleNoteFromIn(widget.payeeName, group)
        : strings.splitSettleNoteToIn(widget.payeeName, group);
  }

  Future<void> _settle() async {
    final strings = AlayaStrings.of(context);
    final amount = _amount;
    final accountId = _accountId;
    if (amount == null || accountId == null) return;

    setState(() => _submitting = true);
    final result = await ref
        .read(settleUpProvider.notifier)
        .settle(
          payeeId: widget.payeeId,
          theyOweMe: widget.theyOweMe,
          amount: amount,
          accountId: accountId,
          groupId: widget.groupId,
          paymentMethodId: _paymentMethodId,
          note: _noteFor(strings),
          on: _on,
        );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (!result) {
      // The service's own sentence. "Choose which person is you" and "that account is in USD, not INR"
      // are different problems with different remedies, and collapsing them into one message is what
      // makes a sheet impossible to get past (Law U9).
      final why = ref.read(settleUpProvider.notifier).lastError;
      setState(() => _error = why ?? strings.errorBodyGeneric);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final digits = ref.watch(splitDecimalDigitsProvider).valueOrNull ?? 2;
    final accounts =
        ref.watch(splitAccountsProvider).valueOrNull ?? const <Account>[];
    final methods =
        ref.watch(splitPaymentMethodsProvider).valueOrNull ??
        const <PaymentMethod>[];

    Account? accountFor(String? id) {
      for (final account in accounts) {
        if (account.id == id) return account;
      }
      return null;
    }

    final over = _amount != null && _amount! > widget.outstanding;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.theyOweMe
              ? strings.splitSettleFrom(widget.payeeName)
              : strings.splitSettleTo(widget.payeeName),
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.xxs),
        // A `Wrap`, not a `Row`: a label beside an amount is the shape that overflows at 320dp with the text
        // scaler doubled, and an `AmountText` cannot shrink below its own text (Law U15).
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AlayaSpacing.xs,
          children: [
            Text(
              strings.splitOutstandingLabel,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            AmountText(
              widget.outstanding,
              size: AmountSize.small,
              showSign: false,
              decimalDigits: digits,
            ),
          ],
        ),

        const SizedBox(height: AlayaSpacing.lg),
        AmountField(
          currencyCode: widget.outstanding.currencyCode,
          decimalDigits: digits,
          label: strings.splitSettleAmount,
          initialValue: _amount,
          onChanged: (value) => setState(() => _amount = value),
        ),
        if (over) ...[
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            // **Warned, not blocked.** Paying more than the balance is a real thing to do — rounding up,
            // or covering something not yet entered — and the extra simply flips the balance the other
            // way, which the ledger represents perfectly well. Refusing it would be inventing a rule
            // the data does not have.
            strings.splitSettleOverpay,
            style: AlayaTypography.caption.copyWith(color: semantic.warning),
          ),
        ],

        SectionHeader(
          label: widget.theyOweMe
              ? strings.splitSettleIntoAccount
              : strings.splitSettleFromAccount,
          padding: const EdgeInsets.only(
            top: AlayaSpacing.lg,
            bottom: AlayaSpacing.xs,
          ),
        ),
        AccountPicker(
          accounts: accounts,
          selected: accountFor(_accountId),
          label: strings.labelAccount,
          hint: strings.hintSelectAccount,
          onChanged: (account) => setState(() => _accountId = account.id),
        ),

        const SizedBox(height: AlayaSpacing.md),
        DropdownButtonFormField<String>(
          key: ValueKey(_paymentMethodId),
          initialValue: _paymentMethodId,
          isExpanded: true,
          decoration: InputDecoration(labelText: strings.labelPaymentMethod),
          items: [
            for (final method in methods)
              DropdownMenuItem(value: method.id, child: Text(method.name)),
          ],
          onChanged: (id) => setState(() => _paymentMethodId = id),
        ),

        const SizedBox(height: AlayaSpacing.md),
        DatePickerField(
          value: _on ?? ref.read(splitTodayProvider),
          label: strings.labelDate,
          formatted: (date) => date.fullLabel,
          onChanged: (date) => setState(() => _on = date),
        ),

        if (_error != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            _error!,
            style: AlayaTypography.caption.copyWith(color: semantic.danger),
          ),
        ],

        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _submitting || _amount == null || _accountId == null
              ? null
              : _settle,
          child: Text(strings.splitSettleAction),
        ),
      ],
    );
  }
}
