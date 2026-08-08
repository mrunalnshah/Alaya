import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/services/backup/data_transfer_port.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/recovery_providers.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Recovering a forgotten PIN, and the last resort behind it (ARCH_5 §3 archetype B).
///
/// **Reachable while the app is locked**, which is why `/lock/recovery` sits under `/lock`: the router
/// permits anything in that branch while locked, and anywhere else this screen would be redirected straight
/// back to the PIN the user cannot remember.
///
/// **The forgot-both path offers a backup before it erases, and that is the improvement dropping encryption
/// bought** (ARCH_3 §2.2). With an encrypted database the export would have been unreadable without the key
/// the user has lost; plaintext means nobody permanently loses their financial history to a forgotten
/// four-digit PIN.
class RecoveryFlow extends ConsumerWidget {
  /// Creates the flow.
  const RecoveryFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.recoveryTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: switch (state.stage) {
            RecoveryStage.code => const _CodeStage(),
            RecoveryStage.newPin ||
            RecoveryStage.confirmPin => const _PinStage(),
            RecoveryStage.forgotBoth => const _ForgotBothStage(),
            RecoveryStage.done => const _DoneStage(),
          },
        ),
      ),
    );
  }
}

/// Entering the recovery code.
class _CodeStage extends ConsumerWidget {
  const _CodeStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.recoveryCodePrompt, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: TextField(
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            // The length comes from the contract, so the counter cannot disagree with the validator. One
            // extra character for the display hyphen in `ABCDE-FGHJK`.
            maxLength: AppLock.recoveryCodeLength + 1,
            style: AlayaTypography.amountLarge,
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: strings.recoveryCodeLabel,
              errorText: state.failureMessage,
            ),
            onChanged: notifier.setCode,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: state.code.trim().isEmpty ? null : notifier.toNewPin,
          child: Text(strings.actionContinue, style: AlayaTypography.button),
        ),
        const SizedBox(height: AlayaSpacing.xl),
        // The last resort is reachable but not adjacent to the commit: a destructive path sits last and
        // quiet, in the manner of archetype E's destructive actions (ARCH_5 §3).
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: notifier.toForgotBoth,
            child: Text(
              strings.recoveryForgotBoth,
              style: AlayaTypography.button,
            ),
          ),
        ),
      ],
    );
  }
}

/// Choosing the new PIN, twice.
class _PinStage extends ConsumerWidget {
  const _PinStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);
    final confirming = state.stage == RecoveryStage.confirmPin;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          confirming
              ? strings.pinSetupConfirmPrompt
              : strings.recoveryNewPinPrompt,
          style: AlayaTypography.bodyEmphasis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.lg),
        if (!confirming && state.entered.isEmpty)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AlayaSpacing.xs,
            children: [
              for (final length in const [4, 6])
                ChoiceChip(
                  label: Text(
                    strings.pinSetupLength(length),
                    style: AlayaTypography.button,
                  ),
                  selected: state.length == length,
                  onSelected: (_) => notifier.setLength(length),
                ),
            ],
          ),
        const SizedBox(height: AlayaSpacing.lg),
        ShakeOnError(
          trigger: state.shakeTrigger,
          child: PinDots(
            length: state.length,
            filled: state.active.length,
            dimmed: false,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.mismatch)
          Text(
            strings.pinSetupMismatch,
            style: AlayaTypography.body.copyWith(
              color: context.semantic.danger,
            ),
            textAlign: TextAlign.center,
          )
        else
          const SizedBox(height: AlayaSpacing.lg),
        const SizedBox(height: AlayaSpacing.md),
        PinKeypad(
          enabled: !state.isWorking,
          onDigit: notifier.append,
          onBackspace: notifier.backspace,
        ),
      ],
    );
  }
}

/// The last resort: export, then type the word, then erase.
class _ForgotBothStage extends ConsumerWidget {
  const _ForgotBothStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(recoveryProvider);
    final notifier = ref.read(recoveryProvider.notifier);
    final semantic = context.semantic;
    final armed =
        state.eraseTyped.trim() == DataTransferPort.eraseConfirmationWord;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          strings.recoveryForgotBothTitle,
          style: AlayaTypography.bodyEmphasis,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.recoveryForgotBothBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        // **The export comes first, and it is offered rather than assumed.** ARCH_3 §2.2 requires the offer;
        // ordering it above the erase is what makes it an offer rather than a footnote nobody reads after
        // they have already typed the word.
        Container(
          padding: const EdgeInsets.all(AlayaSpacing.md),
          decoration: BoxDecoration(
            color: semantic.warning.withValues(alpha: 0.12),
            borderRadius: AlayaRadii.borderMd,
          ),
          child: Text(
            strings.backupNotEncryptedWarning,
            style: AlayaTypography.bodyEmphasis,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        if (state.exported)
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: AlayaIconSize.md,
                color: semantic.success,
              ),
              const SizedBox(width: AlayaSpacing.xs),
              Expanded(
                child: Text(
                  strings.recoveryExported,
                  style: AlayaTypography.body,
                ),
              ),
            ],
          )
        else
          FilledButton.tonal(
            onPressed: state.isWorking ? null : () => notifier.exportFirst(),
            child: Text(
              strings.recoveryExportFirst,
              style: AlayaTypography.button,
            ),
          ),
        const SizedBox(height: AlayaSpacing.xl),
        Text(
          strings.recoveryTypeToConfirm(DataTransferPort.eraseConfirmationWord),
          style: AlayaTypography.body,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            labelText: DataTransferPort.eraseConfirmationWord,
            errorText: state.failureMessage,
          ),
          onChanged: notifier.setEraseTyped,
        ),
        const SizedBox(height: AlayaSpacing.md),
        // **Enabled only on an exact match, and never a filled button.** ARCH_5 §5.5 puts an irreversible
        // action last and quiet; a prominent primary here would be the one control on the screen that
        // destroys everything, styled like the one that saves.
        OutlinedButton(
          onPressed: armed && !state.isWorking
              ? () => notifier.eraseEverything()
              : null,
          style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
          child: Text(
            strings.recoveryEraseEverything,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }
}

/// The PIN is reset, or the data is gone.
class _DoneStage extends ConsumerWidget {
  const _DoneStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: AlayaIconSize.lg,
              color: context.semantic.success,
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Text(
                strings.recoveryDone,
                style: AlayaTypography.bodyEmphasis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          // `go`, not `pop`: the lock branch is behind this screen and the redirect has already released it,
          // so popping would land on a lock screen that immediately bounces to the dashboard anyway.
          onPressed: () => context.go(Routes.dashboard),
          child: Text(strings.actionDone, style: AlayaTypography.button),
        ),
      ],
    );
  }
}
