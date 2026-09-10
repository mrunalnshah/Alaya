import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/pin_setup_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_card.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// Setting or changing the PIN (ARCH_5 §3 archetype B).
///
/// **ARCH_3 §2.2's sequence exactly: PIN twice, then the recovery code, then one confirmation, then the
/// offer of a backup.** The order is not arbitrary. The code is generated only once the PIN is confirmed,
/// so a half-finished attempt leaves no orphan secret; the confirmation gates leaving the code behind; and
/// the backup offer comes last because it is the moment a lock has just been placed over data the user may
/// have no other copy of.
///
/// **[embedded] is what lets onboarding reuse this without a route.** As a screen it brings its own
/// `Scaffold` and app bar; embedded it is a bare column, because onboarding owns the chrome and the
/// footer, and because a route here would fight the onboarding gate that sends everything outside
/// `/onboarding` back to it.
class PinSetupFlow extends ConsumerWidget {
  /// Creates the flow. [embedded] omits the scaffold, for onboarding's security step.
  const PinSetupFlow({this.embedded = false, super.key});

  /// Whether an enclosing screen supplies the scaffold.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final body = _Body(embedded: embedded);
    if (embedded) return body;

    return Scaffold(
      appBar: AppBar(
        // `CloseButton`, per archetype B: setting a PIN is a task you abandon, not a place you go up from.
        leading: const CloseButton(),
        title: Text(strings.pinSetupTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: body,
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.embedded});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(pinSetupProvider);
    return switch (state.stage) {
      PinSetupStage.enter || PinSetupStage.confirm => const _EntryStage(),
      PinSetupStage.recovery => const _RecoveryStage(),
      PinSetupStage.backup => const _BackupStage(),
      PinSetupStage.done => _DoneStage(embedded: embedded),
    };
  }
}

/// Stages one and two: the PIN, twice.
class _EntryStage extends ConsumerWidget {
  const _EntryStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);
    final confirming = state.stage == PinSetupStage.confirm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          confirming
              ? strings.pinSetupConfirmPrompt
              : strings.pinSetupEnterPrompt,
          style: AlayaTypography.bodyEmphasis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        Text(
          strings.lockHonestBody,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // Offered only before the first digit: changing length mid-entry discards what was typed, and a
        // control that silently throws away work is worse than one that disappears.
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
        else if (state.failureMessage != null)
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(
              color: context.semantic.danger,
            ),
            textAlign: TextAlign.center,
          )
        else
          const SizedBox(height: AlayaSpacing.lg),
        const SizedBox(height: AlayaSpacing.md),
        PinKeypad(
          enabled: !state.isSaving,
          onDigit: notifier.append,
          onBackspace: notifier.backspace,
        ),
      ],
    );
  }
}

/// Stage three: the recovery code, shown once, behind one confirmation.
class _RecoveryStage extends ConsumerWidget {
  const _RecoveryStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);
    final code = state.recoveryCode ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.pinSetupRecoveryHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.pinSetupRecoveryBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        AlayaCard(
          padding: const EdgeInsets.all(AlayaSpacing.lg),
          child: Column(
            children: [
              // `SelectableText`, so somebody using a screen reader or a password manager can get at it
              // without the clipboard — and `amountLarge` because a tabular numeric style is exactly what
              // a code of digits and letters wants: every glyph the same width, nothing ambiguous.
              SelectableText(
                code,
                style: AlayaTypography.amountLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AlayaSpacing.sm),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code));
                  if (!context.mounted) return;
                  showResultSnack(
                    context,
                    message: strings.pinSetupRecoveryCopied,
                  );
                },
                icon: const Icon(Icons.copy_outlined, size: AlayaIconSize.md),
                label: Text(
                  strings.pinSetupRecoveryCopy,
                  style: AlayaTypography.button,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Copy is offered rather than withheld: a password manager is the sensible home for this, and
        // refusing to let people use one would be worse security theatre than the clipboard risk it avoids.
        Text(
          strings.pinSetupRecoveryWhereToKeep,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        // **One checkbox, per the brief.** Two would be a form; none would let somebody swipe past the only
        // thing that can rescue a forgotten PIN. It gates the button rather than warning after the fact.
        CheckboxListTile(
          value: state.acknowledged,
          onChanged: (value) => notifier.acknowledge(value: value ?? false),
          title: Text(strings.pinSetupRecoveryAck, style: AlayaTypography.body),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
        ),
        const SizedBox(height: AlayaSpacing.md),
        FilledButton(
          onPressed: state.acknowledged ? notifier.toBackupOffer : null,
          child: Text(strings.actionContinue, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// Stage four: the offer of a backup, per ARCH_3 §2.2.
class _BackupStage extends ConsumerWidget {
  const _BackupStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(pinSetupProvider);
    final notifier = ref.read(pinSetupProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.pinSetupBackupHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(strings.pinSetupBackupBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.md),
        // **ARCH_3 §3.4, every single time an export is offered** — not in settings, not a tooltip. The
        // database is plaintext too, so this is a consistent threat model rather than a contradiction, and
        // saying it here is what keeps it one.
        Container(
          padding: const EdgeInsets.all(AlayaSpacing.md),
          decoration: BoxDecoration(
            color: context.semantic.warning.withValues(alpha: 0.12),
            borderRadius: AlayaRadii.borderMd,
          ),
          child: Text(
            strings.backupNotEncryptedWarning,
            style: AlayaTypography.bodyEmphasis,
          ),
        ),
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(
              color: context.semantic.danger,
            ),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: state.isSaving ? null : () => notifier.backupNow(),
          child: Text(strings.pinSetupBackupNow, style: AlayaTypography.button),
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextButton(
          onPressed: state.isSaving ? null : notifier.skipBackup,
          child: Text(
            strings.pinSetupBackupLater,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }
}

/// The lock is on.
class _DoneStage extends ConsumerWidget {
  const _DoneStage({required this.embedded});

  final bool embedded;

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
                strings.pinSetupDone,
                style: AlayaTypography.bodyEmphasis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.md),
        Text(
          strings.pinSetupDoneBody,
          style: AlayaTypography.caption.copyWith(
            color: context.semantic.muted,
          ),
        ),
        if (!embedded) ...[
          const SizedBox(height: AlayaSpacing.lg),
          FilledButton(
            onPressed: () => context.pop(),
            child: Text(strings.actionDone, style: AlayaTypography.button),
          ),
        ],
      ],
    );
  }
}
