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
import 'package:alaya/features/backup/providers/restore_providers.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Restoring from a backup (ARCH_5 §3 archetype B).
///
/// **ARCH_3 §3.2's guards, in its order, and each one visible.** Verify the file opens → check its `user_version`
/// against this build → choose a mode → for Replace, type the word → snapshot a rollback → apply. The gate is
/// checked when the file is picked rather than when Apply is pressed, so a refusal arrives before the user has
/// chosen anything they would then lose.
///
/// **Merge is the default; Replace is a choice.** Merge upserts by UUID and keeps rows the backup does not have.
/// Replace discards them. A destructive default is a destructive accident.
///
/// **The lock is never restored**, and the screen says so. PIN and recovery hashes live in secure storage
/// (ARCH_3 §2.1), so importing a backup cannot change who can open the app — which is worth stating on the one
/// screen where somebody might expect otherwise.
class RestoreFlow extends ConsumerWidget {
  /// Creates the flow.
  const RestoreFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(strings.restoreTitle),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: switch (state.stage) {
            RestoreStage.pick => const _PickStage(),
            RestoreStage.confirm => const _ConfirmStage(),
            RestoreStage.arm => const _ArmStage(),
            RestoreStage.done => const _DoneStage(),
          },
        ),
      ),
    );
  }
}

/// Choosing a file.
class _PickStage extends ConsumerWidget {
  const _PickStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(strings.restorePickBody, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.md),
        _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
        if (state.refusal == RestoreRefusal.notADatabase) ...[
          const SizedBox(height: AlayaSpacing.md),
          _Notice(text: strings.restoreNotADatabase, tone: semantic.danger),
        ],
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton.icon(
          onPressed: state.isWorking
              ? null
              : () => ref.read(restoreProvider.notifier).pickFile(),
          icon: const Icon(Icons.folder_open_outlined, size: AlayaIconSize.md),
          label: Text(strings.restoreChooseFile, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// The file is readable; choose a mode.
class _ConfirmStage extends ConsumerWidget {
  const _ConfirmStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final notifier = ref.read(restoreProvider.notifier);
    final semantic = context.semantic;
    final refused = state.refusal == RestoreRefusal.newerSchema;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(label: strings.restoreChosenHeader),
        const SizedBox(height: AlayaSpacing.xs),
        Text(state.fileName ?? '', style: AlayaTypography.cardTitle),
        const SizedBox(height: AlayaSpacing.md),
        if (refused) ...[
          // **Both numbers, because a refusal without them is one nobody can act on.** "That backup is from a
          // newer version (7) than this app understands (1)" tells the user to update; "cannot restore" does not.
          _Notice(
            text: strings.restoreNewerSchema(
              state.backupVersion ?? 0,
              state.appVersion ?? 0,
            ),
            tone: semantic.danger,
          ),
          const SizedBox(height: AlayaSpacing.lg),
          OutlinedButton(
            onPressed: () => ref.invalidate(restoreProvider),
            child: Text(
              strings.restoreChooseAnother,
              style: AlayaTypography.button,
            ),
          ),
        ] else ...[
          SectionHeader(label: strings.restoreModeHeader),
          const SizedBox(height: AlayaSpacing.xs),
          for (final mode in RestoreMode.values)
            RadioListTile<RestoreMode>(
              value: mode,
              groupValue: state.mode,
              onChanged: (next) => next == null ? null : notifier.setMode(next),
              contentPadding: EdgeInsets.zero,
              title: Text(
                mode == RestoreMode.merge
                    ? strings.restoreMergeTitle
                    : strings.restoreReplaceTitle,
                style: AlayaTypography.body,
              ),
              subtitle: Text(
                mode == RestoreMode.merge
                    ? strings.restoreMergeBody
                    : strings.restoreReplaceBody,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
          const SizedBox(height: AlayaSpacing.md),
          _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
          if (state.failureMessage != null) ...[
            const SizedBox(height: AlayaSpacing.md),
            Text(
              state.failureMessage!,
              style: AlayaTypography.body.copyWith(color: semantic.danger),
            ),
          ],
          const SizedBox(height: AlayaSpacing.lg),
          if (state.mode == RestoreMode.merge)
            FilledButton(
              onPressed: state.isWorking ? null : () => notifier.apply(),
              child: Text(
                strings.restoreApplyMerge,
                style: AlayaTypography.button,
              ),
            )
          else
            // Replace never commits from this screen: it goes to the typed confirmation first, and the button
            // says so rather than pretending to be the last step.
            OutlinedButton(
              onPressed: state.isWorking ? null : notifier.arm,
              style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
              child: Text(
                strings.restoreContinueReplace,
                style: AlayaTypography.button,
              ),
            ),
        ],
      ],
    );
  }
}

/// Typing the word, for Replace.
class _ArmStage extends ConsumerWidget {
  const _ArmStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final notifier = ref.read(restoreProvider.notifier);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Notice(text: strings.restoreReplaceWarning, tone: semantic.danger),
        const SizedBox(height: AlayaSpacing.md),
        // Says the snapshot happens *before* the swap, because that is what makes this recoverable — and a user
        // who knows there is a way back reads the warning as information rather than a threat.
        Text(strings.restoreRollbackPromise, style: AlayaTypography.body),
        const SizedBox(height: AlayaSpacing.lg),
        Text(
          strings.restoreTypeToConfirm(RestoreState.confirmationWord),
          style: AlayaTypography.body,
        ),
        const SizedBox(height: AlayaSpacing.xs),
        TextField(
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(labelText: RestoreState.confirmationWord),
          onChanged: notifier.setTyped,
        ),
        if (state.failureMessage != null) ...[
          const SizedBox(height: AlayaSpacing.md),
          Text(
            state.failureMessage!,
            style: AlayaTypography.body.copyWith(color: semantic.danger),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        OutlinedButton(
          onPressed: state.isArmed && !state.isWorking
              ? () => notifier.apply()
              : null,
          style: OutlinedButton.styleFrom(foregroundColor: semantic.danger),
          child: Text(
            strings.restoreApplyReplace,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }
}

/// Applied.
class _DoneStage extends ConsumerWidget {
  const _DoneStage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(restoreProvider);
    final outcome = state.outcome;
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: AlayaIconSize.lg,
              color: semantic.success,
            ),
            const SizedBox(width: AlayaSpacing.sm),
            Expanded(
              child: Text(
                outcome == null
                    ? strings.restoreDone
                    : strings.restoreDoneDetail(outcome.tablesMerged),
                style: AlayaTypography.bodyEmphasis,
              ),
            ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.md),
        _Notice(text: strings.restoreLockNotRestored, tone: semantic.muted),
        if (outcome != null && outcome.rollbackAvailable) ...[
          const SizedBox(height: AlayaSpacing.lg),
          Text(strings.restoreRollbackAvailable, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.xs),
          // Offered on the success screen, not hidden behind a settings row: the moment somebody realises they
          // restored the wrong file is the moment they are looking at this.
          OutlinedButton(
            onPressed: state.isWorking
                ? null
                : () => ref.read(restoreProvider.notifier).rollback(),
            child: Text(strings.restoreUndo, style: AlayaTypography.button),
          ),
        ],
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: () => context.go(Routes.dashboard),
          child: Text(strings.actionDone, style: AlayaTypography.button),
        ),
      ],
    );
  }
}

/// A tinted paragraph.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.tone});

  final String text;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AlayaSpacing.md),
    decoration: BoxDecoration(
      color: tone.withValues(alpha: 0.12),
      borderRadius: AlayaRadii.borderMd,
    ),
    child: Text(text, style: AlayaTypography.body),
  );
}
