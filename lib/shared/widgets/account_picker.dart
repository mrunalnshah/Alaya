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
