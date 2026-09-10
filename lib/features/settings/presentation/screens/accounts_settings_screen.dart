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
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/amount_text.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Accounts (ARCH_5 §3 archetype D, outside the shell).
///
/// **Outside the shell, so it brings its own `Scaffold` and gets a back arrow** — it is reached *from*
/// `/settings`, and `AppBar` resolves `hasDrawer` before `canPop`, so rendering it inside the shell would put
/// a hamburger where back belongs (Law U18).
///
/// **Archived accounts are listed, in their own group.** Every picker in the app hides them (ARCH_3 §4), which
/// makes this the only place one can be found and restored — and an account the user cannot find is one they
/// will recreate by hand, splitting a history that was meant to be one thing.
///
/// **No delete action anywhere on this screen.** `AccountRepository.delete` exists, but an account is named by
/// every transaction that ever used it; archiving is the answer the schema is built for, and offering both
/// side by side would make the destructive one look like a tidier version of the safe one.
class AccountsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AccountsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final accounts = ref.watch(accountsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAccounts)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.accountNew),
        tooltip: strings.accountsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: accounts.when(
        // A skeleton, not a spinner: the shape of what is arriving beats a spinner in a space about to be a
        // list (ARCH_5 §5.2).
        loading: () => AlayaListSkeleton(label: strings.accountsLoading),
        // The repository's own message, never a generic body (Law U9).
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(accountsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.accountsEmptyTitle,
              body: strings.accountsEmptyBody,
              icon: Icons.account_balance_wallet_outlined,
              actionLabel: strings.accountsAdd,
              onAction: () => context.push(Routes.accountNew),
            );
          }
          final active = [
            for (final row in rows)
              if (!row.isArchived) row,
          ];
          final archived = [
            for (final row in rows)
              if (row.isArchived) row,
          ];
          return ListView(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            children: [
              for (final row in active) _AccountRow(account: row),
              if (archived.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                  ),
                  child: SectionHeader(label: strings.accountsArchivedHeader),
                ),
                for (final row in archived) _AccountRow(account: row),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// One account row: identity, its opening figure, and what is abnormal about it.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(
        _icon(account.kind),
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(account.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        _kindLabel(strings, account.kind),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      // The opening balance, not the current one: this screen is about how the account is *configured*, and a
      // live balance here would be the same figure the dashboard owns, one tap from a screen that explains it.
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AmountText(
            account.openingBalance,
            size: AmountSize.small,
            showSign: false,
          ),
          if (account.isArchived || !account.includeInNetWorth) ...[
            const SizedBox(height: AlayaSpacing.xxs),
            StatusChip(
              label: account.isArchived
                  ? strings.accountsArchivedChip
                  : strings.accountsExcludedChip,
              tone: account.isArchived ? StatusTone.neutral : StatusTone.info,
            ),
          ],
        ],
      ),
      onTap: () => context.push(Routes.accountEdit(account.id)),
    );
  }

  IconData _icon(AccountKind kind) => switch (kind) {
    AccountKind.cash => Icons.payments_outlined,
    AccountKind.bank => Icons.account_balance_outlined,
    AccountKind.wallet => Icons.account_balance_wallet_outlined,
    AccountKind.card => Icons.credit_card_outlined,
    AccountKind.other => Icons.savings_outlined,
  };

  String _kindLabel(AlayaStrings strings, AccountKind kind) => switch (kind) {
    AccountKind.cash => strings.accountKindCash,
    AccountKind.bank => strings.accountKindBank,
    AccountKind.wallet => strings.accountKindWallet,
    AccountKind.card => strings.accountKindCard,
    AccountKind.other => strings.accountKindOther,
  };
}
