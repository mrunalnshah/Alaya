import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/onboarding/providers/onboarding_providers.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/amount_field.dart';
import 'package:alaya/shared/widgets/date_picker_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// The first-run flow (ARCH_5 §3 archetype B).
///
/// **Skippable from every step and resumable into any of them.** `OnboardingController.goTo` writes the
/// step to `app_settings` on each transition, so a phone call at step two does not cost the opening
/// balances already typed — and re-asking for those is the fastest way to have somebody skip the flow
/// entirely.
///
/// **Archetype B, with one deviation: no `CloseButton`.** §3's editor opens with ✕ because an editor is a
/// task you can abandon back to something. Onboarding has nothing behind it — the router redirects here
/// until it is finished or skipped — so the escape is a named **Skip** action instead, which says where it
/// leads. Both routes through the same `finish()`, so a skip is recorded as deliberately as a completion.
///
/// **It edits as much as it creates.** Phase 1C's seeder already inserts two accounts and a home
/// currency, so a flow that started from an empty list would either duplicate them or ignore them, and a
/// first-run screen showing none of the accounts the app already has reads as broken.
class OnboardingFlow extends ConsumerWidget {
  /// Creates the flow.
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    // Loading: the seeded accounts and the stored step have not arrived. Not an empty list — showing
    // "no accounts yet" to somebody who has two would be a lie for one frame (Law U4).
    if (!draft.isLoaded) {
      return Scaffold(
        appBar: AppBar(title: Text(strings.onboardingTitle)),
        body: Center(
          child: Text(
            strings.onboardingLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitle(strings, draft.step)),
        actions: [
          TextButton(
            onPressed: draft.isSaving
                ? null
                : () async {
                    await controller.finish();
                    if (context.mounted) _leave(context);
                  },
            child: Text(strings.onboardingSkip, style: AlayaTypography.button),
          ),
        ],
      ),
      body: AlayaFormScaffold(
        primaryLabel: _primaryLabel(strings, draft.step),
        onPrimary: draft.isSaving ? null : () => _commit(context, ref, draft),
        secondaryLabel: draft.step == OnboardingStep.currency
            ? null
            : strings.actionBack,
        onSecondary: draft.step == OnboardingStep.currency
            ? null
            : () => controller.goTo(_previous(draft.step)),
        isSubmitting: draft.isSaving,
        // Nothing to guard: there is no way out of this screen except Skip, which commits the decision to
        // skip. A discard prompt over a flow the user cannot accidentally leave would be noise.
        discardTitle: strings.onboardingSkipTitle,
        discardBody: strings.onboardingSkipBody,
        discardConfirmLabel: strings.onboardingSkip,
        discardCancelLabel: strings.actionKeepEditing,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepProgress(step: draft.step),
            const SizedBox(height: AlayaSpacing.lg),
            if (draft.failureMessage != null) ...[
              // The repository's own message, inline under the step it belongs to (Law U9).
              ErrorState(
                title: strings.errorTitleGeneric,
                body: draft.failureMessage!,
                retryLabel: strings.actionRetry,
                onRetry: () => _commit(context, ref, draft),
              ),
              const SizedBox(height: AlayaSpacing.lg),
            ],
            switch (draft.step) {
              OnboardingStep.currency => const _CurrencyStep(),
              OnboardingStep.accounts ||
              OnboardingStep.done => const _AccountsStep(),
            },
          ],
        ),
      ),
    );
  }

  Future<void> _commit(
    BuildContext context,
    WidgetRef ref,
    OnboardingDraft draft,
  ) async {
    final controller = ref.read(onboardingControllerProvider.notifier);
    switch (draft.step) {
      case OnboardingStep.currency:
        await controller.commitCurrency();
      case OnboardingStep.accounts:
      case OnboardingStep.done:
        // `commitAccounts` finishes the flow itself once the writes land.
        final done = await controller.commitAccounts();
        if (done && context.mounted) _leave(context);
    }
  }

  /// Leaves the flow.
  ///
  /// **Explicit, rather than waiting for the redirect to notice.** The gate is a *guard* — it stops somebody
  /// arriving somewhere they should not be. Using it to move somebody forward means the transition depends on a
  /// `refreshListenable` notification being delivered, and if that lands before `GoRouter` has attached its
  /// listener it is simply dropped. The symptom was Finish appearing to do nothing while the write had in fact
  /// succeeded — reopening the app showed the dashboard.
  ///
  /// The screen knows it has finished, so the screen navigates. The redirect still runs and still agrees; it is
  /// no longer the thing carrying the user.
  ///
  /// `go`, not `push`: onboarding must not remain on the stack for a back gesture to return to.
  void _leave(BuildContext context) => context.go(Routes.dashboard);

  OnboardingStep _previous(OnboardingStep step) => switch (step) {
    OnboardingStep.currency => OnboardingStep.currency,
    OnboardingStep.accounts || OnboardingStep.done => OnboardingStep.currency,
  };

  String _stepTitle(AlayaStrings strings, OnboardingStep step) =>
      switch (step) {
        OnboardingStep.currency => strings.onboardingCurrencyTitle,
        OnboardingStep.accounts ||
        OnboardingStep.done => strings.onboardingAccountsTitle,
      };

  String _primaryLabel(AlayaStrings strings, OnboardingStep step) =>
      switch (step) {
        OnboardingStep.currency => strings.onboardingNext,
        OnboardingStep.accounts ||
        OnboardingStep.done => strings.onboardingFinish,
      };
}

/// Which of the three steps is showing.
///
/// Words and a count, not three dots. A dot row says "there are more" without saying how many more or
/// what they are, and the one question somebody abandons a setup flow over is how long it will take.
class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.step});

  final OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final index = switch (step) {
      OnboardingStep.currency => 1,
      OnboardingStep.accounts || OnboardingStep.done => 2,
    };
    return Text(
      // Two steps now, not three: the security step moved to Settings › Security.
      strings.onboardingStepOf(index, 2),
      style: AlayaTypography.overline.copyWith(color: context.semantic.muted),
    );
  }
}

/// Step one: the currency totals are shown in.
class _CurrencyStep extends ConsumerWidget {
  const _CurrencyStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final currencies =
        ref.watch(onboardingCurrenciesProvider).valueOrNull ??
        const <Currency>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.onboardingCurrencyBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.xs),
        // **Says what it does and what it does not.** Law L9 makes this a display choice: it changes what
        // totals are added up in, and changes no amount that was ever recorded. Somebody who thinks they
        // are converting their history would be very surprised later.
        Text(
          strings.onboardingCurrencyNote,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        if (currencies.isEmpty)
          Text(
            strings.onboardingLoading,
            style: AlayaTypography.body.copyWith(color: context.semantic.muted),
          )
        else
          Wrap(
            spacing: AlayaSpacing.xs,
            runSpacing: AlayaSpacing.xs,
            children: [
              for (final currency in currencies)
                ChoiceChip(
                  label: Text(
                    strings.onboardingCurrencyChip(
                      currency.code,
                      currency.symbol,
                    ),
                    style: AlayaTypography.button,
                  ),
                  selected: currency.code == draft.homeCurrencyCode,
                  onSelected: (_) => ref
                      .read(onboardingControllerProvider.notifier)
                      .setHomeCurrency(currency.code),
                ),
            ],
          ),
      ],
    );
  }
}

/// Step two: the accounts, and what was in them when the user started.
class _AccountsStep extends ConsumerWidget {
  const _AccountsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(onboardingControllerProvider);
    final controller = ref.read(onboardingControllerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.onboardingAccountsBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.xs),
        // **This is the paragraph anomaly A03 exists for.** An opening balance without a date cannot be
        // placed in a ledger, so every transaction before that date would be silently unaccounted for —
        // and the balance is the only reason a new user's real cash is visible at all.
        Text(
          strings.onboardingOpeningNote,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // Empty is reachable: the user can remove every row. It names the next action rather than the
        // absence (ARCH_5 §2.8).
        if (draft.accounts.isEmpty)
          EmptyState(
            title: strings.onboardingNoAccountsTitle,
            body: strings.onboardingNoAccountsBody,
            icon: Icons.account_balance_wallet_outlined,
            actionLabel: strings.onboardingAddAccount,
            onAction: controller.addAccount,
          )
        else ...[
          for (var i = 0; i < draft.accounts.length; i++) ...[
            _AccountCard(index: i, draft: draft.accounts[i]),
            const SizedBox(height: AlayaSpacing.sm),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.addAccount,
              icon: const Icon(Icons.add, size: AlayaIconSize.md),
              label: Text(
                strings.onboardingAddAccount,
                style: AlayaTypography.button,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One account being set up.
class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.index, required this.draft});

  final int index;
  final DraftAccount draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final controller = ref.read(onboardingControllerProvider.notifier);
    final digits =
        ref
            .watch(onboardingCurrencyDigitsProvider(draft.currencyCode))
            .valueOrNull ??
        2;

    return AlayaCard(
      padding: const EdgeInsets.all(AlayaSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft.name,
                  decoration: InputDecoration(
                    labelText: strings.accountNameLabel,
                  ),
                  onChanged: (value) => controller.updateAccount(
                    index,
                    draft.copyWith(name: value),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => controller.removeAccount(index),
                tooltip: strings.onboardingRemoveAccount,
                icon: const Icon(Icons.close, size: AlayaIconSize.md),
              ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
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
                  selected: kind == draft.kind,
                  onSelected: (_) => controller.updateAccount(
                    index,
                    draft.copyWith(kind: kind),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AlayaSpacing.sm),
          AmountField(
            currencyCode: draft.currencyCode,
            decimalDigits: digits,
            initialValue: draft.openingBalance,
            label: strings.accountOpeningBalanceLabel,
            // Negative allowed: a card account can legitimately open overdrawn, and refusing it would
            // force somebody to record a debt as an asset.
            allowNegative: true,
            onChanged: (money) => controller.updateAccount(
              index,
              draft.copyWith(openingMinor: money?.minor ?? 0),
            ),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          DatePickerField(
            value: draft.openingDate,
            label: strings.accountOpeningDateLabel,
            // `DateText` has no public formatter — its `_format` is private, because every other date in
            // the app goes through the widget. A `DatePickerField` needs a `String`, so this is the same
            // `intl` call 6A's forms make, and the only place in this phase a date is formatted by hand.
            // A formatter, not a formatted string: `DatePickerField.formatted` is
            // `String Function(DateKey)`, so it formats whichever date the picker lands on rather than
            // the one that was there when this built.
            formatted: (date) => DateFormat.yMMMd(
              Localizations.localeOf(context).toLanguageTag(),
            ).format(date.toUtcMidnight()),
            onChanged: (date) => controller.updateAccount(
              index,
              draft.copyWith(openingDate: date),
            ),
          ),
          const SizedBox(height: AlayaSpacing.sm),
          SwitchListTile(
            value: draft.includeInNetWorth,
            title: Text(
              strings.accountIncludeInNetWorth,
              style: AlayaTypography.body,
            ),
            // **The toggle is explained, which is the whole of ARCH_5 §7.2's row for it.** A switch called
            // "include in net worth" with no subtitle leaves the user guessing whether turning it off
            // hides the account or merely stops it being counted.
            subtitle: Text(
              strings.accountIncludeInNetWorthHelp,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.muted,
              ),
            ),
            contentPadding: EdgeInsets.zero,
            onChanged: (value) => controller.updateAccount(
              index,
              draft.copyWith(includeInNetWorth: value),
            ),
          ),
        ],
      ),
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
