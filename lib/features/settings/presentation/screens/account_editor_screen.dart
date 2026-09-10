import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one account (ARCH_5 §3 archetype B).
///
/// **The opening balance and its date are one field pair, never one alone** (anomaly A03). A balance with no
/// date cannot be placed in a ledger, so every transaction before it would be silently unaccounted for — which
/// is why the date is required rather than defaulted and hidden.
///
/// **Archiving lives here, and deleting does not.** An account is named by every transaction that ever used it;
/// `AccountRepository.delete` exists for a mis-created row, but a screen that offers both makes the
/// irreversible one look like a tidier version of the safe one (ARCH_3 §4, ARCH_5 §5.5).
class AccountEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [accountId] null means a new account.
  const AccountEditorScreen({this.accountId, super.key});

  /// The account being edited, or null for a new one.
  final String? accountId;

  @override
  ConsumerState<AccountEditorScreen> createState() =>
      _AccountEditorScreenState();
}

class _AccountEditorScreenState extends ConsumerState<AccountEditorScreen> {
  final _name = TextEditingController();
  AccountKind _kind = AccountKind.cash;
  String? _currency;
  int _openingMinor = 0;
  DateKey? _openingDate;
  bool _includeInNetWorth = true;
  bool _isArchived = false;
  int _sortOrder = 0;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Fills the form from [account] once, so a rebuild cannot overwrite what the user has typed.
  void _adopt(Account? account, String homeCurrency, DateKey today) {
    if (_loaded) return;
    _loaded = true;
    if (account == null) {
      _currency = homeCurrency;
      _openingDate = today;
      return;
    }
    _name.text = account.name;
    _kind = account.kind;
    _currency = account.currencyCode;
    _openingMinor = account.openingBalance.minor;
    _openingDate = account.openingBalanceDateKey;
    _includeInNetWorth = account.includeInNetWorth;
    _isArchived = account.isArchived;
    _sortOrder = account.sortOrder;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(accountDraftProvider(widget.accountId));
    final editing = ref.watch(accountEditorProvider);
    final home = ref.watch(onboardingCurrenciesProvider).valueOrNull;
    final homeCode =
        ref.watch(accountsHomeCurrencyProvider).valueOrNull ?? 'INR';

    return draft.when(
      loading: () => Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(strings.accountEditorTitle),
        ),
        body: Center(
          child: Text(
            strings.accountsLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          ),
        ),
      ),
      error: (error, stack) => Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(strings.accountEditorTitle),
        ),
        body: ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(accountDraftProvider(widget.accountId)),
        ),
      ),
      data: (account) {
        // Empty, in the one sense an editor has one: the route named an account that is not there — a stale
        // deep link, or a row removed in another window. It says so rather than rendering a blank form that
        // would silently create a second account on save.
        if (widget.accountId != null && account == null) {
          return Scaffold(
            appBar: AppBar(
              leading: const CloseButton(),
              title: Text(strings.accountEditorTitle),
            ),
            body: ErrorState(
              title: strings.accountsMissingTitle,
              body: strings.accountsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(account, homeCode, ref.read(clockProvider).today());

        final currencies = home ?? const <Currency>[];
        final canSave =
            _name.text.trim().isNotEmpty &&
            _currency != null &&
            _openingDate != null;

        return Scaffold(
          appBar: AppBar(
            leading: const CloseButton(),
            title: Text(
              account == null
                  ? strings.accountEditorTitle
                  : strings.accountEditorEditTitle,
            ),
          ),
          body: AlayaFormScaffold(
            primaryLabel: strings.accountEditorSave,
            onPrimary: canSave && !editing.isLoading
                ? () => _save(account)
                : null,
            isDirty: _dirty,
            isSubmitting: editing.isLoading,
            discardTitle: strings.confirmDiscardTitle,
            discardBody: strings.confirmDiscardBody,
            discardConfirmLabel: strings.actionDiscard,
            discardCancelLabel: strings.actionKeepEditing,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  autofocus: account == null,
                  decoration: InputDecoration(
                    labelText: strings.accountNameLabel,
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.md),
                SectionHeader(label: strings.accountKindHeader),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final kind in AccountKind.values)
                      ChoiceChip(
                        label: Text(
                          _kindLabel(strings, kind),
                          style: AlayaTypography.button,
                        ),
                        selected: kind == _kind,
                        onSelected: (_) => setState(() {
                          _kind = kind;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.md),
                SectionHeader(label: strings.accountCurrencyHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                // Law L9 again, where it bites hardest: an account's currency is what its money *is*, not how
                // totals are displayed. Changing it after transactions exist would reinterpret every one of
                // them, so it is offered only while the account is new.
                Text(
                  account == null
                      ? strings.accountCurrencyNewHelp
                      : strings.accountCurrencyLockedHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final currency in currencies)
                      ChoiceChip(
                        label: Text(
                          currency.code,
                          style: AlayaTypography.button,
                        ),
                        selected: currency.code == _currency,
                        onSelected: account == null
                            ? (_) => setState(() {
                                _currency = currency.code;
                                _dirty = true;
                              })
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.md),
                if (_currency != null)
                  AmountField(
                    currencyCode: _currency!,
                    decimalDigits:
                        ref
                            .watch(onboardingCurrencyDigitsProvider(_currency!))
                            .valueOrNull ??
                        2,
                    initialValue: Money(_openingMinor, _currency!),
                    label: strings.accountOpeningBalanceLabel,
                    allowNegative: true,
                    onChanged: (money) => setState(() {
                      _openingMinor = money?.minor ?? 0;
                      _dirty = true;
                    }),
                  ),
                const SizedBox(height: AlayaSpacing.md),
                if (_openingDate != null)
                  DatePickerField(
                    value: _openingDate,
                    label: strings.accountOpeningDateLabel,
                    // A formatter, not a formatted string: `formatted` is `String Function(DateKey)`, so it
                    // formats whichever date the picker lands on rather than the one that was there when
                    // this built.
                    formatted: (date) => DateFormat.yMMMd(
                      Localizations.localeOf(context).toLanguageTag(),
                    ).format(date.toUtcMidnight()),
                    onChanged: (date) => setState(() {
                      _openingDate = date;
                      _dirty = true;
                    }),
                  ),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.onboardingOpeningNote,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.md),
                SwitchListTile(
                  value: _includeInNetWorth,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    strings.accountIncludeInNetWorth,
                    style: AlayaTypography.body,
                  ),
                  subtitle: Text(
                    strings.accountIncludeInNetWorthHelp,
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _includeInNetWorth = value;
                    _dirty = true;
                  }),
                ),
                if (account != null) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  // Last and quiet, per ARCH_5 §5.5 — and an `OutlinedButton`, never the filled one that saves.
                  OutlinedButton(
                    onPressed: editing.isLoading
                        ? null
                        : () => _toggleArchive(account),
                    child: Text(
                      _isArchived
                          ? strings.accountsRestore
                          : strings.accountsArchive,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.accountsArchiveHelp,
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    editing.error.toString(),
                    style: AlayaTypography.body.copyWith(
                      color: context.semantic.danger,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _save(Account? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(accountEditorProvider.notifier)
        .save(
          id: existing?.id,
          name: _name.text,
          kind: _kind,
          currencyCode: _currency!,
          openingMinor: _openingMinor,
          openingDate: _openingDate!,
          includeInNetWorth: _includeInNetWorth,
          isArchived: _isArchived,
          sortOrder: _sortOrder,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.accountsSaved);
    context.pop();
  }

  Future<void> _toggleArchive(Account account) async {
    final strings = AlayaStrings.of(context);
    final next = !_isArchived;
    // Confirmed in both directions. Archiving removes an account from every picker, which a user who meant to
    // tidy a list will not have predicted; restoring puts it back into all of them, which is equally worth
    // stating before it happens.
    final confirmed = await ConfirmSheet.show(
      context,
      title: next
          ? strings.accountsArchiveConfirmTitle
          : strings.accountsRestoreConfirmTitle,
      body: next
          ? strings.accountsArchiveConfirmBody
          : strings.accountsRestoreConfirmBody,
      confirmLabel: next ? strings.accountsArchive : strings.accountsRestore,
      cancelLabel: strings.actionCancel,
      destructive: next,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref
        .read(accountEditorProvider.notifier)
        .setArchived(id: account.id, isArchived: next);
    if (!mounted || !ok) return;
    setState(() => _isArchived = next);
    showResultSnack(
      context,
      message: next ? strings.accountsArchived : strings.accountsRestored,
    );
  }

  String _kindLabel(AlayaStrings strings, AccountKind kind) => switch (kind) {
    AccountKind.cash => strings.accountKindCash,
    AccountKind.bank => strings.accountKindBank,
    AccountKind.wallet => strings.accountKindWallet,
    AccountKind.card => strings.accountKindCard,
    AccountKind.other => strings.accountKindOther,
  };
}
