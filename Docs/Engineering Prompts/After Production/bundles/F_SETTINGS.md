# F_SETTINGS

Settings tree and branches, onboarding, PIN, lock, recovery.

**39 files · 8,125 lines.**  Written 2026-08-27T08:54:37-04:00.

Every file below is complete and current. Paths are destinations.

---

### `lib/features/lock/presentation/screens/lock_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/features/lock/providers/lock_entry_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/shared/widgets/scroll_safe_center.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

/// The PIN gate (ARCH_5 §3 archetype A, outside the shell).
///
/// **Archetype A's shape, not its skeleton, and the deviation is deliberate.** A is a capture sheet:
/// `AlayaBottomSheet`, one required field autofocused, optional context as chips, a full-width commit. A
/// lock screen cannot be a sheet — a sheet is dismissible, and one with no way out is a worse answer than
/// a screen. What carries over is everything A is actually about: exactly one required input, focus in it
/// on open, context as chips rather than pickers, and a commit that fires the moment the input parses.
///
/// **A keypad rather than a `TextField`, which is the second deviation from A's "keyboard up".** The
/// system keyboard is the wrong control here: it can be switched to a layout with no digits, it carries
/// autocorrect chrome over a secret, and it can be dismissed leaving no way to type on a screen with no
/// other exit. Every key here is a labelled 48dp target, which is also what makes
/// `labeledTapTargetGuideline` pass without special pleading.
///
/// **The copy is the point of this screen as much as the keypad is (ARCH_3 §2.5).** It says in plain words
/// that this PIN stops someone who picks up the unlocked phone, and that it does **not** encrypt anything
/// — because the database is plaintext by design (ARCH_1 §2.1) and claiming otherwise would be both
/// dishonest and a Play listing risk. There is no padlock glyph anywhere in this file: a closed padlock is
/// the universal icon for encryption, and drawing one here would undo the sentence beside it.
class LockScreen extends ConsumerWidget {
  /// Creates the lock screen.
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final state = ref.watch(lockEntryProvider);
    final notifier = ref.read(lockEntryProvider.notifier);

    // The fourth state, and the only destructive one this screen has: the ten-failure auto-erase is
    // running. It takes the whole screen because there is nothing left to enter a PIN against — the erase
    // clears the lock as well as the data — and because somebody watching their history be deleted should
    // not also be looking at a keypad.
    if (state.isErasing) {
      return Scaffold(
        body: ScrollSafeCenter(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: Text(
            strings.lockErasing,
            style: AlayaTypography.body.copyWith(
              color: context.semantic.danger,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // **Leave explicitly the moment the lock opens, rather than waiting for the redirect to notice.**
    //
    // The gate is a guard: it stops somebody arriving somewhere they should not be. Using it to carry somebody
    // forward makes the transition depend on a `refreshListenable` notification being delivered, and a dropped
    // one would leave a user who entered the correct PIN staring at the lock screen. Onboarding's Finish button
    // failed exactly that way before this was applied here too.
    //
    // `ref.listen` rather than a check in `build`, because navigating during a build is the error Flutter
    // asserts on.
    ref.listen<LockPhase>(lockPhaseProvider, (previous, next) {
      if (next == LockPhase.open && context.mounted)
        context.go(Routes.dashboard);
    });

    return Scaffold(
      body: SafeArea(
        child: ScrollSafeCenter(
          padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.lockTitle,
                  style: AlayaTypography.screenTitle,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AlayaSpacing.xs),
                // ARCH_3 §2.5, on the screen itself and not buried in Settings.
                Text(
                  strings.lockHonestBody,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AlayaSpacing.xl),
                ShakeOnError(
                  trigger: state.shakeTrigger,
                  child: PinDots(
                    length: state.pinLength,
                    filled: state.entered.length,
                    dimmed: state.isThrottled,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.md),
                _Feedback(state: state, error: notifier.lastError),
                const SizedBox(height: AlayaSpacing.lg),
                PinKeypad(
                  enabled: !state.isThrottled && !state.isChecking,
                  onDigit: notifier.append,
                  onBackspace: notifier.backspace,
                  // A chip, in A's spirit: the shortcut sits beside the required input rather than
                  // replacing it, and it is absent — not disabled — where the device cannot offer it.
                  onBiometric: state.biometricAvailable
                      ? () => notifier.useBiometric(
                          reason: strings.lockBiometricReason,
                        )
                      : null,
                ),
                const SizedBox(height: AlayaSpacing.lg),
                TextButton(
                  onPressed: () => context.push(Routes.lockRecovery),
                  child: Text(
                    strings.lockForgotPin,
                    style: AlayaTypography.button,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the keypad thumb-sized on a phone and stops it stretching across a tablet.
  static const double _maxWidth = 360;
}

/// The countdown, the refusal, or nothing.
///
/// **The throttle is stated as a duration that moves**, per this phase's brief. A screen that silently
/// refuses every tap is indistinguishable from a broken one, and ARCH_3 §2.3's delays reach an hour — long
/// enough that a user with no explanation would reasonably conclude the app had failed.
class _Feedback extends StatelessWidget {
  const _Feedback({required this.state, required this.error});

  final LockEntryState state;
  final LockEntryError? error;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    final remaining = state.remaining;
    if (remaining != null) {
      return Column(
        children: [
          Text(
            strings.lockThrottled(_clock(remaining)),
            style: AlayaTypography.bodyEmphasis.copyWith(
              color: semantic.warning,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AlayaSpacing.xxs),
          Text(
            strings.lockThrottledWhy,
            style: AlayaTypography.caption.copyWith(color: semantic.muted),
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    final message = switch (error) {
      LockEntryError.wrongPin => strings.lockWrongPin,
      LockEntryError.biometricFailed => strings.lockBiometricFailed,
      LockEntryError.eraseFailed => strings.lockEraseFailed,
      LockEntryError.throttled || null => null,
    };
    if (message == null) {
      // Reserves the line's height so the keypad does not jump when a message appears — a control that
      // moves under a thumb mid-tap is how a wrong digit gets entered.
      return const SizedBox(height: AlayaSpacing.lg);
    }
    return Text(
      message,
      style: AlayaTypography.body.copyWith(color: semantic.danger),
      textAlign: TextAlign.center,
    );
  }

  /// `m:ss` for anything a minute or longer, plain seconds below that.
  ///
  /// Formatted here rather than in the ARB because a plural on "second" cannot express `1:05`, and a
  /// duration is not a number a translator should have to assemble.
  String _clock(Duration remaining) {
    final total = remaining.inSeconds;
    if (total < 60) return '$total';
    final minutes = total ~/ 60;
    final seconds = total % 60;
    return '$minutes:${seconds < 10 ? '0$seconds' : '$seconds'}';
  }
}
```

### `lib/features/lock/presentation/screens/pin_setup_flow.dart`

```dart
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
```

### `lib/features/lock/presentation/screens/recovery_flow.dart`

```dart
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
```

### `lib/features/lock/presentation/widgets/pin_pad.dart`

```dart
/// The PIN dots and keypad, shared by the three screens that ask for a PIN.
///
/// **Feature-local, not `shared/`.** ARCH_5 §8 permits this phase no shared additions, and it is
/// right not to need one: a keypad is only ever wanted by the lock, PIN setup and recovery, all of
/// which live here. Three private copies would have been the alternative, and the third would have
/// drifted.
library;

import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// One dot per digit of the configured PIN.
///
/// Dots rather than an obscured field: the count is information the user needs — a six-digit PIN entered
/// into four boxes is a confusing failure — and `readPinLength` exists so this can be right.
class PinDots extends StatelessWidget {
  /// Creates the dots.
  const PinDots({
    required this.length,
    required this.filled,
    required this.dimmed,
  });

  /// How many digits the configured PIN has.
  final int length;

  /// How many have been entered.
  final int filled;

  /// Renders muted while a throttle is in force.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.xs),
            child: Container(
              width: AlayaSpacing.sm,
              height: AlayaSpacing.sm,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (dimmed ? semantic.muted : theme.colorScheme.primary)
                    : theme.colorScheme.outlineVariant,
              ),
            ),
          ),
      ],
    );
  }
}

/// The digits, the backspace and the optional biometric shortcut.
class PinKeypad extends StatelessWidget {
  /// Creates the keypad.
  const PinKeypad({
    required this.enabled,
    required this.onDigit,
    required this.onBackspace,
    this.onBiometric,
  });

  /// Whether keys accept taps.
  final bool enabled;

  /// Called with the digit tapped.
  final ValueChanged<String> onDigit;

  /// Removes the last digit.
  final VoidCallback onBackspace;

  /// The biometric shortcut, or null where the device has none.
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final digit in row)
                _Key(
                  label: digit,
                  enabled: enabled,
                  onPressed: () => onDigit(digit),
                ),
            ],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (onBiometric == null)
              const _KeySpacer()
            else
              _Key(
                icon: Icons.fingerprint,
                // A tooltip and a `Semantics` label, because a fingerprint glyph is not one of the six
                // ARCH_5 §2.7 lets stand alone.
                semanticLabel: strings.lockUseBiometric,
                enabled: enabled,
                onPressed: onBiometric!,
              ),
            _Key(label: '0', enabled: enabled, onPressed: () => onDigit('0')),
            _Key(
              icon: Icons.backspace_outlined,
              semanticLabel: strings.lockBackspace,
              enabled: enabled,
              onPressed: onBackspace,
            ),
          ],
        ),
      ],
    );
  }
}

/// One key. Sized from the tap-target token, so a doubled text scale cannot shrink it below 48dp.
class _Key extends StatelessWidget {
  const _Key({
    required this.enabled,
    required this.onPressed,
    this.label,
    this.icon,
    this.semanticLabel,
  });

  final bool enabled;
  final VoidCallback onPressed;
  final String? label;
  final IconData? icon;
  final String? semanticLabel;

  static const double _extent = AlayaSpacing.minTapTarget + AlayaSpacing.md;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = icon != null
        ? Icon(icon, size: AlayaIconSize.lg)
        : Text(label!, style: AlayaTypography.amountLarge);

    return Padding(
      padding: const EdgeInsets.all(AlayaSpacing.xs),
      child: Semantics(
        button: true,
        label: semanticLabel,
        child: SizedBox(
          width: _extent,
          height: _extent,
          child: Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: AlayaRadii.borderMd,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: AlayaRadii.borderMd,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Holds the biometric key's place when the device cannot offer one, so `0` stays centred.
class _KeySpacer extends StatelessWidget {
  const _KeySpacer();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AlayaSpacing.xs),
    child: SizedBox(width: _Key._extent, height: _Key._extent),
  );
}
```

### `lib/features/lock/providers/lock_entry_providers.dart`

```dart
/// View-model state for the lock screen (ARCH_5 U19).
///
/// **Neither `AppLock` nor `UnlockOutcome` is named here, and that is deliberate.** Dart needs an import
/// only to *write* a type, not to call a member on an inferred one — so this file drives the lock through
/// `pinServiceProvider` and translates the outcome into [LockEntryError] before the screen sees anything.
/// The screen therefore owns every string (Law U5) while this owns every decision about which applies.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/services/lock/app_lock.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// What the lock screen is showing.
class LockEntryState {
  /// Creates a state.
  const LockEntryState({
    required this.pinLength,
    this.entered = '',
    this.shakeTrigger = 0,
    this.failedCount = 0,
    this.remaining,
    this.isChecking = false,
    this.biometricAvailable = false,
    this.isErasing = false,
    this.message,
  });

  /// How many digits the configured PIN has, so the field knows when it is full.
  final int pinLength;

  /// What has been typed.
  final String entered;

  /// Incremented on every rejection, so two failures shake twice (ARCH_5 §2.6).
  final int shakeTrigger;

  /// Consecutive wrong attempts recorded so far.
  final int failedCount;

  /// How long until the next attempt will even be checked, or null when none is owed.
  ///
  /// **Ticks down while the screen is open**, because a throttle the user cannot see reads as the app
  /// having frozen — and the countdown is the difference between "wait 30 seconds" and "this is broken".
  final Duration? remaining;

  /// Whether a check is in flight.
  final bool isChecking;

  /// Whether this device can offer the biometric shortcut.
  final bool biometricAvailable;

  /// Whether the ten-failure auto-erase is running.
  final bool isErasing;

  /// The reason the last attempt was refused, already localised by the screen.
  final String? message;

  /// Whether a delay is in force.
  bool get isThrottled => remaining != null;

  /// Whether the entered PIN is long enough to submit.
  bool get isComplete => entered.length >= pinLength;

  /// A copy with the given fields replaced.
  LockEntryState copyWith({
    int? pinLength,
    String? entered,
    int? shakeTrigger,
    int? failedCount,
    Duration? remaining,
    bool clearRemaining = false,
    bool? isChecking,
    bool? biometricAvailable,
    bool? isErasing,
    String? message,
    bool clearMessage = false,
  }) => LockEntryState(
    pinLength: pinLength ?? this.pinLength,
    entered: entered ?? this.entered,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    failedCount: failedCount ?? this.failedCount,
    remaining: clearRemaining ? null : (remaining ?? this.remaining),
    isChecking: isChecking ?? this.isChecking,
    biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    isErasing: isErasing ?? this.isErasing,
    message: clearMessage ? null : (message ?? this.message),
  );
}

/// Why the last attempt failed, in terms the screen can localise.
///
/// A separate signal from [LockEntryState.message] so the screen owns every string (Law U5) while the
/// view-model owns the decision about which one applies.
enum LockEntryError {
  /// The PIN was wrong and no delay is owed yet.
  wrongPin,

  /// A delay is in force.
  throttled,

  /// The biometric prompt did not succeed.
  biometricFailed,

  /// The erase failed.
  eraseFailed,
}

/// The lock screen's entry state.
final lockEntryProvider = NotifierProvider<LockEntryNotifier, LockEntryState>(
  LockEntryNotifier.new,
);

/// Drives PIN entry, the throttle countdown, the biometric shortcut and the auto-erase.
class LockEntryNotifier extends Notifier<LockEntryState> {
  Timer? _ticker;

  @override
  LockEntryState build() {
    ref.onDispose(() => _ticker?.cancel());
    unawaited(_prime());
    return const LockEntryState(pinLength: 4);
  }

  /// The last error, for the screen to turn into a sentence.
  LockEntryError? get lastError => _lastError;
  LockEntryError? _lastError;

  Future<void> _prime() async {
    final lock = ref.read(pinServiceProvider);
    final length = await lock.readPinLength();
    final failed = await lock.readFailedCount();
    final remaining = await lock.remainingLockout();
    final biometric = await ref.read(biometricGateProvider).isAvailable;
    state = state.copyWith(
      pinLength: length,
      failedCount: failed,
      remaining: remaining,
      biometricAvailable: biometric,
    );
    if (remaining != null) _startTicker();
  }

  /// Appends a digit, submitting automatically once the PIN is long enough.
  ///
  /// **Auto-submits rather than waiting for a button.** A four-digit PIN with a separate Enter is five
  /// taps for a screen the user passes through several times a day, and there is nothing to review — the
  /// field is either right or it is not.
  Future<void> append(String digit) async {
    if (state.isThrottled || state.isChecking) return;
    final next = state.entered + digit;
    state = state.copyWith(entered: next, clearMessage: true);
    if (next.length >= state.pinLength) await submit();
  }

  /// Removes the last digit.
  void backspace() {
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
      clearMessage: true,
    );
  }

  /// Checks the entered PIN.
  Future<void> submit() async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true);
    final outcome = await ref.read(pinServiceProvider).verifyPin(state.entered);

    if (outcome.unlocked) {
      _ticker?.cancel();
      _lastError = null;
      state = state.copyWith(
        isChecking: false,
        entered: '',
        clearMessage: true,
      );
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }

    // **`notEnabled` means there is nothing to unlock, so let the user through.** Mapping it to `wrongPin` — as
    // this did — traps somebody behind a PIN that does not exist, and every digit they try says "not right". It
    // should be unreachable now that the phase is resolved before the first frame, but a lock screen with no way
    // past it is bad enough to guard twice.
    if (outcome.refusal == UnlockRefusal.notEnabled) {
      _lastError = null;
      state = state.copyWith(
        isChecking: false,
        entered: '',
        clearMessage: true,
      );
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }
    _lastError = outcome.isThrottled
        ? LockEntryError.throttled
        : LockEntryError.wrongPin;
    state = state.copyWith(
      isChecking: false,
      // Cleared, so the next attempt starts from an empty field rather than the user having to delete
      // four digits they already know are wrong.
      entered: '',
      shakeTrigger: state.shakeTrigger + 1,
      failedCount: outcome.failedCount,
      remaining: outcome.retryAfter,
    );
    if (outcome.retryAfter != null) _startTicker();

    // **Checked here and not inside `PinService`.** The service enforces ARCH_3 §2.3's throttle for
    // everyone; the erase is an opt-in the user turned on in Settings, so the decision belongs where the
    // setting is readable. Default off (§2.3), which is why an unset key reads as false.
    if (outcome.failedCount >= autoEraseFailureThreshold) {
      final enabled = await ref.read(autoEraseEnabledProvider.future);
      if (enabled) await _eraseEverything();
    }
  }

  /// Tries the biometric shortcut.
  ///
  /// **Subject to the same throttle as a PIN.** Otherwise the shortcut would be the cheaper of the two
  /// paths to attack, and a lock is only as strong as the weakest way in.
  Future<void> useBiometric({required String reason}) async {
    if (state.isThrottled || state.isChecking) return;
    state = state.copyWith(isChecking: true, clearMessage: true);
    final result = await ref
        .read(biometricGateProvider)
        .authenticate(reason: reason);
    if (result.isOk) {
      _lastError = null;
      state = state.copyWith(isChecking: false);
      ref.read(lockPhaseProvider.notifier).markUnlocked();
      return;
    }
    _lastError = LockEntryError.biometricFailed;
    state = state.copyWith(
      isChecking: false,
      // **No `shakeTrigger` and no `failedCount`.** A dismissed fingerprint prompt is not a wrong PIN,
      // and counting it toward the throttle would let a pocket-tap lock somebody out.
      message: '',
    );
  }

  Future<void> _eraseEverything() async {
    state = state.copyWith(isErasing: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    state = state.copyWith(isErasing: false);
    if (result.isFailure) {
      _lastError = LockEntryError.eraseFailed;
      return;
    }
    // The erase clears the lock too, so there is nothing left to unlock.
    await ref.read(lockPhaseProvider.notifier).refresh();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final remaining = await ref.read(pinServiceProvider).remainingLockout();
      if (remaining == null) {
        timer.cancel();
        state = state.copyWith(clearRemaining: true, clearMessage: true);
        return;
      }
      state = state.copyWith(remaining: remaining);
    });
  }
}
```

### `lib/features/lock/providers/lock_providers.dart`

```dart
/// Lock state, the router's refresh bridge, and the security setting keys (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** `pinServiceProvider` and `eraseServiceProvider`
/// live in `lib/app/providers/` and are watched from here (Law U19).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';

/// Why the app is showing the lock screen, or that it is not.
enum LockPhase {
  /// No lock is configured, or it has been satisfied for this session.
  open,

  /// A lock exists and has not been satisfied.
  locked,

  /// Still asking secure storage whether a lock exists.
  ///
  /// A distinct state rather than an optimistic `open`, because guessing wrong flashes the dashboard —
  /// including the funds header — for one frame before the lock appears. A lock that shows your balance
  /// on the way past is not a lock.
  unknown,
}

/// Whether a lock was configured when the app started.
///
/// **Overridden by `bootstrap()` with an awaited answer, which is what removes the race.** Reading secure storage
/// is asynchronous, so a `Notifier` that starts at [LockPhase.unknown] and resolves a frame later forces the
/// router to guess — and either guess is wrong for somebody. Guessing "locked" showed a lock screen to a fresh
/// install that had no PIN and no way past it; guessing "open" would flash the dashboard, balances included, at
/// somebody who does.
///
/// One awaited read before `runApp` costs a few milliseconds and removes the question.
final lockConfiguredAtStartupProvider = Provider<bool>((ref) {
  throw StateError(
    'lockConfiguredAtStartupProvider was not overridden. bootstrap() must supply it — see '
    'lib/app/bootstrap.dart. A widget test supplies false.',
  );
});

/// Whether the app is locked, and the one place that changes.
final lockPhaseProvider = NotifierProvider<LockNotifier, LockPhase>(
  LockNotifier.new,
);

/// Holds the lock phase and the three transitions it has.
class LockNotifier extends Notifier<LockPhase> {
  @override
  LockPhase build() {
    // **Synchronous, from a value `bootstrap()` already awaited.** No `unknown`, so the router never redirects on
    // a guess. `refresh()` remains for later changes — a lock enabled or removed in Settings.
    return ref.read(lockConfiguredAtStartupProvider)
        ? LockPhase.locked
        : LockPhase.open;
  }

  /// Re-reads whether a lock is configured, without changing whether it has been satisfied.
  ///
  /// Called on construction and after the lock is enabled or disabled in Settings.
  Future<void> refresh() async {
    final enabled = await ref.read(pinServiceProvider).isEnabled;
    state = enabled ? LockPhase.locked : LockPhase.open;
  }

  /// Records that the user has satisfied the lock for this session.
  void markUnlocked() => state = LockPhase.open;

  /// Locks the app again — on backgrounding past the auto-lock delay, or from Settings.
  ///
  /// A no-op when no lock is configured, so a "lock now" action cannot strand a user who has none
  /// behind a screen they have no way to pass.
  Future<void> lock() async {
    if (!await ref.read(pinServiceProvider).isEnabled) return;
    state = LockPhase.locked;
  }
}

/// Whether navigation should be redirected to the lock screen.
///
/// `unknown` counts as locked. Erring the other way would show the app for a frame while the answer
/// arrived, which is the one thing a lock exists to prevent.
final isLockedProvider = Provider<bool>(
  (ref) => ref.watch(lockPhaseProvider) != LockPhase.open,
);

// `routerRefreshProvider` used to live here. It moved to `app.dart` in the same phase it was written,
// because the router has **two** gates — this one and onboarding — and a bridge that listened to only
// one would leave the other decorative. It belongs with whatever knows about both.

/// How long the app may sit in the background before it locks again (ARCH_3 §2.2).
///
/// Sixty seconds by default: long enough to answer a message or check a rate and come back, short
/// enough that a phone left on a table is not open indefinitely.
const Duration autoLockDelay = Duration(seconds: 60);

/// The `app_settings` key holding the user's chosen auto-lock delay, in seconds.
const String autoLockDelaySettingKey = 'lock.autoLockSeconds';

/// The `app_settings` key holding whether ten failures erase everything (ARCH_3 §2.3).
///
/// **Defaults off, and the key stores only the choice.** The erase itself runs through `EraseService`;
/// this exists so a user who has never opened Security cannot lose their history to a child mashing
/// digits.
const String autoEraseSettingKey = 'lock.autoEraseAfterTenFailures';

/// How many consecutive failures trigger the optional auto-erase.
const int autoEraseFailureThreshold = 10;

/// Whether ten failures erase everything, off unless the user turned it on.
final autoEraseEnabledProvider = FutureProvider<bool>((ref) async {
  final stored = await ref
      .watch(settingsRepositoryProvider)
      .readValue(autoEraseSettingKey);
  return stored == 'true';
});

/// Re-locks the app when it returns from the background after [autoLockDelay].
///
/// **A widget rather than a service, because only a widget receives lifecycle events.** It wraps the
/// router's content, records the instant of backgrounding and compares on resume — so the elapsed time
/// is measured against the clock rather than by a timer, which would not survive the process being
/// killed and would make the lock defeatable by a task switch.
class AutoLockObserver extends ConsumerStatefulWidget {
  /// Wraps [child].
  const AutoLockObserver({required this.child, super.key});

  /// The app's content.
  final Widget child;

  @override
  ConsumerState<AutoLockObserver> createState() => _AutoLockObserverState();
}

class _AutoLockObserverState extends ConsumerState<AutoLockObserver>
    with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _leftAt ??= DateTime.now().toUtc();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _leftAt = null;
        if (left == null) return;
        if (DateTime.now().toUtc().difference(left) >= autoLockDelay) {
          unawaited(ref.read(lockPhaseProvider.notifier).lock());
        }
      case AppLifecycleState.inactive:
        // Deliberately ignored. `inactive` fires for a notification-shade pull and an incoming-call
        // banner, neither of which is leaving the app — locking on it would re-prompt for a PIN
        // several times a day for no reason.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

### `lib/features/lock/providers/pin_setup_providers.dart`

```dart
/// View-model state for setting or changing the PIN (ARCH_5 U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the setup flow is showing.
enum PinSetupStage {
  /// Choosing and entering a PIN.
  enter,

  /// Entering it a second time.
  confirm,

  /// The recovery code, shown once.
  recovery,

  /// The offer to make a backup, per ARCH_3 §2.2.
  backup,

  /// Finished.
  done,
}

/// What the setup flow is holding.
class PinSetupState {
  /// Creates a state.
  const PinSetupState({
    this.stage = PinSetupStage.enter,
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.recoveryCode,
    this.acknowledged = false,
    this.isSaving = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.failureMessage,
  });

  /// The part being shown.
  final PinSetupStage stage;

  /// Four digits, or six if the user chose it (ARCH_3 §2.1).
  final int length;

  /// The first entry.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// The code to show exactly once, formatted `ABCDE-FGHJK`.
  ///
  /// Held in memory only, and never written anywhere this app can read back — `PinService` stores its
  /// hash and nothing else. A code the app could redisplay would be one an attacker could read off a
  /// screen instead of guessing.
  final String? recoveryCode;

  /// Whether the one confirmation box is ticked.
  final bool acknowledged;

  /// Whether a write is in flight.
  final bool isSaving;

  /// Incremented on a mismatch, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the second entry differed from the first.
  final bool mismatch;

  /// The service's own message from a failed enable (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == PinSetupStage.confirm ? confirmed : entered;

  /// A copy with the given fields replaced.
  PinSetupState copyWith({
    PinSetupStage? stage,
    int? length,
    String? entered,
    String? confirmed,
    String? recoveryCode,
    bool? acknowledged,
    bool? isSaving,
    int? shakeTrigger,
    bool? mismatch,
    String? failureMessage,
    bool clearFailure = false,
  }) => PinSetupState(
    stage: stage ?? this.stage,
    length: length ?? this.length,
    entered: entered ?? this.entered,
    confirmed: confirmed ?? this.confirmed,
    recoveryCode: recoveryCode ?? this.recoveryCode,
    acknowledged: acknowledged ?? this.acknowledged,
    isSaving: isSaving ?? this.isSaving,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    mismatch: mismatch ?? this.mismatch,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The PIN setup flow's state.
final pinSetupProvider = NotifierProvider<PinSetupNotifier, PinSetupState>(
  PinSetupNotifier.new,
);

/// Drives the four stages ARCH_3 §2.2 specifies for enabling a lock.
class PinSetupNotifier extends Notifier<PinSetupState> {
  @override
  PinSetupState build() => const PinSetupState();

  /// Switches between a 4- and 6-digit PIN, discarding whatever was typed.
  ///
  /// Discarding is deliberate: keeping three digits of a four-digit attempt when the user asks for six
  /// leaves a half-filled field that looks like progress toward something it is not.
  void setLength(int length) => state = PinSetupState(length: length);

  /// Appends a digit to whichever entry is active, advancing when it is full.
  Future<void> append(String digit) async {
    if (state.isSaving) return;
    if (state.stage == PinSetupStage.enter) {
      final next = state.entered + digit;
      state = state.copyWith(
        entered: next,
        mismatch: false,
        clearFailure: true,
      );
      if (next.length >= state.length) {
        state = state.copyWith(stage: PinSetupStage.confirm);
      }
      return;
    }
    if (state.stage != PinSetupStage.confirm) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _commit();
  }

  /// Removes the last digit of the active entry, stepping back a stage when it empties.
  void backspace() {
    if (state.stage == PinSetupStage.confirm) {
      if (state.confirmed.isEmpty) {
        // Back to the first entry rather than nowhere: a user who mistyped the confirmation and holds
        // backspace should end up somewhere they can act, not at a dead field.
        state = state.copyWith(stage: PinSetupStage.enter, mismatch: false);
        return;
      }
      state = state.copyWith(
        confirmed: state.confirmed.substring(0, state.confirmed.length - 1),
        mismatch: false,
      );
      return;
    }
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
    );
  }

  Future<void> _commit() async {
    if (state.confirmed != state.entered) {
      // **Both entries are cleared, not just the second.** Somebody who mistyped does not know which of
      // the two was wrong, and re-confirming against a first entry they may have fat-fingered would set a
      // PIN they do not know.
      state = state.copyWith(
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref
        .read(pinServiceProvider)
        .enable(pin: state.entered);
    final code = result.valueOrNull;
    if (code == null) {
      state = state.copyWith(
        isSaving: false,
        stage: PinSetupStage.enter,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    // **The session is marked satisfied, and deliberately *not* refreshed.** Enabling a lock means
    // `PinService.isEnabled` now answers true, so re-reading it here would set the phase to `locked` —
    // firing the router's `refreshListenable` and ejecting the user to the lock screen from the very
    // screen where they just entered the PIN twice, which is more proof than the lock screen asks for.
    // The re-read exists for the opposite direction: a lock disabled elsewhere.
    ref.read(lockPhaseProvider.notifier).markUnlocked();

    state = state.copyWith(
      isSaving: false,
      stage: PinSetupStage.recovery,
      recoveryCode: code,
    );
  }

  /// Ticks or unticks the single confirmation box.
  void acknowledge({required bool value}) =>
      state = state.copyWith(acknowledged: value);

  /// Moves from the recovery code to the backup offer.
  void toBackupOffer() {
    if (!state.acknowledged) return;
    state = state.copyWith(stage: PinSetupStage.backup);
  }

  /// Exports a backup and offers to share it, then finishes.
  Future<bool> backupNow() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isSaving: false,
      stage: result.isOk ? PinSetupStage.done : PinSetupStage.backup,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Declines the backup and finishes.
  void skipBackup() => state = state.copyWith(stage: PinSetupStage.done);
}
```

### `lib/features/lock/providers/recovery_providers.dart`

```dart
/// View-model state for the forgotten-PIN and forgotten-both paths (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';

/// Which part of the recovery flow is showing.
enum RecoveryStage {
  /// Entering the recovery code.
  code,

  /// Choosing a new PIN.
  newPin,

  /// Entering the new PIN again.
  confirmPin,

  /// The last resort: erase and start over.
  forgotBoth,

  /// The PIN has been reset.
  done,
}

/// What the recovery flow is holding.
class RecoveryState {
  /// Creates a state.
  const RecoveryState({
    this.stage = RecoveryStage.code,
    this.code = '',
    this.length = 4,
    this.entered = '',
    this.confirmed = '',
    this.eraseTyped = '',
    this.isWorking = false,
    this.shakeTrigger = 0,
    this.mismatch = false,
    this.exported = false,
    this.failureMessage,
  });

  /// The stage being shown.
  final RecoveryStage stage;

  /// The recovery code as typed, hyphen and case included.
  ///
  /// Passed through unnormalised: `PinService.resetWithRecoveryCode` normalises and validates, and a second
  /// normaliser here could disagree with the one that actually checks.
  final String code;

  /// How many digits the new PIN will have.
  final int length;

  /// The first entry of the new PIN.
  final String entered;

  /// The second entry.
  final String confirmed;

  /// What the user has typed into the erase confirmation.
  final String eraseTyped;

  /// Whether a check, export or erase is in flight.
  final bool isWorking;

  /// Incremented on a rejection, so two in a row shake twice.
  final int shakeTrigger;

  /// Whether the two new-PIN entries differed.
  final bool mismatch;

  /// Whether a backup has been taken during this flow.
  final bool exported;

  /// The service's own message from the last failure (Law U9).
  final String? failureMessage;

  /// Which entry the keypad is filling.
  String get active => stage == RecoveryStage.confirmPin ? confirmed : entered;

  /// A copy with the given fields replaced.
  RecoveryState copyWith({
    RecoveryStage? stage,
    String? code,
    int? length,
    String? entered,
    String? confirmed,
    String? eraseTyped,
    bool? isWorking,
    int? shakeTrigger,
    bool? mismatch,
    bool? exported,
    String? failureMessage,
    bool clearFailure = false,
  }) => RecoveryState(
    stage: stage ?? this.stage,
    code: code ?? this.code,
    length: length ?? this.length,
    entered: entered ?? this.entered,
    confirmed: confirmed ?? this.confirmed,
    eraseTyped: eraseTyped ?? this.eraseTyped,
    isWorking: isWorking ?? this.isWorking,
    shakeTrigger: shakeTrigger ?? this.shakeTrigger,
    mismatch: mismatch ?? this.mismatch,
    exported: exported ?? this.exported,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}

/// The recovery flow's state.
final recoveryProvider = NotifierProvider<RecoveryNotifier, RecoveryState>(
  RecoveryNotifier.new,
);

/// Drives recovery by code, and the erase behind it.
class RecoveryNotifier extends Notifier<RecoveryState> {
  @override
  RecoveryState build() => const RecoveryState();

  /// Records the typed code.
  void setCode(String code) =>
      state = state.copyWith(code: code, clearFailure: true);

  /// Moves to choosing a new PIN.
  ///
  /// **The code is not checked here.** `PinService.resetWithRecoveryCode` verifies it and the throttle
  /// together, at the point it would set the new PIN — so a wrong code costs one throttled attempt rather
  /// than an unlimited number of free guesses against a check with nothing behind it.
  void toNewPin() {
    if (state.code.trim().isEmpty) return;
    state = state.copyWith(stage: RecoveryStage.newPin, clearFailure: true);
  }

  /// Switches between a 4- and 6-digit new PIN, discarding what was typed.
  void setLength(int length) => state = state.copyWith(
    length: length,
    entered: '',
    confirmed: '',
    mismatch: false,
  );

  /// Appends a digit to whichever entry is active.
  Future<void> append(String digit) async {
    if (state.isWorking) return;
    if (state.stage == RecoveryStage.newPin) {
      final next = state.entered + digit;
      state = state.copyWith(
        entered: next,
        mismatch: false,
        clearFailure: true,
      );
      if (next.length >= state.length) {
        state = state.copyWith(stage: RecoveryStage.confirmPin);
      }
      return;
    }
    if (state.stage != RecoveryStage.confirmPin) return;
    final next = state.confirmed + digit;
    state = state.copyWith(confirmed: next, mismatch: false);
    if (next.length >= state.length) await _reset();
  }

  /// Removes the last digit, stepping back a stage when the entry empties.
  void backspace() {
    if (state.stage == RecoveryStage.confirmPin) {
      if (state.confirmed.isEmpty) {
        state = state.copyWith(stage: RecoveryStage.newPin, mismatch: false);
        return;
      }
      state = state.copyWith(
        confirmed: state.confirmed.substring(0, state.confirmed.length - 1),
        mismatch: false,
      );
      return;
    }
    if (state.entered.isEmpty) return;
    state = state.copyWith(
      entered: state.entered.substring(0, state.entered.length - 1),
    );
  }

  Future<void> _reset() async {
    if (state.confirmed != state.entered) {
      state = state.copyWith(
        stage: RecoveryStage.newPin,
        entered: '',
        confirmed: '',
        mismatch: true,
        shakeTrigger: state.shakeTrigger + 1,
      );
      return;
    }

    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref
        .read(pinServiceProvider)
        .resetWithRecoveryCode(
          code: state.code,
          newPin: state.entered,
        );
    if (result.isFailure) {
      // **Back to the code stage, not the PIN stage.** A rejection here is almost always a wrong recovery
      // code rather than a mistyped new PIN, and leaving somebody on the keypad to try the same code again
      // spends another throttled attempt on the same mistake.
      state = state.copyWith(
        isWorking: false,
        stage: RecoveryStage.code,
        entered: '',
        confirmed: '',
        shakeTrigger: state.shakeTrigger + 1,
        failureMessage: result.failureOrNull?.message,
      );
      return;
    }

    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The new PIN satisfies this session: somebody who has just chosen one, twice, should not be asked for
    // it again on the way out.
    ref.read(lockPhaseProvider.notifier).markUnlocked();
  }

  /// Opens the last resort.
  void toForgotBoth() => state = state.copyWith(
    stage: RecoveryStage.forgotBoth,
    clearFailure: true,
  );

  /// Records what has been typed into the erase confirmation.
  void setEraseTyped(String value) => state = state.copyWith(eraseTyped: value);

  /// Exports a backup before erasing, per ARCH_3 §2.2.
  ///
  /// **Possible only because the database is plaintext and the lock is not a decryption key.** This is the
  /// path the redesign bought: nobody permanently loses their financial history to a forgotten PIN.
  Future<bool> exportFirst() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).exportAndShare();
    state = state.copyWith(
      isWorking: false,
      exported: result.isOk,
      failureMessage: result.isOk ? null : result.failureOrNull?.message,
    );
    return result.isOk;
  }

  /// Erases everything, once the confirmation word has been typed exactly.
  Future<bool> eraseEverything() async {
    state = state.copyWith(isWorking: true, clearFailure: true);
    final result = await ref.read(dataTransferPortProvider).eraseEverything();
    if (result.isFailure) {
      state = state.copyWith(
        isWorking: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(isWorking: false, stage: RecoveryStage.done);
    // The erase cleared the lock as well as the data, so re-reading leaves the app open.
    await ref.read(lockPhaseProvider.notifier).refresh();
    return true;
  }
}
```

### `lib/features/onboarding/presentation/screens/onboarding_flow.dart`

```dart
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
        // **Keyed to `name` now that it is first.** Left on `currency` this would have offered Back on
        // the opening screen, pointing at a step nobody had seen.
        secondaryLabel: draft.step == OnboardingStep.name
            ? null
            : strings.actionBack,
        onSecondary: draft.step == OnboardingStep.name
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
              OnboardingStep.name => const _NameStep(),
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
      case OnboardingStep.name:
        // Advances whether a name was given or not — see `commitName`. A blank field is this step's own
        // skip, since the app-bar Skip abandons the whole flow rather than one question.
        await controller.commitName();
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
    OnboardingStep.name => OnboardingStep.name,
    OnboardingStep.currency => OnboardingStep.name,
    OnboardingStep.accounts || OnboardingStep.done => OnboardingStep.currency,
  };

  String _stepTitle(AlayaStrings strings, OnboardingStep step) =>
      switch (step) {
        OnboardingStep.name => strings.onboardingNameTitle,
        OnboardingStep.currency => strings.onboardingCurrencyTitle,
        OnboardingStep.accounts ||
        OnboardingStep.done => strings.onboardingAccountsTitle,
      };

  String _primaryLabel(
    AlayaStrings strings,
    OnboardingStep step,
  ) => switch (step) {
    OnboardingStep.name || OnboardingStep.currency => strings.onboardingNext,
    OnboardingStep.accounts || OnboardingStep.done => strings.onboardingFinish,
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
      OnboardingStep.name => 1,
      OnboardingStep.currency => 2,
      OnboardingStep.accounts || OnboardingStep.done => 3,
    };
    return Text(
      // Three again, and the third is not the old security step — that moved to Settings › Security. The
      // name step joined the front, where the friendliest question belongs.
      strings.onboardingStepOf(index, 3),
      style: AlayaTypography.overline.copyWith(color: context.semantic.muted),
    );
  }
}

/// Step one: what to call the user.
///
/// **A body widget, not a page.** This flow puts its primary button in a shared `AlayaFormScaffold`
/// footer and dispatches per step, so a step contributes content and the scaffold owns Continue, Back and
/// Skip. A self-contained page with its own button would have given the opening screen two of them.
///
/// **Optional, and Continue with a blank field is how you say no.** ARCH_5 §3 archetype B makes the whole
/// flow skippable; the app-bar Skip abandons all of it, so this step needs its own smaller exit — and an
/// empty name simply advances. Nothing is written, and nothing records that the question was declined,
/// because there is nothing to remember about it.
///
/// **The name is not stored as text anywhere.** It becomes a `payees` row with `kind: person`, and
/// `split.selfPayeeId` points at it. Somebody who renames themselves under Settings › Payees renames
/// themselves everywhere, because there is no second copy to disagree.
class _NameStep extends ConsumerStatefulWidget {
  const _NameStep();

  @override
  ConsumerState<_NameStep> createState() => _NameStepState();
}

class _NameStepState extends ConsumerState<_NameStep> {
  late final TextEditingController _name = TextEditingController(
    // Seeded from the draft rather than left blank: `_load` fills it from the existing payee, so somebody
    // who set a name, closed the app mid-flow and came back sees what they already gave.
    text: ref.read(onboardingControllerProvider).displayName,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          // Says what the answer buys. "Enter your name" is a form field; naming what it unlocks is a
          // reason, and a reason is what makes an optional question worth answering.
          strings.onboardingNameBody,
          style: AlayaTypography.body.copyWith(color: semantic.muted),
        ),
        const SizedBox(height: AlayaSpacing.lg),
        TextField(
          controller: _name,
          // **No `autofocus`, and this is the screen where it mattered most.** It is the first thing a new
          // user sees, and the keyboard covered the Skip button in the footer — hiding the way past an
          // optional question on the one screen where somebody has not yet decided to trust the app.
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: strings.onboardingNameLabel),
          // Written to the draft on every keystroke, so the footer's Continue reads the same value the
          // field shows. Keeping it only in this widget would make the button commit whatever the draft
          // last happened to hold.
          onChanged: (value) => ref
              .read(onboardingControllerProvider.notifier)
              .setDisplayName(value),
        ),
        const SizedBox(height: AlayaSpacing.sm),
        Text(
          strings.onboardingNameOptional,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
      ],
    );
  }
}

/// Step two: the currency totals are shown in.
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

/// Step three: the accounts, and what was in them when the user started.
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
```

### `lib/features/onboarding/providers/onboarding_providers.dart`

```dart
/// View-model state for the first-run flow (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** `accountRepositoryProvider`,
/// `settingsRepositoryProvider` and the rest live in `lib/app/providers/` and are watched from here
/// (Law U19).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/profile_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/clock.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/onboarding/state/onboarding_state.dart';

/// Whether the first-run flow still has to happen.
enum OnboardingPhase {
  /// Still asking `app_settings`.
  ///
  /// Distinct from `needed`, so the router does not push a brand-new user into onboarding and then pull
  /// them out again a frame later when the answer arrives.
  unknown,

  /// Not finished and not skipped.
  needed,

  /// Finished, or skipped deliberately.
  done,
}

/// Whether onboarding had already been finished when the app started.
///
/// **Overridden by `bootstrap()` with an awaited answer**, for the same reason the lock has one — and
/// after the same bug. A `Notifier` that starts at [OnboardingPhase.unknown] and resolves a frame later
/// leaves the router's first decision wrong, and worse, it can miss its own correction: if `_restore()`
/// completes before `GoRouter` attaches its `refreshListenable`, the notification lands on nobody and the
/// redirect does not re-run until the next navigation. The symptom is a first-run flow that appears when
/// the user opens Settings.
///
/// One awaited settings read before `runApp` removes both halves.
final onboardingDoneAtStartupProvider = Provider<bool>((ref) {
  throw StateError(
    'onboardingDoneAtStartupProvider was not overridden. bootstrap() must supply it — see '
    'lib/app/bootstrap.dart. A widget test supplies true, so no test is redirected into onboarding.',
  );
});

/// Whether onboarding is still owed, and the one place that changes.
final onboardingPhaseProvider =
    NotifierProvider<OnboardingPhaseNotifier, OnboardingPhase>(
      OnboardingPhaseNotifier.new,
    );

/// Reads and records whether onboarding is finished.
class OnboardingPhaseNotifier extends Notifier<OnboardingPhase> {
  @override
  OnboardingPhase build() {
    // Synchronous, from a value `bootstrap()` already awaited — so the router's first decision is correct
    // and does not depend on a notification arriving after a listener exists.
    return ref.read(onboardingDoneAtStartupProvider)
        ? OnboardingPhase.done
        : OnboardingPhase.needed;
  }

  /// Records that onboarding is over, whether finished or skipped.
  ///
  /// The write is awaited, unlike the theme and range preferences: this is the flag that stops the router
  /// sending the user back, and losing it would restart the flow on the next launch.
  Future<void> complete() async {
    await ref
        .read(settingsRepositoryProvider)
        .writeValue(
          key: OnboardingKeys.done,
          value: 'true',
          valueType: 'string',
        );
    state = OnboardingPhase.done;
  }
}

/// Whether the router should redirect to the first-run flow.
///
/// There is no guess left to make: the phase is resolved before the first frame, so `unknown` never
/// reaches the router. It remains on the enum only for a scope that has not been given a startup value —
/// which now throws rather than defaulting, because a silent default is what produced the bug this
/// replaced.
final needsOnboardingProvider = Provider<bool>(
  (ref) => ref.watch(onboardingPhaseProvider) == OnboardingPhase.needed,
);

/// The currencies the picker offers.
///
/// **Declared here rather than reusing 6A's `enabledCurrenciesProvider`, which lives inside
/// `quick_add_sheet.dart`.** Importing a sheet to obtain a provider is worse coupling than a second
/// stream over `currencies` — a five-row seeded table — and 7B's rule about not duplicating a stream was
/// about `accounts`, which grows. Consolidating the two belongs in Phase 9's sweep, along with moving
/// that provider out of a screen file.
final onboardingCurrenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchEnabled(),
);

/// One currency's minor-unit precision, so an amount field shows the right number of decimals.
///
/// JPY has none, and an opening balance typed as `1200` becoming `¥1,200.00` is the bug this prevents.
final onboardingCurrencyDigitsProvider = FutureProvider.family<int, String>((
  ref,
  code,
) async {
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// The first-run flow's draft and every transition it has.
final onboardingControllerProvider =
    NotifierProvider<OnboardingController, OnboardingDraft>(
      OnboardingController.new,
    );

/// Holds the draft, loads what the seeder already created, and commits.
class OnboardingController extends Notifier<OnboardingDraft> {
  @override
  OnboardingDraft build() {
    unawaited(_load());
    return const OnboardingDraft(
      step: OnboardingStep.name,
      homeCurrencyCode: fallbackHomeCurrencyCode,
      accounts: <DraftAccount>[],
    );
  }

  /// The currency assumed until `app_settings` answers.
  ///
  /// Matches Phase 1C's seeder default so the first frame agrees with the database rather than flicking
  /// from one code to another.
  static const String fallbackHomeCurrencyCode = 'INR';

  /// Loads the seeded accounts, the stored step, and any name already claimed.
  ///
  /// **The flow edits as much as it creates.** Phase 1C's seeder already inserts two accounts and a
  /// `homeCurrencyCode`, so starting from an empty list would either duplicate them or quietly ignore
  /// them — and a first-run screen that shows none of the accounts the app already has reads as broken.
  ///
  /// The name is read for the same reason: somebody who typed it, closed the app mid-flow and came back
  /// should see what they already gave rather than an empty field that makes them wonder whether it saved.
  Future<void> _load() async {
    final settings = ref.read(settingsRepositoryProvider);
    final home =
        await settings.readHomeCurrencyCode() ?? fallbackHomeCurrencyCode;
    final storedStep = await settings.readValue(OnboardingKeys.step);
    final existing = await ref
        .read(accountRepositoryProvider)
        .watchSelectable()
        .first;
    final name = await ref.read(userDisplayNameProvider.future);
    state = state.copyWith(
      step: OnboardingKeys.parseStep(storedStep),
      homeCurrencyCode: home,
      accounts: [for (final account in existing) DraftAccount.from(account)],
      displayName: name ?? '',
      isLoaded: true,
    );
  }

  /// Records what the user is typing as their name.
  ///
  /// **Not trimmed here.** Trimming mid-typing would eat the space between a first and last name the
  /// instant it was typed; [commitName] trims once, at the point it matters.
  void setDisplayName(String value) {
    state = state.copyWith(displayName: value, clearFailure: true);
  }

  /// Claims the name if one was given, then moves to the currency step.
  ///
  /// **A blank name advances without writing anything, and that is this step's own skip.** The app-bar
  /// Skip abandons the whole flow, so the opening question needed a smaller exit than that — and there is
  /// nothing to record about having declined, because every screen that wants a name already handles not
  /// having one.
  ///
  /// **Delegates to [claimSelfProvider] rather than creating the payee here.** That notifier already
  /// reuses an existing person of the same name instead of cloning them, and duplicating that rule in a
  /// second place is how two "Ravi" rows appear with one of them being the user — the worst possible state
  /// for a module built on who owes whom.
  Future<bool> commitName() async {
    final name = state.displayName.trim();
    if (name.isEmpty) {
      await goTo(OnboardingStep.currency);
      return true;
    }

    state = state.copyWith(isSaving: true, clearFailure: true);
    final claimer = ref.read(claimSelfProvider.notifier);
    final ok = await claimer.claim(name);
    if (!ok) {
      state = state.copyWith(
        isSaving: false,
        // The repository's own sentence where there is one — a duplicate name says so, where "something
        // went wrong" would leave somebody retyping the same thing (Law U9).
        failureMessage: claimer.lastError,
      );
      return false;
    }
    state = state.copyWith(isSaving: false);
    await goTo(OnboardingStep.currency);
    return true;
  }

  /// Sets the currency totals are shown in, carrying untouched accounts with it.
  ///
  /// **Untouched accounts follow; chosen ones do not.** Somebody selecting yen does not want two rupee
  /// accounts they never asked for, and equally does not want an account they deliberately set to rupees
  /// rewritten behind them. `DraftAccount.currencyTouched` is what separates the two.
  void setHomeCurrency(String code) {
    state = state.copyWith(
      homeCurrencyCode: code,
      accounts: [
        for (final account in state.accounts)
          account.currencyTouched
              ? account
              : account.copyWith(currencyCode: code),
      ],
      clearFailure: true,
    );
  }

  /// Adds an empty account row, in the home currency and dated today.
  void addAccount() {
    state = state.copyWith(
      accounts: [
        ...state.accounts,
        DraftAccount(
          name: '',
          kind: AccountKind.cash,
          currencyCode: state.homeCurrencyCode,
          openingMinor: 0,
          openingDate: ref.read(clockProvider).today(),
        ),
      ],
      clearFailure: true,
    );
  }

  /// Replaces the row at [index].
  void updateAccount(int index, DraftAccount account) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..[index] = account;
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Marks the row at [index] as having a currency the user chose.
  void setAccountCurrency(int index, String code) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]
      ..[index] = state.accounts[index].copyWith(
        currencyCode: code,
        currencyTouched: true,
      );
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Removes the row at [index].
  ///
  /// A row that already exists in the database is **not** deleted here — removing it from the draft only
  /// stops this flow writing to it. Deleting an account is a destructive action with its own tier in
  /// ARCH_5 §5.5, and burying it in a first-run screen would be the wrong place for it.
  void removeAccount(int index) {
    if (index < 0 || index >= state.accounts.length) return;
    final next = [...state.accounts]..removeAt(index);
    state = state.copyWith(accounts: next, clearFailure: true);
  }

  /// Moves to [step] and remembers it, so a restart resumes here.
  Future<void> goTo(OnboardingStep step) async {
    state = state.copyWith(step: step, clearFailure: true);
    await ref
        .read(settingsRepositoryProvider)
        .writeValue(
          key: OnboardingKeys.step,
          value: step.name,
          valueType: 'string',
        );
  }

  /// Writes the home currency, then moves to the accounts step.
  ///
  /// Through `writeHomeCurrencyCode` rather than `writeValue` with a key: the key lives in `data/`, which a
  /// feature may not import, and a literal here would write to a dead key the moment `data/` renamed it.
  Future<bool> commitCurrency() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final result = await ref
        .read(settingsRepositoryProvider)
        .writeHomeCurrencyCode(state.homeCurrencyCode);
    if (result.isFailure) {
      state = state.copyWith(
        isSaving: false,
        failureMessage: result.failureOrNull?.message,
      );
      return false;
    }
    state = state.copyWith(isSaving: false);
    await goTo(OnboardingStep.accounts);
    return true;
  }

  /// Saves every account, then finishes.
  ///
  /// **Stops at the first failure rather than continuing.** Half-written accounts with the other half
  /// reported as an error is a worse state to leave someone in than nothing written, and Law L14's
  /// all-or-nothing reasoning applies to a loop of writes as much as to a transaction.
  Future<bool> commitAccounts() async {
    state = state.copyWith(isSaving: true, clearFailure: true);
    final repository = ref.read(accountRepositoryProvider);
    final normalizer = ref.read(normalizerProvider);
    final uids = ref.read(uidGeneratorProvider);
    for (var i = 0; i < state.accounts.length; i++) {
      final draft = state.accounts[i];
      final account = Account(
        id: draft.id ?? uids.generate(),
        name: draft.name.trim(),
        normalizedName: normalizer.normalize(draft.name),
        kind: draft.kind,
        currencyCode: draft.currencyCode,
        openingBalance: Money(draft.openingMinor, draft.currencyCode),
        openingBalanceDateKey: draft.openingDate,
        isArchived: false,
        includeInNetWorth: draft.includeInNetWorth,
        sortOrder: i,
      );
      final result = await repository.save(account);
      if (result.isFailure) {
        state = state.copyWith(
          isSaving: false,
          failureMessage: result.failureOrNull?.message,
        );
        return false;
      }
    }
    state = state.copyWith(isSaving: false);
    // **Straight to finished. There is no security step any more.**
    //
    // Asking a first-time user to choose a PIN before they had entered a single transaction put the most
    // abandonable question in the flow at the point they had least reason to answer it — and it was the
    // step that needed a redirect exemption, an embedded widget and a post-frame callback to report
    // upward. Settings › Security offers the same thing later, when there is something worth locking.
    await finish();
    return true;
  }

  /// Ends the flow, whether the user finished it or skipped.
  Future<void> finish() async {
    await goTo(OnboardingStep.done);
    await ref.read(onboardingPhaseProvider.notifier).complete();
  }
}
```

### `lib/features/onboarding/state/onboarding_state.dart`

```dart
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';

/// Which step of the first-run flow the user is on.
///
/// Stored by name, so resuming survives a restart and a reorder of this enum does not silently move
/// somebody to a different step (Law L13's reasoning, applied to a settings row rather than a column).
enum OnboardingStep {
  /// What to call the user.
  ///
  /// **First, and deliberately the friendliest thing in the flow.** A name is a warmer opening question
  /// than a currency picker, and it is the one answer several unrelated features want: which share is
  /// yours on a split, who a shared summary is from, what a dashboard greets you by.
  ///
  /// It is also the step that unblocks a whole module. Nothing in Split works until the app knows which
  /// payee the user is, and the screens that noticed used to point at a settings branch whose list of
  /// candidates was empty — four screens deferring to each other, with a dead end at the end of it.
  name,

  /// Which currency totals are shown in.
  currency,

  /// The accounts, and what was in them when the user started.
  accounts,

  /// Finished or skipped.
  done,
}

/// How the first-run flow is stored.
abstract final class OnboardingKeys {
  /// The `app_settings` key holding whether onboarding is finished or was skipped.
  static const String done = 'onboarding.done';

  /// The `app_settings` key holding the furthest step reached.
  ///
  /// **Written on every step change, which is what "resumable" costs.** A flow that only recorded
  /// completion would restart from the beginning after a phone call at step two, and re-asking someone
  /// for their opening balances is the fastest way to have them skip the flow entirely.
  static const String step = 'onboarding.step';

  /// Parses a stored step name, falling back to the first step.
  ///
  /// **The fallback is now `name` rather than `currency`, and that is a real behaviour change.** A
  /// half-finished install stores its own step by name and resumes exactly where it was, so nobody is
  /// moved; only a database with a missing or unrecognisable value lands here, and starting such a
  /// session at the first step is what "fall back" has always meant.
  static OnboardingStep parseStep(String? stored) {
    for (final step in OnboardingStep.values) {
      if (step.name == stored) return step;
    }
    return OnboardingStep.name;
  }
}

/// One account being set up, before it is saved.
///
/// A draft rather than an `Account`, because an `Account` requires a `normalizedName` and a `sortOrder`
/// that the user never sees and should not have to think about, and because half of these rows already
/// exist in the database — Phase 1C's seeder creates two — so the flow is editing as much as creating.
class DraftAccount {
  /// Creates a draft.
  const DraftAccount({
    required this.name,
    required this.kind,
    required this.currencyCode,
    required this.openingMinor,
    required this.openingDate,
    this.id,
    this.includeInNetWorth = true,
    this.currencyTouched = false,
  });

  /// A draft of an account that already exists, keeping every value it has.
  factory DraftAccount.from(Account account) => DraftAccount(
    id: account.id,
    name: account.name,
    kind: account.kind,
    currencyCode: account.currencyCode,
    openingMinor: account.openingBalance.minor,
    openingDate: account.openingBalanceDateKey,
    includeInNetWorth: account.includeInNetWorth,
  );

  /// The existing account's id, or null for one being added.
  final String? id;

  /// What the user calls it.
  final String name;

  /// Cash, bank, wallet, card or other.
  final AccountKind kind;

  /// The currency the balance is held in.
  ///
  /// Its own field and not derived from the home currency, because Law L9 makes the home currency a
  /// display choice: an account in yen stays in yen however the user chooses to see totals.
  final String currencyCode;

  /// What was in it on [openingDate], in minor units.
  final int openingMinor;

  /// The date the balance was true on.
  ///
  /// **This is the half of the pair that gets forgotten** (anomaly A03). A balance without a date cannot
  /// be placed in a ledger, so every transaction before it would be silently unaccounted for.
  final DateKey openingDate;

  /// Whether it counts toward net worth.
  final bool includeInNetWorth;

  /// Whether the user has chosen this account's currency themselves.
  ///
  /// **Why a flag and not a comparison.** Changing the home currency on the currency step should carry
  /// the seeded accounts with it — nobody choosing yen wants two rupee accounts they did not ask for —
  /// but it must not overwrite a currency the user set deliberately. Comparing against the old home
  /// currency cannot tell those apart when they happen to match.
  final bool currencyTouched;

  /// The balance as a `Money`.
  Money get openingBalance => Money(openingMinor, currencyCode);

  /// Whether this draft is complete enough to save.
  bool get isValid => name.trim().isNotEmpty && currencyCode.isNotEmpty;

  /// A copy with the given fields replaced.
  DraftAccount copyWith({
    String? name,
    AccountKind? kind,
    String? currencyCode,
    int? openingMinor,
    DateKey? openingDate,
    bool? includeInNetWorth,
    bool? currencyTouched,
  }) => DraftAccount(
    id: id,
    name: name ?? this.name,
    kind: kind ?? this.kind,
    currencyCode: currencyCode ?? this.currencyCode,
    openingMinor: openingMinor ?? this.openingMinor,
    openingDate: openingDate ?? this.openingDate,
    includeInNetWorth: includeInNetWorth ?? this.includeInNetWorth,
    currencyTouched: currencyTouched ?? this.currencyTouched,
  );
}

/// Everything the first-run flow is holding.
class OnboardingDraft {
  /// Creates a draft.
  const OnboardingDraft({
    required this.step,
    required this.homeCurrencyCode,
    required this.accounts,
    this.displayName = '',
    this.isLoaded = false,
    this.isSaving = false,
    this.failureMessage,
  });

  /// The step being shown.
  final OnboardingStep step;

  /// The currency totals are aggregated into (Law L9).
  final String homeCurrencyCode;

  /// The accounts being set up, seeded ones included.
  final List<DraftAccount> accounts;

  /// What the user has typed as their name, or empty when they have not.
  ///
  /// **Held in the draft rather than read from the payee on every rebuild**, because this is a field
  /// somebody is part-way through typing. Reading the saved value would fight the keystroke; the payee is
  /// written once, on commit, and `_load` seeds this from it so resuming shows what was already given.
  final String displayName;

  /// Whether the existing accounts and settings have been read yet.
  final bool isLoaded;

  /// Whether a save is in flight.
  final bool isSaving;

  /// The repository's own message from the last failed write (Law U9).
  final String? failureMessage;

  /// Whether every account is complete enough to save.
  bool get accountsAreValid =>
      accounts.isNotEmpty && accounts.every((account) => account.isValid);

  /// A copy with the given fields replaced.
  ///
  /// [failureMessage] is cleared by passing [clearFailure], because `null` cannot distinguish "leave it"
  /// from "clear it" in a `copyWith` — and a stale error under a field the user has since fixed is worse
  /// than no error at all.
  OnboardingDraft copyWith({
    OnboardingStep? step,
    String? homeCurrencyCode,
    List<DraftAccount>? accounts,
    String? displayName,
    bool? isLoaded,
    bool? isSaving,
    String? failureMessage,
    bool clearFailure = false,
  }) => OnboardingDraft(
    step: step ?? this.step,
    homeCurrencyCode: homeCurrencyCode ?? this.homeCurrencyCode,
    accounts: accounts ?? this.accounts,
    displayName: displayName ?? this.displayName,
    isLoaded: isLoaded ?? this.isLoaded,
    isSaving: isSaving ?? this.isSaving,
    failureMessage: clearFailure
        ? null
        : (failureMessage ?? this.failureMessage),
  );
}
```

### `lib/features/settings/presentation/screens/about_settings_screen.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › About (ARCH_5 §3 archetype D, outside the shell).
///
/// **No version number, and that is a dependency decision rather than an oversight.** Reading one at runtime needs
/// `package_info_plus`, which ARCH_1 §7 does not pin — and adding a package so that one row can show a string
/// would be the opposite of §7.4's discipline. A hard-coded constant would be worse: it would be wrong from the
/// first release that forgot to update it, which is more misleading than saying nothing.
///
/// The licence page is Flutter's own `showLicensePage`, which enumerates every dependency's licence from the
/// build rather than from a list somebody has to maintain by hand.
class AboutSettingsScreen extends StatelessWidget {
  /// Creates the screen.
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAbout)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(strings.appName, style: AlayaTypography.screenTitle),
                const SizedBox(height: AlayaSpacing.xs),
                Text(strings.aboutTagline, style: AlayaTypography.body),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.aboutHowItWorksHeader),
          ),
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The same threat model the lock screen states, in the place somebody comes looking for it. Saying
                // it in two places is not duplication — one is a decision point and the other is where a question
                // gets answered.
                Text(strings.aboutOfflineBody, style: AlayaTypography.body),
                const SizedBox(height: AlayaSpacing.sm),
                Text(strings.aboutStorageBody, style: AlayaTypography.body),
              ],
            ),
          ),
          ListTile(
            leading: Icon(
              Icons.description_outlined,
              size: AlayaIconSize.lg,
              color: semantic.muted,
            ),
            title: Text(
              strings.aboutLicences,
              style: AlayaTypography.cardTitle,
            ),
            subtitle: Text(
              strings.aboutLicencesHelp,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
            onTap: () => showLicensePage(
              context: context,
              applicationName: strings.appName,
            ),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/settings/presentation/screens/account_editor_screen.dart`

```dart
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
```

### `lib/features/settings/presentation/screens/accounts_settings_screen.dart`

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
```

### `lib/features/settings/presentation/screens/appearance_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/app.dart';
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Appearance (ARCH_5 §3 archetype D, outside the shell).
///
/// **This is the visible half of ARCH_4 §5.1 item 23.** Part 1 turned `activePaletteProvider` and
/// `themeModeProvider` into persisted `Notifier`s; this is where a person changes them. Both write to
/// `app_settings` on selection, so a choice survives a restart — which as bare `StateProvider`s it did not.
///
/// **No Save button, deliberately.** A theme is its own preview: the whole tree rethemes on the frame the swatch
/// is tapped, so a commit would ask the user to confirm something they can already see. Archetype D has no
/// commit for the same reason.
class AppearanceSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const AppearanceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final palette = ref.watch(activePaletteProvider);
    final mode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsAppearance)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.appearanceModeHeader),
          ),
          for (final option in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: option,
              groupValue: mode,
              onChanged: (next) {
                if (next == null) return;
                ref.read(themeModeProvider.notifier).use(next);
              },
              title: Text(
                _modeLabel(strings, option),
                style: AlayaTypography.body,
              ),
              subtitle: option == ThemeMode.system
                  ? Text(
                      strings.appearanceModeSystemHelp,
                      style: AlayaTypography.caption.copyWith(
                        color: context.semantic.muted,
                      ),
                    )
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.lg,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: SectionHeader(label: strings.appearancePaletteHeader),
          ),
          for (final preset in AlayaPresets.all)
            _PaletteRow(
              palette: preset,
              selected: preset.name == palette.name,
              onTap: () => ref.read(activePaletteProvider.notifier).use(preset),
            ),
          const SizedBox(height: AlayaSpacing.lg),
          ListTile(
            leading: Icon(
              Icons.science_outlined,
              size: AlayaIconSize.lg,
              color: context.semantic.muted,
            ),
            title: Text(strings.navThemeLab, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.appearanceThemeLabHelp,
              style: AlayaTypography.caption.copyWith(
                color: context.semantic.muted,
              ),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: context.semantic.muted,
            ),
            onTap: () => context.push(Routes.themeLab),
          ),
        ],
      ),
    );
  }

  String _modeLabel(AlayaStrings strings, ThemeMode mode) => switch (mode) {
    ThemeMode.system => strings.appearanceModeSystem,
    ThemeMode.light => strings.appearanceModeLight,
    ThemeMode.dark => strings.appearanceModeDark,
  };
}

/// One palette, previewed by its own colours rather than described.
class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AlayaPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The swatches are drawn from the palette being offered, not from the active theme — a row previewing
    // itself in the *current* palette's colours would render five identical rows.
    //
    // `primary`, `accent` and `surfaceRaised`, because those are the three `AlayaColorSet` actually declares.
    // Material's `secondary`/`tertiary` vocabulary does not appear in Alaya's palette type, and reaching for it
    // from memory is how a preview ends up compiling against the wrong colour system.
    final set = Theme.of(context).brightness == Brightness.dark
        ? palette.dark
        : palette.light;
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final colour in [set.primary, set.accent, set.surfaceRaised])
            Padding(
              padding: const EdgeInsets.only(right: AlayaSpacing.xxs),
              child: Container(
                width: AlayaSpacing.md,
                height: AlayaSpacing.xl,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: AlayaRadii.borderSm,
                ),
              ),
            ),
        ],
      ),
      title: Text(palette.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        palette.description,
        style: AlayaTypography.caption.copyWith(color: context.semantic.muted),
      ),
      trailing: selected
          ? Icon(Icons.check_circle, size: AlayaIconSize.md, color: set.primary)
          : null,
      onTap: onTap,
    );
  }
}
```

### `lib/features/settings/presentation/screens/currencies_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/currency.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Currencies (ARCH_5 §3 archetype D, outside the shell).
///
/// **Enabling and disabling only — nothing here creates a currency.** The list is the ISO set the seeder
/// installed, and a user-invented currency would have no rate source, so every amount in it would be
/// permanently unconvertible (ARCH_3 §1). Disabling is what keeps the pickers short.
///
/// **The home currency cannot be disabled, and the switch says why rather than vanishing.** Law L9 makes it the
/// unit every total is aggregated into; disabling it would leave the dashboard with no currency to add up in.
class CurrenciesSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const CurrenciesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final currencies = ref.watch(currenciesSettingsProvider);
    final home = ref.watch(homeCurrencyCodeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsCurrencies)),
      body: currencies.when(
        loading: () => AlayaListSkeleton(label: strings.currenciesLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(currenciesSettingsProvider),
        ),
        // No empty state, and that is not an omission: `currencies` is seeded by Phase 1C and nothing in the
        // app can delete a row from it, so an empty list is unreachable rather than merely unlikely.
        data: (rows) => ListView.builder(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          itemCount: rows.length,
          itemBuilder: (context, index) => _CurrencyRow(
            currency: rows[index],
            isHome: rows[index].code == home,
          ),
        ),
      ),
    );
  }
}

class _CurrencyRow extends ConsumerWidget {
  const _CurrencyRow({required this.currency, required this.isHome});

  final Currency currency;
  final bool isHome;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SwitchListTile(
      value: currency.isEnabled || isHome,
      // Disabled rather than hidden: a switch that is missing looks like a rendering fault, while one that is
      // present and inert with a reason beside it is an explanation (ARCH_5 §10).
      onChanged: isHome
          ? null
          : (value) => _toggle(context, ref, strings, value: value),
      // **No chip, and no leading icon.** A `SwitchListTile` reserves room for the switch, so `secondary`
      // plus a chip left the title 172dp — enough to overflow by 2.8px at scale 1 and far worse at two.
      // Both were redundant anyway: every row here is a currency, so an icon says nothing, and the
      // subtitle states in words what the chip said as a badge (Law U17 — words, never only a badge).
      title: Text(
        strings.currenciesRowTitle(currency.code, currency.name),
        style: AlayaTypography.cardTitle,
      ),
      subtitle: Text(
        isHome
            ? strings.currenciesHomeLocked
            : strings.currenciesRowSubtitle(
                currency.symbol,
                currency.decimalDigits,
              ),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool value,
  }) async {
    final ok = await ref
        .read(currencyToggleProvider.notifier)
        .setEnabled(code: currency.code, isEnabled: value);
    if (!context.mounted || ok) return;
    showFailureSnack(context, message: strings.currenciesToggleFailed);
  }
}
```

### `lib/features/settings/presentation/screens/data_settings_screen.dart`

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
import 'package:alaya/features/settings/providers/app_settings_providers.dart';

/// Settings › Data (ARCH_5 §3 archetype D, outside the shell).
///
/// **A hub, not a workspace, since 8B.** It previously held the export flow inline and a *"coming in the next
/// update"* row where restore belonged. Both are real screens now, so this branch does what a settings branch
/// should: name what is behind it and get out of the way. Keeping a second export here would have meant two
/// places carrying ARCH_3 §3.4's warning, and two places to forget it.
class DataSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const DataSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final trashed = ref.watch(settingsTrashCountProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsData)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          ListTile(
            leading: Icon(
              Icons.backup_outlined,
              size: AlayaIconSize.lg,
              color: semantic.muted,
            ),
            title: Text(strings.backupTitle, style: AlayaTypography.cardTitle),
            subtitle: Text(
              strings.dataBackupRowBody,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
            onTap: () => context.push(Routes.settingsBackup),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              size: AlayaIconSize.lg,
              color: semantic.muted,
            ),
            title: Text(strings.trashTitle, style: AlayaTypography.cardTitle),
            // Null while the count loads, so the row shows its title alone rather than "0 items" — a zero that
            // really means "not yet known" is the figure Law U4 exists to prevent.
            subtitle: Text(
              trashed == null
                  ? strings.dataTrashRowBody
                  : strings.settingsTrashCount(trashed),
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
            trailing: Icon(
              Icons.chevron_right,
              size: AlayaIconSize.md,
              color: semantic.muted,
            ),
            onTap: () => context.push(Routes.settingsTrash),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/settings/presentation/screens/payees_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/sheets/payee_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

/// Settings › Payees (ARCH_5 §3 archetype D, outside the shell).
///
/// **The only settings branch with a search field, because it is the only one that grows without
/// bound.** Every other list here is fixed by the app's shape — five account kinds, six payment
/// methods, three unit categories — while payees accumulate one per shop the user ever names. A
/// hundred rows is normal, and scanning fails.
///
/// **This screen does not filter placeholders, and it used to.** `payeesSettingsProvider` excludes
/// [PayeeKind.splitPlaceholder] now, which is where the decision belongs: filtering here left every
/// other consumer of that provider counting rows this list refused to show, so a payee count and a
/// payee list disagreed by the number of unnamed split participants. One filter, one layer, and no
/// second reader to keep in step.
class PayeesSettingsScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const PayeesSettingsScreen({super.key});

  @override
  ConsumerState<PayeesSettingsScreen> createState() =>
      _PayeesSettingsScreenState();
}

class _PayeesSettingsScreenState extends ConsumerState<PayeesSettingsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final payees = ref.watch(payeesSettingsProvider);
    final query = _query.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPayees)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => PayeeSheet.show(context, existing: null),
        tooltip: strings.payeesAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AlayaSpacing.screenEdge,
              AlayaSpacing.sm,
              AlayaSpacing.screenEdge,
              AlayaSpacing.xs,
            ),
            child: AlayaSearchField(
              hintText: strings.payeesSearchHint,
              clearLabel: strings.actionClear,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: payees.when(
              loading: () => AlayaListSkeleton(label: strings.payeesLoading),
              error: (error, stack) => ErrorState(
                title: strings.errorTitleGeneric,
                body: error.toString(),
                retryLabel: strings.actionRetry,
                onRetry: () => ref.invalidate(payeesSettingsProvider),
              ),
              data: (rows) {
                final matching = query.isEmpty
                    ? rows
                    // Matched on `normalizedName`, so "cafe" finds "Café" — the same normaliser the
                    // repository used when it stored the row, rather than a second rule that would
                    // disagree with it.
                    : [
                        for (final row in rows)
                          if (row.normalizedName.contains(query)) row,
                      ];

                if (rows.isEmpty) {
                  return EmptyState(
                    title: strings.payeesEmptyTitle,
                    body: strings.payeesEmptyBody,
                    icon: Icons.storefront_outlined,
                    actionLabel: strings.payeesAdd,
                    onAction: () => PayeeSheet.show(context, existing: null),
                  );
                }
                // Two distinct empties: nothing at all, and nothing matching. The second names the
                // search, because "no payees" in front of a list the user can see is a lie.
                if (matching.isEmpty) {
                  return EmptyState(
                    title: strings.payeesNoMatchTitle,
                    body: strings.payeesNoMatchBody,
                    icon: Icons.search_off_outlined,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: matching.length,
                  itemBuilder: (context, index) =>
                      _PayeeRow(payee: matching[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PayeeRow extends ConsumerWidget {
  const _PayeeRow({required this.payee});

  final Payee payee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final detail = [
      payeeKindLabel(strings, payee.kind),
      if (payee.phone != null && payee.phone!.isNotEmpty) payee.phone!,
    ].join(' · ');

    return ListTile(
      leading: Icon(
        // A person and a shop are different things and the list said so with one icon for both. The
        // kind is already in the subtitle; the glyph now agrees with it rather than contradicting it.
        payee.kind == PayeeKind.person
            ? Icons.person_outline
            : Icons.storefront_outlined,
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(payee.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        detail,
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: IconButton(
        onPressed: () => _delete(context, ref, strings),
        tooltip: strings.payeesDelete,
        icon: Icon(
          Icons.delete_outline,
          size: AlayaIconSize.md,
          color: semantic.danger,
        ),
      ),
      onTap: () => PayeeSheet.show(context, existing: payee),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.payeesDeleteConfirmTitle,
      body: strings.payeesDeleteConfirmBody,
      confirmLabel: strings.payeesDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(payeeEditorProvider.notifier).delete(payee.id);
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.payeesDeleted)
        : showFailureSnack(context, message: strings.payeesDeleteFailed);
  }
}

/// The name of each payee kind.
///
/// **Exhaustive, and it refused to compile the moment `PayeeKind` gained a sixth member.** That is Law
/// L13 working: an added member cannot fall through to a wrong label, because every switch like this
/// one fails loudly until somebody decides what the new case means.
///
/// [PayeeKind.splitPlaceholder] never reaches this screen — `payeesSettingsProvider` filters those rows
/// out — but this function is public and the compiler is right to insist. A placeholder that reaches
/// some other caller should say what it is rather than borrow "Other".
String payeeKindLabel(AlayaStrings strings, PayeeKind kind) => switch (kind) {
  PayeeKind.person => strings.payeeKindPerson,
  PayeeKind.merchant => strings.payeeKindMerchant,
  PayeeKind.employer => strings.payeeKindEmployer,
  PayeeKind.utility => strings.payeeKindUtility,
  PayeeKind.other => strings.payeeKindOther,
  PayeeKind.splitPlaceholder => strings.payeeKindSplitPlaceholder,
};
```

### `lib/features/settings/presentation/screens/payment_methods_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/sheets/payment_method_sheet.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Payment methods (ARCH_5 §3 archetype D, outside the shell).
///
/// **Edited in a sheet, not a route.** A payment method is a name and a kind — two fields — and archetype A
/// exists for exactly that: one required field, the keyboard already up, commit as soon as it parses. A
/// full-screen editor for two fields would cost a navigation each way for less work than the transition.
class PaymentMethodsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const PaymentMethodsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final methods = ref.watch(paymentMethodsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsPaymentMethods)),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            PaymentMethodSheet.show(context, existing: null, nextSortOrder: 0),
        tooltip: strings.paymentMethodsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: methods.when(
        loading: () => AlayaListSkeleton(label: strings.paymentMethodsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(paymentMethodsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.paymentMethodsEmptyTitle,
              body: strings.paymentMethodsEmptyBody,
              icon: Icons.credit_card_outlined,
              actionLabel: strings.paymentMethodsAdd,
              onAction: () => PaymentMethodSheet.show(
                context,
                existing: null,
                nextSortOrder: 0,
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: rows.length,
            itemBuilder: (context, index) => _MethodRow(
              method: rows[index],
              nextSortOrder: rows.length,
            ),
          );
        },
      ),
    );
  }
}

class _MethodRow extends ConsumerWidget {
  const _MethodRow({required this.method, required this.nextSortOrder});

  final PaymentMethod method;
  final int nextSortOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      leading: Icon(
        _icon(method.kind),
        size: AlayaIconSize.lg,
        color: semantic.muted,
      ),
      title: Text(method.name, style: AlayaTypography.cardTitle),
      subtitle: Text(
        paymentMethodKindLabel(strings, method.kind),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      trailing: method.isSystem
          // A system method is renameable but not removable, and the chip says so before the user goes looking
          // for a delete that is not there.
          ? StatusChip(
              label: strings.paymentMethodsSystemChip,
              tone: StatusTone.neutral,
            )
          : IconButton(
              onPressed: () => _delete(context, ref, strings),
              tooltip: strings.paymentMethodsDelete,
              icon: Icon(
                Icons.delete_outline,
                size: AlayaIconSize.md,
                color: semantic.danger,
              ),
            ),
      onTap: () => PaymentMethodSheet.show(
        context,
        existing: method,
        nextSortOrder: nextSortOrder,
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.paymentMethodsDeleteConfirmTitle,
      // Says what survives: a transaction that used this method keeps its record of having done so.
      body: strings.paymentMethodsDeleteConfirmBody,
      confirmLabel: strings.paymentMethodsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final ok = await ref
        .read(paymentMethodEditorProvider.notifier)
        .delete(method.id);
    if (!context.mounted) return;
    if (ok) {
      showResultSnack(context, message: strings.paymentMethodsDeleted);
    } else {
      showFailureSnack(context, message: strings.paymentMethodsDeleteFailed);
    }
  }

  IconData _icon(PaymentMethodKind kind) => switch (kind) {
    PaymentMethodKind.cash => Icons.payments_outlined,
    PaymentMethodKind.upi => Icons.qr_code_2_outlined,
    PaymentMethodKind.bankTransfer => Icons.account_balance_outlined,
    PaymentMethodKind.card => Icons.credit_card_outlined,
    PaymentMethodKind.cheque => Icons.receipt_long_outlined,
    PaymentMethodKind.wallet => Icons.account_balance_wallet_outlined,
    PaymentMethodKind.other => Icons.more_horiz,
  };
}

/// The name of each payment-method kind.
///
/// Exhaustive without a `default`, so a seventh kind fails to compile here rather than rendering blank.
String paymentMethodKindLabel(AlayaStrings strings, PaymentMethodKind kind) =>
    switch (kind) {
      PaymentMethodKind.cash => strings.paymentKindCash,
      PaymentMethodKind.upi => strings.paymentKindUpi,
      PaymentMethodKind.bankTransfer => strings.paymentKindBankTransfer,
      PaymentMethodKind.card => strings.paymentKindCard,
      PaymentMethodKind.cheque => strings.paymentKindCheque,
      PaymentMethodKind.wallet => strings.paymentKindWallet,
      PaymentMethodKind.other => strings.paymentKindOther,
    };
```

### `lib/features/settings/presentation/screens/security_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/features/lock/providers/lock_providers.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Settings › Security (ARCH_5 §3 archetype D, outside the shell).
///
/// **The honest paragraph is at the top, not the bottom.** ARCH_3 §2.5: this PIN stops someone who picks up the
/// unlocked phone, and it does not encrypt anything. Somebody deciding whether to turn a lock on should read that
/// before the switch, not after — and there is no padlock glyph on this screen for the same reason there is none
/// on the lock screen.
///
/// **Auto-erase is off unless the user turns it on, and turning it on costs a confirmation that says what it
/// does** (ARCH_3 §2.3). Ten wrong attempts from a child mashing digits would otherwise destroy a household's
/// entire financial history, which is not a default anybody would choose knowingly.
class SecuritySettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final configured = ref.watch(lockConfiguredProvider).valueOrNull;
    final autoErase = ref.watch(autoEraseEnabledProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsSecurity)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
        children: [
          Padding(
            padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
            child: Container(
              padding: const EdgeInsets.all(AlayaSpacing.md),
              decoration: BoxDecoration(
                // `muted`, not `info`: AlayaSemanticColors declares income, expense, transfer, warning,
                // danger, success and muted — there is no `info` tone, and this panel is explanatory
                // rather than a state (ARCH_5 §2.4).
                color: semantic.muted.withValues(alpha: 0.12),
                borderRadius: AlayaRadii.borderMd,
              ),
              child: Text(strings.lockHonestBody, style: AlayaTypography.body),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AlayaSpacing.screenEdge,
            ),
            child: SectionHeader(label: strings.securityPinHeader),
          ),
          // Null while secure storage answers, so neither branch is guessed. A row that said "no PIN set" for one
          // frame to somebody who has one would be alarming for exactly the wrong reason.
          if (configured == null)
            ListTile(
              title: Text(
                strings.securityChecking,
                style: AlayaTypography.body.copyWith(color: semantic.muted),
              ),
            )
          else if (!configured)
            ListTile(
              leading: Icon(
                Icons.pin_outlined,
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              title: Text(
                strings.securitySetPin,
                style: AlayaTypography.cardTitle,
              ),
              subtitle: Text(
                strings.securitySetPinHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              onTap: () => context.push(Routes.settingsPin),
            )
          else ...[
            ListTile(
              leading: Icon(
                Icons.pin_outlined,
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              title: Text(
                strings.securityChangePin,
                style: AlayaTypography.cardTitle,
              ),
              trailing: Icon(
                Icons.chevron_right,
                size: AlayaIconSize.md,
                color: semantic.muted,
              ),
              onTap: () => context.push(Routes.settingsPin),
            ),
            ListTile(
              leading: Icon(
                Icons.lock_open_outlined,
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              title: Text(
                strings.securityRemovePin,
                style: AlayaTypography.cardTitle,
              ),
              subtitle: Text(
                strings.securityRemovePinHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              onTap: () => _removePin(context, ref, strings),
            ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.securityAutoLockHeader),
            ),
            ListTile(
              leading: Icon(
                Icons.timer_outlined,
                size: AlayaIconSize.lg,
                color: semantic.muted,
              ),
              title: Text(
                strings.securityAutoLockTitle,
                style: AlayaTypography.cardTitle,
              ),
              // Stated rather than configurable in this phase: `autoLockDelay` is a constant, and offering a
              // picker that wrote a setting nothing reads would be the dead control §10 objects to. The key is
              // reserved (`autoLockDelaySettingKey`) so 8B can make it real without a migration.
              subtitle: Text(
                strings.securityAutoLockBody(autoLockDelay.inSeconds),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
            const SizedBox(height: AlayaSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.securityAutoEraseHeader),
            ),
            SwitchListTile(
              value: autoErase,
              onChanged: (value) =>
                  _setAutoErase(context, ref, strings, value: value),
              title: Text(
                strings.securityAutoEraseTitle,
                style: AlayaTypography.body,
              ),
              subtitle: Text(
                strings.securityAutoEraseBody(autoEraseFailureThreshold),
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
              secondary: Icon(
                Icons.delete_forever_outlined,
                size: AlayaIconSize.lg,
                // The one place on this screen `danger` is used, because it is the one setting that destroys
                // data (ARCH_5 §2.4 — a state colour, never emphasis).
                color: autoErase ? semantic.danger : semantic.muted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _removePin(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) async {
    // Removing a lock needs the PIN, which `PinService.disable` enforces — so this sends the user to the flow
    // that can ask for it rather than collecting a PIN on a settings row.
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.securityRemovePinConfirmTitle,
      body: strings.securityRemovePinConfirmBody,
      confirmLabel: strings.actionContinue,
      cancelLabel: strings.actionCancel,
    );
    if (!confirmed || !context.mounted) return;
    await context.push(Routes.settingsPin);
    if (!context.mounted) return;
    // Re-read on return: the flow may have removed the lock, and this screen's rows are the only thing that
    // would still claim otherwise.
    ref.invalidate(lockConfiguredProvider);
    await ref.read(lockPhaseProvider.notifier).refresh();
  }

  Future<void> _setAutoErase(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings, {
    required bool value,
  }) async {
    if (value) {
      // **The scary confirm, and it names the number.** "After 10 failed attempts everything on this device is
      // deleted" is the sentence somebody needs to have read; a generic "are you sure?" would not earn consent
      // to a setting that destroys a household's records.
      final confirmed = await ConfirmSheet.show(
        context,
        title: strings.securityAutoEraseConfirmTitle,
        body: strings.securityAutoEraseConfirmBody(autoEraseFailureThreshold),
        confirmLabel: strings.securityAutoEraseConfirmAction,
        cancelLabel: strings.actionCancel,
        destructive: true,
      );
      if (!confirmed || !context.mounted) return;
    }
    final result = await ref
        .read(settingsRepositoryProvider)
        .writeValue(
          key: autoEraseSettingKey,
          value: value ? 'true' : 'false',
          valueType: 'string',
        );
    if (!context.mounted) return;
    if (result.isFailure) {
      showFailureSnack(context, message: strings.securityAutoEraseFailed);
      return;
    }
    ref.invalidate(autoEraseEnabledProvider);
    showResultSnack(
      context,
      message: value
          ? strings.securityAutoEraseOn
          : strings.securityAutoEraseOff,
    );
  }
}
```

### `lib/features/settings/presentation/screens/settings_screen.dart`

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
import 'package:alaya/features/settings/providers/settings_providers.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/shared/widgets/alaya_search_field.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// One row of the settings tree.
class _Entry {
  const _Entry({
    required this.title,
    required this.icon,
    required this.route,
    required this.keywords,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String route;

  /// Extra words this row should match on.
  ///
  /// **Because the title is not what people search for.** Somebody looking for dark mode types "dark", not
  /// "Appearance"; somebody looking to change their PIN types "PIN", not "Security". A tree whose search
  /// only matched headings would be worse than no search at all, because it would answer "no results" to a
  /// setting that is right there.
  final List<String> keywords;
}

/// The settings tree (ARCH_5 §3 archetype D).
///
/// **Archetype D with two deviations.** There is no FAB, because nothing is added at the tree level — every
/// branch owns its own add action. And the grouping is by subject rather than by a user-chosen axis, because
/// a settings tree has no axis the user controls; the three groups are what the app is made of, in the order
/// somebody looks for them.
///
/// **The search field is pinned and real**, per D — catalogues are searched constantly, and a ten-branch
/// tree with sub-settings is exactly the case where scanning fails. It matches keywords as well as titles,
/// so "dark" finds Appearance and "PIN" finds Security.
///
/// Each row carries a live count, which is D's "the one number that matters": a branch that says *18 tags*
/// tells the user whether it is worth opening before they open it.
class SettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final query = ref.watch(settingsQueryProvider).trim().toLowerCase();
    final groups = _groups(context, ref, strings);

    final filtered = query.isEmpty
        ? groups
        : [
            for (final group in groups)
              (
                label: group.label,
                entries: [
                  for (final entry in group.entries)
                    if (entry.title.toLowerCase().contains(query) ||
                        entry.keywords.any((word) => word.contains(query)))
                      entry,
                ],
              ),
          ].where((group) => group.entries.isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AlayaSpacing.screenEdge,
            AlayaSpacing.sm,
            AlayaSpacing.screenEdge,
            AlayaSpacing.xs,
          ),
          child: AlayaSearchField(
            hintText: strings.settingsSearchHint,
            clearLabel: strings.actionClear,
            onChanged: ref.read(settingsQueryProvider.notifier).set,
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              // Empty is reachable only through search, so it names the search rather than the tree — "no
              // settings" would be false, and the user can see it is.
              ? EmptyState(
                  title: strings.settingsNoMatchTitle,
                  body: strings.settingsNoMatchBody,
                  icon: Icons.search_off_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final group = filtered[index];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AlayaSpacing.lg,
                            bottom: AlayaSpacing.xs,
                          ),
                          child: SectionHeader(label: group.label),
                        ),
                        for (final entry in group.entries)
                          _EntryTile(entry: entry),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<({String label, List<_Entry> entries})> _groups(
    BuildContext context,
    WidgetRef ref,
    AlayaStrings strings,
  ) {
    final accounts = ref.watch(settingsAccountCountProvider).valueOrNull;
    final methods = ref.watch(settingsPaymentMethodCountProvider).valueOrNull;
    final payees = ref.watch(settingsPayeeCountProvider).valueOrNull;
    final tags = ref.watch(settingsTagCountProvider).valueOrNull;
    final units = ref.watch(settingsUnitCountProvider).valueOrNull;
    final currencies = ref.watch(settingsCurrencyCountProvider).valueOrNull;
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return [
      (
        label: strings.settingsGroupMoney,
        entries: [
          _Entry(
            title: strings.settingsAccounts,
            // Null while the count is loading, so the row shows its title alone rather than "0 accounts"
            // — a zero that is really "not yet known" is the kind of figure Law U4 exists to prevent.
            subtitle: accounts == null
                ? null
                : strings.settingsAccountCount(accounts),
            icon: Icons.account_balance_wallet_outlined,
            route: Routes.settingsAccounts,
            keywords: const [
              'account',
              'balance',
              'bank',
              'cash',
              'wallet',
              'net worth',
            ],
          ),
          _Entry(
            title: strings.settingsPaymentMethods,
            subtitle: methods == null
                ? null
                : strings.settingsPaymentMethodCount(methods),
            icon: Icons.credit_card_outlined,
            route: Routes.settingsPaymentMethods,
            keywords: const ['payment', 'card', 'upi', 'method'],
          ),
          _Entry(
            title: strings.settingsPayees,
            subtitle: payees == null
                ? null
                : strings.settingsPayeeCount(payees),
            icon: Icons.storefront_outlined,
            route: Routes.settingsPayees,
            keywords: const ['payee', 'shop', 'merchant', 'who'],
          ),
          _Entry(
            title: strings.settingsSplit,
            // **Not a count, and the only row here that is not.** Every other subtitle says how much is
            // in a branch; this one says whether the module works at all. Until `split.selfPayeeId` is
            // set, nothing can tell which side of a debt the user is on — so three screens send people
            // here, and "Not set up yet" is how they recognise the row when they arrive.
            subtitle: self == null
                ? strings.settingsSplitUnset
                : strings.settingsSplitSet,
            icon: Icons.call_split_outlined,
            // The keywords matter more than usual: somebody sent here by a message about splitting a
            // bill will type "split" or "who am i", neither of which appears in the title.
            keywords: const ['split', 'share', 'owe', 'upi', 'me', 'who am i'],
            route: Routes.settingsSplit,
          ),
        ],
      ),
      (
        label: strings.settingsGroupThings,
        entries: [
          _Entry(
            title: strings.settingsTags,
            subtitle: tags == null ? null : strings.settingsTagCount(tags),
            icon: Icons.sell_outlined,
            route: Routes.settingsTags,
            keywords: const ['tag', 'label', 'category', 'kitchen'],
          ),
          _Entry(
            title: strings.settingsUnits,
            subtitle: units == null ? null : strings.settingsUnitCount(units),
            icon: Icons.straighten_outlined,
            route: Routes.settingsUnits,
            keywords: const ['unit', 'kg', 'litre', 'measure', 'weight'],
          ),
          _Entry(
            title: strings.settingsCurrencies,
            subtitle: currencies == null
                ? null
                : strings.settingsCurrencyCount(
                    currencies.enabled,
                    currencies.total,
                  ),
            icon: Icons.currency_exchange_outlined,
            route: Routes.settingsCurrencies,
            keywords: const ['currency', 'rate', 'exchange', 'home currency'],
          ),
        ],
      ),
      (
        label: strings.settingsGroupApp,
        entries: [
          _Entry(
            title: strings.settingsAppearance,
            icon: Icons.palette_outlined,
            route: Routes.settingsAppearance,
            keywords: const [
              'appearance',
              'theme',
              'dark',
              'light',
              'palette',
              'colour',
              'color',
            ],
          ),
          _Entry(
            title: strings.settingsSecurity,
            icon: Icons.shield_outlined,
            route: Routes.settingsSecurity,
            keywords: const [
              'security',
              'pin',
              'lock',
              'fingerprint',
              'biometric',
              'erase',
            ],
          ),
          // Phase 8B. Reminders sits beside Security because both are about what the app does when it is not
          // open, and somebody looking for one often means the other.
          _Entry(
            title: strings.remindersTitle,
            subtitle: strings.settingsRemindersHelp,
            icon: Icons.notifications_none_outlined,
            route: Routes.settingsReminders,
            keywords: const [
              'reminder',
              'notification',
              'notify',
              'alert',
              'digest',
              'expiry',
              'due',
              'daily',
            ],
          ),
          _Entry(
            title: strings.settingsData,
            icon: Icons.folder_outlined,
            route: Routes.settingsData,
            keywords: const ['data', 'backup', 'export', 'restore', 'trash'],
          ),
          // **Reachable from Settings and nowhere else.** Ads load when that screen opens, so a shell
          // destination or a dashboard tile would start an SDK for people who never asked (ARCH_4 §5.1).
          _Entry(
            title: strings.supportTitle,
            subtitle: strings.settingsSupportHelp,
            icon: Icons.favorite_outline,
            route: Routes.support,
            keywords: const [
              'support',
              'tip',
              'donate',
              'advert',
              'ad',
              'help',
              'contribute',
            ],
          ),
          _Entry(
            title: strings.settingsAbout,
            icon: Icons.info_outlined,
            route: Routes.settingsAbout,
            keywords: const [
              'about',
              'version',
              'licence',
              'license',
              'open source',
            ],
          ),
        ],
      ),
    ];
  }
}

/// One tappable branch.
class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return ListTile(
      leading: Icon(entry.icon, size: AlayaIconSize.lg, color: semantic.muted),
      title: Text(entry.title, style: AlayaTypography.cardTitle),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              entry.subtitle!,
              style: AlayaTypography.caption.copyWith(color: semantic.muted),
            ),
      trailing: Icon(
        Icons.chevron_right,
        size: AlayaIconSize.md,
        color: semantic.muted,
      ),
      onTap: () => context.push(entry.route),
    );
  }
}
```

### `lib/features/settings/presentation/screens/split_settings_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/providers/split_settings_providers.dart';
import 'package:alaya/features/split/presentation/sheets/add_person_sheet.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Who you are, and how people can pay you (ARCH_5 §3 archetype D leaf).
///
/// **This screen is on its way out.** Onboarding will ask for the name once, at which point nothing
/// arrives here for the first time and the branch becomes what it should always have been: somewhere to
/// *change* a decision, not to make one. Until that lands it is still the only place the payment details
/// can be set.
///
/// **The link to Groups is gone.** Groups are a tab on `/split` now, and a settings branch offering a
/// shortcut into a tab of another destination is the kind of cross-link that made this module feel like a
/// maze — seven routes where two would do.
class SplitSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const SplitSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final people = ref.watch(splitPeopleProvider);
    final self = ref.watch(splitSelfProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsSplit)),
      body: people.when(
        loading: () => AlayaListSkeleton(label: strings.loadingLabel),
        error: (error, stack) => EmptyState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          icon: Icons.error_outline,
        ),
        data: (all) => ListView(
          padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: SectionHeader(label: strings.splitSettingsWhoAreYou),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                0,
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
              ),
              child: Text(
                strings.splitSettingsWhoAreYouHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),

            if (all.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Text(
                  strings.splitSettingsNoPeople,
                  style: AlayaTypography.body.copyWith(color: semantic.muted),
                ),
              )
            else
              for (final payee in all)
                RadioListTile<String>(
                  value: payee.id,
                  groupValue: self,
                  title: Text(payee.name),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AlayaSpacing.screenEdge,
                  ),
                  onChanged: (id) => _claim(context, ref, id, payee),
                ),

            // **`AddPersonSheet`, not `PayeeSheet`.** The shared sheet defaults a new payee to
            // `PayeeKind.merchant`, and `splitPeopleProvider` filters to persons — so anybody added from
            // here used to vanish from the very list that sent them to add somebody.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => AddPersonSheet.show(context),
                  icon: const Icon(
                    Icons.person_add_outlined,
                    size: AlayaIconSize.md,
                  ),
                  label: Text(strings.splitAddPerson),
                ),
              ),
            ),

            SectionHeader(
              label: strings.splitSettingsPayMe,
              padding: const EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.xl,
                AlayaSpacing.screenEdge,
                AlayaSpacing.xxs,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AlayaSpacing.screenEdge,
              ),
              child: Text(
                // What it buys, not what it is. Optional, and the summary works without one.
                strings.splitSettingsPayMeHelp,
                style: AlayaTypography.caption.copyWith(color: semantic.muted),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AlayaSpacing.screenEdge,
                AlayaSpacing.sm,
                AlayaSpacing.screenEdge,
                0,
              ),
              child: _PaymentHandleField(),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _claim(
    BuildContext context,
    WidgetRef ref,
    String? id,
    Payee payee,
  ) async {
    if (id == null) return;
    final strings = AlayaStrings.of(context);
    final ok = await ref.read(splitSettingsProvider.notifier).setSelf(id);
    if (!context.mounted) return;
    showResultSnack(
      context,
      message: ok
          ? strings.splitSettingsClaimed(payee.name)
          : strings.errorBodyGeneric,
    );
  }
}

/// Where people can send money, in whatever form the user's country uses.
///
/// Its own widget so the controller has somewhere to live and be disposed — a `TextEditingController`
/// created inside a `build` leaks one per rebuild, and a settings screen rebuilds on every provider it
/// watches.
class _PaymentHandleField extends ConsumerStatefulWidget {
  const _PaymentHandleField();

  @override
  ConsumerState<_PaymentHandleField> createState() =>
      _PaymentHandleFieldState();
}

class _PaymentHandleFieldState extends ConsumerState<_PaymentHandleField> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final saved = ref.watch(splitPaymentHandleProvider).valueOrNull;

    // Adopted once. The provider re-emits after every write, and without this guard a save would reset
    // the cursor to the start of the field mid-typing — the same `_loaded` guard `TagEditorScreen` uses
    // and for the same reason.
    if (!_loaded && saved != null) {
      _loaded = true;
      _controller.text = saved;
    }

    return TextField(
      controller: _controller,
      // **No keyboard hint, no autocorrect, no validation.** The field used to be a UPI id with an email
      // keyboard, which quietly assumed India. It now holds a PayPal link, an IBAN, a Venmo handle or a
      // sentence, and any assumption about its shape would be wrong somewhere.
      autocorrect: false,
      maxLines: 2,
      minLines: 1,
      decoration: InputDecoration(
        labelText: strings.splitSettingsPayMeLabel,
        hintText: strings.splitSettingsPayMeHint,
        suffixIcon: IconButton(
          onPressed: () => _save(strings),
          tooltip: strings.actionSave,
          icon: const Icon(Icons.check, size: AlayaIconSize.md),
        ),
      ),
      onSubmitted: (_) => _save(strings),
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final ok = await ref
        .read(splitSettingsProvider.notifier)
        .setPaymentHandle(_controller.text);
    if (!mounted) return;
    showResultSnack(
      context,
      message: ok ? strings.actionSaved : strings.errorBodyGeneric,
    );
  }
}
```

### `lib/features/settings/presentation/screens/tag_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one tag (ARCH_5 §3 archetype B).
///
/// **This is where `tags.allowedIn*` and `tags.parentTagId` are actually set**, and the two §7.2 rows they
/// represent close here. The matrix is six switches with a line each saying what unticking one would do, because
/// "Withdrawal" on its own tells the reader nothing about *why* a tag would vanish from the screen they use most.
///
/// **A tag scoped nowhere is warned about, not forbidden.** ARCH_2 permits an empty scope set and somebody may
/// well want to park a tag they are not using; inventing a constraint the schema does not have would be worse
/// than saying plainly that the tag will not appear anywhere.
class TagEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [tagId] null means a new tag.
  const TagEditorScreen({this.tagId, super.key});

  /// The tag being edited, or null for a new one.
  final String? tagId;

  @override
  ConsumerState<TagEditorScreen> createState() => _TagEditorScreenState();
}

class _TagEditorScreenState extends ConsumerState<TagEditorScreen> {
  final _name = TextEditingController();
  Set<TagScope> _scopes = {};
  String? _parentId;
  int? _colorArgb;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _adopt(Tag? tag) {
    if (_loaded) return;
    _loaded = true;
    if (tag == null) {
      // A new tag starts scoped to the two money pickers rather than to nothing. Somebody adding a tag almost
      // always means to use it on a transaction, and an empty set would make their first act invisible.
      _scopes = {TagScope.deposit, TagScope.withdrawal};
      return;
    }
    _name.text = tag.name;
    _scopes = {...tag.allowedScopes};
    _parentId = tag.parentTagId;
    _colorArgb = tag.colorArgb;
    _sortOrder = tag.sortOrder;
    _isSystem = tag.isSystem;
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(tagDraftProvider(widget.tagId));
    final editing = ref.watch(tagEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagDraftProvider(widget.tagId)),
        ),
      ),
      data: (tag) {
        if (widget.tagId != null && tag == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.tagsMissingTitle,
              body: strings.tagsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(tag);
        final parents = ref.watch(tagParentChoicesProvider(widget.tagId));
        final theme = Theme.of(context);
        final swatches = <int>[
          theme.colorScheme.primary.toARGB32(),
          theme.colorScheme.secondary.toARGB32(),
          theme.colorScheme.tertiary.toARGB32(),
          theme.colorScheme.primaryContainer.toARGB32(),
          theme.colorScheme.secondaryContainer.toARGB32(),
          theme.colorScheme.tertiaryContainer.toARGB32(),
        ];

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.tagEditorSave,
            onPrimary: _name.text.trim().isEmpty || editing.isLoading
                ? null
                : () => _save(tag),
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
                  autofocus: tag == null,
                  decoration: InputDecoration(labelText: strings.tagNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagColourHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                // **The swatches come from the live palette; the stored value is a frozen int.** `colorArgb` is
                // a column, so a tag coloured under one preset keeps that colour if the user later switches
                // palettes. Storing a palette *role* would follow the theme, but the schema stores an int and
                // inventing a second encoding in the UI would put two meanings in one column.
                Text(
                  strings.tagColourHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    _Swatch(
                      color: theme.colorScheme.outlineVariant,
                      selected: _colorArgb == null,
                      semanticLabel: strings.tagColourNone,
                      onTap: () => setState(() {
                        _colorArgb = null;
                        _dirty = true;
                      }),
                    ),
                    for (final argb in swatches)
                      _Swatch(
                        color: Color(argb),
                        selected: _colorArgb == argb,
                        semanticLabel: strings.tagColourSwatch,
                        onTap: () => setState(() {
                          _colorArgb = argb;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagParentHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagParentHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    ChoiceChip(
                      label: Text(
                        strings.tagParentNone,
                        style: AlayaTypography.button,
                      ),
                      selected: _parentId == null,
                      onSelected: (_) => setState(() {
                        _parentId = null;
                        _dirty = true;
                      }),
                    ),
                    // Already filtered to exclude this tag and everything beneath it, so the picker cannot build
                    // a cycle — the constraint lives where the choice is made.
                    for (final parent in parents)
                      ChoiceChip(
                        label: Text(parent.name, style: AlayaTypography.button),
                        selected: parent.id == _parentId,
                        onSelected: (_) => setState(() {
                          _parentId = parent.id;
                          _dirty = true;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.tagScopesHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  strings.tagScopesHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                if (_scopes.isEmpty) ...[
                  const SizedBox(height: AlayaSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AlayaSpacing.md),
                    decoration: BoxDecoration(
                      color: context.semantic.warning.withValues(alpha: 0.12),
                      borderRadius: AlayaRadii.borderMd,
                    ),
                    child: Text(
                      strings.tagsNoScopesWarning,
                      style: AlayaTypography.bodyEmphasis,
                    ),
                  ),
                ],
                const SizedBox(height: AlayaSpacing.xs),
                for (final scope in TagScope.values)
                  SwitchListTile(
                    value: _scopes.contains(scope),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      tagScopeLabel(strings, scope),
                      style: AlayaTypography.body,
                    ),
                    subtitle: Text(
                      tagScopeHelp(strings, scope),
                      style: AlayaTypography.caption.copyWith(
                        color: context.semantic.muted,
                      ),
                    ),
                    onChanged: (on) => setState(() {
                      final next = {..._scopes};
                      if (on) {
                        next.add(scope);
                      } else {
                        next.remove(scope);
                      }
                      _scopes = next;
                      _dirty = true;
                    }),
                  ),
                if (tag != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(tag),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.semantic.danger,
                    ),
                    child: Text(
                      strings.tagsDelete,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.tagsDeleteHelp,
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

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: Text(
        widget.tagId == null
            ? strings.tagEditorTitle
            : strings.tagEditorEditTitle,
      ),
    ),
    body: body,
  );

  Future<void> _save(Tag? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(tagEditorProvider.notifier)
        .save(
          id: existing?.id,
          name: _name.text,
          allowedScopes: _scopes,
          sortOrder: _sortOrder,
          parentTagId: _parentId,
          colorArgb: _colorArgb,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.tagsSaved);
    context.pop();
  }

  Future<void> _delete(Tag tag) async {
    final strings = AlayaStrings.of(context);
    // The body says what survives, because a soft delete is not what "delete" usually promises: the transactions
    // that carried this tag keep their history, and only the tag leaves the pickers (ARCH_3 §4).
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.tagsDeleteConfirmTitle,
      body: strings.tagsDeleteConfirmBody,
      confirmLabel: strings.tagsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(tagEditorProvider.notifier).delete(tag.id);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.tagsDeleted);
    context.pop();
  }
}

/// One colour choice.
class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.semanticLabel,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AlayaSpacing.minTapTarget),
        // A full tap target around a small dot: the swatch reads at 24dp and is touchable at 48 (Law U3).
        child: SizedBox(
          width: AlayaSpacing.minTapTarget,
          height: AlayaSpacing.minTapTarget,
          child: Center(
            child: Container(
              width: AlayaSpacing.xl,
              height: AlayaSpacing.xl,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: theme.colorScheme.onSurface, width: 3)
                    : null,
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: AlayaIconSize.sm,
                      color: theme.colorScheme.surface,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
```

### `lib/features/settings/presentation/screens/tags_settings_screen.dart`

```dart
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
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/widgets/tag_scope_labels.dart';
import 'package:alaya/features/settings/providers/tag_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Tags (ARCH_5 §3 archetype D, outside the shell).
///
/// **The scoping matrix is the point of this screen, not decoration on it.** `tags.allowedIn*` is what stops
/// "Kitchen" appearing in the deposit editor's tag picker — a tag scoped to inventory only has no business being
/// offered when somebody records their salary. Every row therefore states its scopes as chips, because a scope
/// that is only visible after opening the editor is one nobody will notice is wrong.
///
/// **A tag with no scopes at all is called out**, not silently listed. It cannot appear anywhere in the app, so
/// it is invisible everywhere except this screen — exactly the kind of dead row a user would spend time hunting
/// for in the pickers before thinking to come here.
///
/// **One level of nesting, and a child is grouped under its top-most ancestor.** ARCH_2 sets no depth limit, but
/// a deeper tree cannot be shown in a picker without indenting past the width of a phone. Flattening keeps a
/// grandchild reachable rather than lost.
class TagsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const TagsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final tags = ref.watch(tagsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsTags)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.tagNew),
        tooltip: strings.tagsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: tags.when(
        loading: () => AlayaListSkeleton(label: strings.tagsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(tagsSettingsProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.tagsEmptyTitle,
              body: strings.tagsEmptyBody,
              icon: Icons.sell_outlined,
              actionLabel: strings.tagsAdd,
              onAction: () => context.push(Routes.tagNew),
            );
          }
          final tree = ref.watch(tagTreeProvider);
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            itemCount: tree.length,
            itemBuilder: (context, index) {
              final branch = tree[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TagRow(tag: branch.parent),
                  for (final child in branch.children)
                    _TagRow(tag: child, nested: true),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// One tag: its colour, its name, and where it is allowed to appear.
class _TagRow extends StatelessWidget {
  const _TagRow({required this.tag, this.nested = false});

  final Tag tag;
  final bool nested;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final theme = Theme.of(context);
    final scopes = tag.allowedScopes;

    return ListTile(
      contentPadding: EdgeInsets.only(
        // Indented once and no further, which is the visible half of the one-level rule.
        left: AlayaSpacing.screenEdge + (nested ? AlayaSpacing.lg : 0),
        right: AlayaSpacing.screenEdge,
      ),
      leading: Container(
        width: AlayaSpacing.md,
        height: AlayaSpacing.md,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: tag.colorArgb == null
              ? theme.colorScheme.outlineVariant
              : Color(tag.colorArgb!),
        ),
      ),
      title: Row(
        children: [
          Expanded(child: Text(tag.name, style: AlayaTypography.cardTitle)),
          if (tag.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            // A system tag can be re-scoped and recoloured but not deleted, and saying so on the row saves the
            // trip into an editor whose delete button is missing for no stated reason.
            StatusChip(label: strings.tagsSystemChip, tone: StatusTone.neutral),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AlayaSpacing.xxs),
        child: scopes.isEmpty
            ? Text(
                strings.tagsNoScopesWarning,
                style: AlayaTypography.caption.copyWith(
                  color: semantic.warning,
                ),
              )
            : Wrap(
                spacing: AlayaSpacing.xxs,
                runSpacing: AlayaSpacing.xxs,
                children: [
                  for (final scope in TagScope.values)
                    if (scopes.contains(scope))
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AlayaSpacing.xs,
                          vertical: AlayaSpacing.xxs / 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: AlayaRadii.borderSm,
                        ),
                        child: Text(
                          tagScopeLabel(strings, scope),
                          style: AlayaTypography.overline.copyWith(
                            color: semantic.muted,
                          ),
                        ),
                      ),
                ],
              ),
      ),
      onTap: () => context.push(Routes.tagEdit(tag.id)),
    );
  }
}
```

### `lib/features/settings/presentation/screens/unit_editor_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/router/routes.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_form_scaffold.dart';
import 'package:alaya/shared/widgets/confirm_sheet.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';

/// Creating or editing one unit (ARCH_5 §3 archetype B).
///
/// **The escape is the point of this screen as much as the form is.** A unit has to be the same amount every
/// time; a "packet" is not, so it cannot have a factor, so it cannot be a unit. `UnitCategory`'s own doc has
/// said since Phase 1A that *"if an amount can't be expressed in one of these, the correct action is a new
/// Item, never a new category"* — this screen is where that rule finally meets a person, and it is offered
/// beside the factor field rather than thrown back as a validation error after they have tried.
///
/// **The question is asked in base units, never in the stored thousandths.** "How many grams is one
/// kilogram?" — 1,000 — and `UnitEditorNotifier` multiplies once. Asking for 1,000,000 would be asking the
/// user to reproduce the arithmetic ARCH_4 R18 got wrong three times.
class UnitEditorScreen extends ConsumerStatefulWidget {
  /// Creates the editor. [unitCode] null means a new unit.
  const UnitEditorScreen({this.unitCode, super.key});

  /// The unit being edited, or null for a new one.
  final String? unitCode;

  @override
  ConsumerState<UnitEditorScreen> createState() => _UnitEditorScreenState();
}

class _UnitEditorScreenState extends ConsumerState<UnitEditorScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _amount = TextEditingController();
  UnitCategory _category = UnitCategory.weight;
  int _sortOrder = 0;
  bool _isSystem = false;
  bool _dirty = false;
  bool _loaded = false;

  /// Whether the user has said the amount varies.
  ///
  /// Local rather than in the notifier: it is a state of the conversation, not of the unit — nothing about it
  /// is ever saved, and a provider holding it would survive a route the user has left.
  bool _varies = false;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _adopt(Unit? unit) {
    if (_loaded) return;
    _loaded = true;
    if (unit == null) return;
    _code.text = unit.code;
    _name.text = unit.displayName;
    _category = unit.category;
    _amount.text = unitBaseAmountLabel(unit).replaceAll(',', '');
    _sortOrder = unit.sortOrder;
    _isSystem = unit.isSystem;
  }

  double? get _baseAmount => double.tryParse(_amount.text.trim());

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final draft = ref.watch(unitDraftProvider(widget.unitCode));
    final editing = ref.watch(unitEditorProvider);

    return draft.when(
      loading: () => _shell(strings, const SizedBox.shrink()),
      error: (error, stack) => _shell(
        strings,
        ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitDraftProvider(widget.unitCode)),
        ),
      ),
      data: (unit) {
        if (widget.unitCode != null && unit == null) {
          return _shell(
            strings,
            ErrorState(
              title: strings.unitsMissingTitle,
              body: strings.unitsMissingBody,
              retryLabel: strings.actionBack,
              onRetry: () => context.pop(),
            ),
          );
        }
        _adopt(unit);

        // The escape replaces the form entirely. Leaving the fields visible underneath would invite somebody
        // to type a number they have just been told does not exist.
        if (_varies)
          return _shell(
            strings,
            _VariesPanel(onBack: () => setState(() => _varies = false)),
          );

        final amount = _baseAmount;
        final canSave =
            _code.text.trim().isNotEmpty &&
            _name.text.trim().isNotEmpty &&
            amount != null &&
            amount > 0;

        return _shell(
          strings,
          AlayaFormScaffold(
            primaryLabel: strings.unitEditorSave,
            onPrimary: canSave && !editing.isLoading ? () => _save(unit) : null,
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
                  autofocus: unit == null,
                  decoration: InputDecoration(labelText: strings.unitNameLabel),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.md),
                TextField(
                  controller: _code,
                  // The code is a primary key (ARCH_2 §2), so it is fixed once anything references it.
                  enabled: unit == null,
                  decoration: InputDecoration(
                    labelText: strings.unitCodeLabel,
                    helperText: unit == null
                        ? strings.unitCodeHelp
                        : strings.unitCodeLockedHelp,
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitCategoryHeader),
                const SizedBox(height: AlayaSpacing.xxs),
                Text(
                  unit == null
                      ? strings.unitCategoryNewHelp
                      : strings.unitCategoryLockedHelp,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Wrap(
                  spacing: AlayaSpacing.xs,
                  runSpacing: AlayaSpacing.xs,
                  children: [
                    for (final category in UnitCategory.values)
                      ChoiceChip(
                        label: Text(
                          unitCategoryLabel(strings, category),
                          style: AlayaTypography.button,
                        ),
                        selected: category == _category,
                        // Changing a unit's category after quantities exist would reinterpret every one of
                        // them, so it is offered only while the unit is new — the same rule as an account's
                        // currency, for the same reason.
                        onSelected: unit == null
                            ? (_) => setState(() {
                                _category = category;
                                _dirty = true;
                              })
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AlayaSpacing.lg),
                SectionHeader(label: strings.unitFactorHeader),
                const SizedBox(height: AlayaSpacing.xs),
                TextField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    // Three decimals, which is exactly what the milli-precision column can hold. Allowing a
                    // fourth would silently round it away at save.
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,3}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: strings.unitFactorQuestion(
                      unitBaseUnitName(strings, _category),
                      _name.text.trim().isEmpty
                          ? strings.unitFactorThisUnit
                          : _name.text.trim(),
                    ),
                    helperText: strings.unitFactorHelp(
                      unitBaseUnitName(strings, _category),
                    ),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
                const SizedBox(height: AlayaSpacing.xs),
                // Offered, not withheld until failure. This is the path for a "packet" or a "bunch", and a
                // user who has that in mind should meet it before typing a number they will have to defend.
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() => _varies = true),
                    icon: const Icon(
                      Icons.help_outline,
                      size: AlayaIconSize.md,
                    ),
                    label: Text(
                      strings.unitFactorVaries,
                      style: AlayaTypography.button,
                    ),
                  ),
                ),
                if (unit != null && !_isSystem) ...[
                  const SizedBox(height: AlayaSpacing.xl),
                  OutlinedButton(
                    onPressed: editing.isLoading ? null : () => _delete(unit),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.semantic.danger,
                    ),
                    child: Text(
                      strings.unitsDelete,
                      style: AlayaTypography.button,
                    ),
                  ),
                  const SizedBox(height: AlayaSpacing.xxs),
                  Text(
                    strings.unitsDeleteHelp,
                    style: AlayaTypography.caption.copyWith(
                      color: context.semantic.muted,
                    ),
                  ),
                ],
                if (editing.hasError) ...[
                  const SizedBox(height: AlayaSpacing.md),
                  Text(
                    // `_ZeroFactor` stringifies to a key rather than a sentence, so the screen owns the words
                    // (Law U5) while the notifier owns the decision.
                    editing.error.toString() == 'factorMustBePositive'
                        ? strings.unitFactorMustBePositive
                        : editing.error.toString(),
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

  Widget _shell(AlayaStrings strings, Widget body) => Scaffold(
    appBar: AppBar(
      leading: const CloseButton(),
      title: Text(
        widget.unitCode == null
            ? strings.unitEditorTitle
            : strings.unitEditorEditTitle,
      ),
    ),
    body: body,
  );

  Future<void> _save(Unit? existing) async {
    final strings = AlayaStrings.of(context);
    final saved = await ref
        .read(unitEditorProvider.notifier)
        .save(
          code: _code.text,
          displayName: _name.text,
          category: _category,
          baseUnitsPerUnit: _baseAmount!,
          sortOrder: existing?.sortOrder ?? _sortOrder,
          isSystem: _isSystem,
        );
    if (!mounted || !saved) return;
    showResultSnack(context, message: strings.unitsSaved);
    context.pop();
  }

  Future<void> _delete(Unit unit) async {
    final strings = AlayaStrings.of(context);
    final confirmed = await ConfirmSheet.show(
      context,
      title: strings.unitsDeleteConfirmTitle,
      // Says what breaks rather than only what goes: a batch bought in this unit keeps its quantity, and
      // deleting the unit is what makes that quantity unreadable — the R18 failure from the other direction.
      body: strings.unitsDeleteConfirmBody,
      confirmLabel: strings.unitsDelete,
      cancelLabel: strings.actionCancel,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(unitEditorProvider.notifier).delete(unit.code);
    if (!mounted || !ok) return;
    showResultSnack(context, message: strings.unitsDeleted);
    context.pop();
  }
}

/// The explanation, and the offer.
///
/// **A refusal with somewhere to go.** ARCH_1 §5.3 says the answer to an unmeasurable amount is a new Item, and
/// this panel says why in terms of what would break — Alaya could not add two packets together or work out what
/// one cost — rather than quoting the rule. Then it offers the thing that does work, one tap away.
class _VariesPanel extends StatelessWidget {
  const _VariesPanel({required this.onBack});

  /// Returns to the form, for somebody who realises they can state a number after all.
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AlayaSpacing.screenEdge),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AlayaSpacing.md),
            decoration: BoxDecoration(
              color: semantic.warning.withValues(alpha: 0.12),
              borderRadius: AlayaRadii.borderMd,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.unitVariesTitle,
                  style: AlayaTypography.bodyEmphasis,
                ),
                const SizedBox(height: AlayaSpacing.xs),
                Text(strings.unitVariesWhy, style: AlayaTypography.body),
              ],
            ),
          ),
          const SizedBox(height: AlayaSpacing.lg),
          Text(
            strings.unitVariesInsteadTitle,
            style: AlayaTypography.bodyEmphasis,
          ),
          const SizedBox(height: AlayaSpacing.xs),
          Text(strings.unitVariesInsteadBody, style: AlayaTypography.body),
          const SizedBox(height: AlayaSpacing.lg),
          FilledButton.icon(
            // Straight to the item editor — the offer is only an offer if it goes somewhere.
            onPressed: () => context.push(Routes.itemNew),
            icon: const Icon(Icons.add, size: AlayaIconSize.md),
            label: Text(
              strings.unitVariesCreateItem,
              style: AlayaTypography.button,
            ),
          ),
          const SizedBox(height: AlayaSpacing.xs),
          TextButton(
            onPressed: onBack,
            child: Text(strings.unitVariesBack, style: AlayaTypography.button),
          ),
        ],
      ),
    );
  }
}
```

### `lib/features/settings/presentation/screens/units_settings_screen.dart`

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
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/presentation/widgets/unit_labels.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';
import 'package:alaya/shared/widgets/section_header.dart';
import 'package:alaya/shared/widgets/status_chip.dart';

/// Settings › Units (ARCH_5 §3 archetype D, outside the shell).
///
/// **Grouped by category, because the categories are the one thing here that can never change.** ARCH_1 §5.3
/// fixes them at three and Law L8 makes cross-category conversion inexpressible, so weight, volume and count
/// are not a filter the user chose — they are the shape of the data, and grouping says so without a sentence.
///
/// Each row states what one of the unit **is**, in its category's base unit: *1 kg = 1,000 g*. A factor shown
/// as `1000000` would be technically the stored value and useless to read.
class UnitsSettingsScreen extends ConsumerWidget {
  /// Creates the screen.
  const UnitsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = AlayaStrings.of(context);
    final units = ref.watch(unitsSettingsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.settingsUnits)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(Routes.unitNew),
        tooltip: strings.unitsAdd,
        child: const Icon(Icons.add, size: AlayaIconSize.lg),
      ),
      body: units.when(
        loading: () => AlayaListSkeleton(label: strings.unitsLoading),
        error: (error, stack) => ErrorState(
          title: strings.errorTitleGeneric,
          body: error.toString(),
          retryLabel: strings.actionRetry,
          onRetry: () => ref.invalidate(unitsSettingsProvider),
        ),
        data: (rows) {
          // Reachable only after somebody deletes every user unit *and* the seed's, which the seeder makes
          // unlikely — but a list screen with no empty state is a list screen that renders a blank rectangle.
          if (rows.isEmpty) {
            return EmptyState(
              title: strings.unitsEmptyTitle,
              body: strings.unitsEmptyBody,
              icon: Icons.straighten_outlined,
              actionLabel: strings.unitsAdd,
              onAction: () => context.push(Routes.unitNew),
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: AlayaSpacing.xxxl),
            children: [
              for (final category in UnitCategory.values) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: AlayaSpacing.lg,
                    bottom: AlayaSpacing.xs,
                  ),
                  child: SectionHeader(
                    label: unitCategoryLabel(strings, category),
                  ),
                ),
                for (final unit in rows.where(
                  (row) => row.category == category,
                ))
                  _UnitRow(unit: unit),
              ],
              const SizedBox(height: AlayaSpacing.lg),
              // The rule from ARCH_1 §5.3, stated where somebody about to add a unit will read it — not only
              // as a refusal after they have tried.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AlayaSpacing.screenEdge,
                ),
                child: Text(
                  strings.unitsCategoriesFixedNote,
                  style: AlayaTypography.caption.copyWith(
                    color: context.semantic.muted,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One unit, stated as what it equals.
class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.unit});

  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(
              strings.unitsRowTitle(unit.displayName, unit.code),
              style: AlayaTypography.cardTitle,
            ),
          ),
          if (unit.isSystem) ...[
            const SizedBox(width: AlayaSpacing.xs),
            StatusChip(
              label: strings.unitsSystemChip,
              tone: StatusTone.neutral,
            ),
          ],
        ],
      ),
      subtitle: Text(
        // `1 kg = 1,000 g`, assembled from the stored thousandths so the reader never meets them.
        strings.unitsEquals(
          unit.code,
          unitBaseAmountLabel(unit),
          unit.category.baseUnitCode,
        ),
        style: AlayaTypography.caption.copyWith(color: semantic.muted),
      ),
      onTap: () => context.push(Routes.unitEdit(unit.code)),
    );
  }
}
```

### `lib/features/settings/presentation/sheets/payee_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/features/settings/presentation/screens/payees_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payee (ARCH_5 §3 archetype A).
///
/// **[PayeeKind.splitPlaceholder] is not offered, and a placeholder being edited is promoted.** That
/// kind exists so a split can be saved before anybody is named — `split_shares.payee_id` is
/// `NOT NULL REFERENCES payees(id)`, so the row has to exist — and it is filtered out of every list a
/// human reads. Two things followed from adding it that this sheet got wrong:
///
/// * the chip row iterated `PayeeKind.values`, so *"Unnamed on a split"* became something a user could
///   assign to a real contact; and
/// * `_kind` was seeded from the existing row, so renaming a placeholder left the kind alone and the
///   row stayed hidden — the user did exactly the right thing and the app ignored it.
///
/// Both are fixed by [_selectableKinds] and by seeding a placeholder's selection as
/// [PayeeKind.person]: opening this sheet on a placeholder *is* the act of naming somebody, and saving
/// is what completes it.
class PayeeSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PayeeSheet({required this.existing, super.key});

  /// The payee being edited, or null for a new one.
  final Payee? existing;

  /// Shows the sheet.
  static Future<void> show(BuildContext context, {required Payee? existing}) =>
      AlayaBottomSheet.show<void>(
        context: context,
        builder: (context) => PayeeSheet(existing: existing),
      );

  /// The kinds a person may choose between.
  ///
  /// Everything except [PayeeKind.splitPlaceholder], which the app assigns and never asks about.
  /// Derived from `PayeeKind.values` rather than listed, so a seventh member appears here
  /// automatically — the opposite mistake to hardcoding, which is what left this loop showing a kind
  /// nobody should pick.
  static final List<PayeeKind> selectableKinds = [
    for (final kind in PayeeKind.values)
      if (kind != PayeeKind.splitPlaceholder) kind,
  ];

  @override
  ConsumerState<PayeeSheet> createState() => _PayeeSheetState();
}

class _PayeeSheetState extends ConsumerState<PayeeSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.existing?.phone ?? '',
  );

  /// The kind that will be written.
  ///
  /// **A placeholder arrives as [PayeeKind.person].** Opening this sheet on one is somebody deciding
  /// who it was, and leaving the selection on a kind that is filtered out of every list would make
  /// saving look like it did nothing.
  late PayeeKind _kind = switch (widget.existing?.kind) {
    null => PayeeKind.merchant,
    PayeeKind.splitPlaceholder => PayeeKind.person,
    final existing => existing,
  };

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(payeeEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null ? strings.payeesAdd : strings.payeesEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          decoration: InputDecoration(labelText: strings.payeeNameLabel),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        // Optional, and marked as such. A payee is usually a shop name and nothing else; an unmarked
        // second field reads as required and is the commonest reason a two-field sheet feels like a form.
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: strings.payeePhoneOptionalLabel,
          ),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PayeeSheet.selectableKinds)
              ChoiceChip(
                label: Text(
                  payeeKindLabel(strings, kind),
                  style: AlayaTypography.button,
                ),
                selected: kind == _kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || editing.isLoading
              ? null
              : () => _save(strings),
          child: Text(strings.payeesSave, style: AlayaTypography.button),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final phone = _phone.text.trim();
    final ok = await ref
        .read(payeeEditorProvider.notifier)
        .save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          // Empty becomes null rather than an empty string, so a "has a phone number" test anywhere
          // else does not have to know about both.
          phone: phone.isEmpty ? null : phone,
          note: widget.existing?.note,
        );
    if (!mounted) return;

    // **The message goes up before the sheet comes down, and the order is the whole fix.** This used
    // to pop first and then check `context.mounted` — which is false the instant a sheet pops, so the
    // check returned and *both* snacks were dropped. A duplicate-name refusal, the one message that
    // explains why nothing happened, had never once been visible.
    //
    // `ScaffoldMessenger` lives above this route, so a snack shown now outlives the pop that follows.
    // The guard that caused the silence looks exactly like the guard that prevents a crash, which is
    // why it survived review: `if (!context.mounted) return;` is correct almost everywhere else.
    ok
        ? showResultSnack(context, message: strings.payeesSaved)
        : showFailureSnack(context, message: strings.payeesSaveFailed);
    Navigator.of(context).pop();
  }
}
```

### `lib/features/settings/presentation/sheets/payment_method_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payment_method.dart';
import 'package:alaya/features/settings/presentation/screens/payment_methods_settings_screen.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';
import 'package:alaya/shared/widgets/alaya_bottom_sheet.dart';

/// Naming a payment method (ARCH_5 §3 archetype A).
///
/// One required field with the keyboard already up, the kind as chips rather than a picker, and a full-width
/// commit enabled the moment the name parses.
class PaymentMethodSheet extends ConsumerStatefulWidget {
  /// Creates the sheet. Prefer [show].
  const PaymentMethodSheet({
    required this.existing,
    required this.nextSortOrder,
    super.key,
  });

  /// The method being renamed, or null for a new one.
  final PaymentMethod? existing;

  /// The sort order a new method takes.
  final int nextSortOrder;

  /// Shows the sheet.
  static Future<void> show(
    BuildContext context, {
    required PaymentMethod? existing,
    required int nextSortOrder,
  }) => AlayaBottomSheet.show<void>(
    context: context,
    builder: (context) =>
        PaymentMethodSheet(existing: existing, nextSortOrder: nextSortOrder),
  );

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late PaymentMethodKind _kind =
      widget.existing?.kind ?? PaymentMethodKind.cash;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final editing = ref.watch(paymentMethodEditorProvider);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.existing == null
              ? strings.paymentMethodsAdd
              : strings.paymentMethodsEditTitle,
          style: AlayaTypography.sectionHeader,
        ),
        const SizedBox(height: AlayaSpacing.md),
        TextField(
          controller: _name,
          decoration: InputDecoration(
            labelText: strings.paymentMethodNameLabel,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AlayaSpacing.md),
        Wrap(
          spacing: AlayaSpacing.xs,
          runSpacing: AlayaSpacing.xs,
          children: [
            for (final kind in PaymentMethodKind.values)
              ChoiceChip(
                label: Text(
                  paymentMethodKindLabel(strings, kind),
                  style: AlayaTypography.button,
                ),
                selected: kind == _kind,
                onSelected: (_) => setState(() => _kind = kind),
              ),
          ],
        ),
        const SizedBox(height: AlayaSpacing.lg),
        FilledButton(
          onPressed: _name.text.trim().isEmpty || editing.isLoading
              ? null
              : () => _save(strings),
          child: Text(
            strings.paymentMethodsSave,
            style: AlayaTypography.button,
          ),
        ),
      ],
    );
  }

  Future<void> _save(AlayaStrings strings) async {
    final ok = await ref
        .read(paymentMethodEditorProvider.notifier)
        .save(
          id: widget.existing?.id,
          name: _name.text,
          kind: _kind,
          sortOrder: widget.existing?.sortOrder ?? widget.nextSortOrder,
          // Preserved rather than defaulted: renaming a seeded method must not quietly turn it into a
          // user-created one that can then be deleted.
          isSystem: widget.existing?.isSystem ?? false,
        );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!context.mounted) return;
    ok
        ? showResultSnack(context, message: strings.paymentMethodsSaved)
        : showFailureSnack(context, message: strings.paymentMethodsSaveFailed);
  }
}
```

### `lib/features/settings/presentation/widgets/tag_scope_labels.dart`

```dart
import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/enums/tag_scope.dart';

/// The name of each place a tag may be offered.
///
/// **One switch, shared by the list and the editor**, so a scope cannot be called one thing on the row and
/// another in the matrix that sets it. Exhaustive over [TagScope] without a `default`, so adding a seventh
/// picker to the app fails to compile here instead of shipping a chip with no label.
String tagScopeLabel(AlayaStrings strings, TagScope scope) => switch (scope) {
  TagScope.deposit => strings.tagScopeDeposit,
  TagScope.withdrawal => strings.tagScopeWithdrawal,
  TagScope.inventory => strings.tagScopeInventory,
  TagScope.shopping => strings.tagScopeShopping,
  TagScope.recurring => strings.tagScopeRecurring,
  TagScope.service => strings.tagScopeService,
};

/// What each scope actually controls, for the editor's matrix.
///
/// The help line matters more here than anywhere else in Settings: "Withdrawal" tells the reader nothing about
/// *why* unticking it would make a tag vanish from the screen they use most.
String tagScopeHelp(AlayaStrings strings, TagScope scope) => switch (scope) {
  TagScope.deposit => strings.tagScopeDepositHelp,
  TagScope.withdrawal => strings.tagScopeWithdrawalHelp,
  TagScope.inventory => strings.tagScopeInventoryHelp,
  TagScope.shopping => strings.tagScopeShoppingHelp,
  TagScope.recurring => strings.tagScopeRecurringHelp,
  TagScope.service => strings.tagScopeServiceHelp,
};
```

### `lib/features/settings/presentation/widgets/unit_labels.dart`

```dart
import 'package:intl/intl.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';
import 'package:alaya/features/settings/providers/unit_settings_providers.dart';

/// The name of each quantity category.
///
/// Exhaustive without a `default`, so ARCH_1 §5.3's promise that there is never a fourth category is enforced
/// by the compiler here as well as by the enum.
String unitCategoryLabel(AlayaStrings strings, UnitCategory category) =>
    switch (category) {
      UnitCategory.weight => strings.unitCategoryWeight,
      UnitCategory.volume => strings.unitCategoryVolume,
      UnitCategory.count => strings.unitCategoryCount,
    };

/// How many base units one [unit] is, formatted for reading.
///
/// **Divides by [milliPerBaseUnit], which is the one arithmetic ARCH_4 R18 was about.** The column counts
/// thousandths of the base unit, so a kilogram is stored as 1,000,000 and shown as 1,000 g. Trailing zeros are
/// dropped, so a tablespoon reads *14.79 ml* rather than *14.790*.
String unitBaseAmountLabel(Unit unit) {
  final base = unit.factorToBaseMilli / milliPerBaseUnit;
  final formatter = base == base.roundToDouble()
      ? NumberFormat.decimalPattern()
      : NumberFormat('#,##0.###');
  return formatter.format(base);
}

/// The plural name of a category's base unit — "grams", "millilitres", "pieces".
///
/// The *name*, not the code, because the editor's question reads "How many grams is one kilogram?" and a
/// question phrased with `g` in it asks the user to decode an abbreviation before they can answer.
String unitBaseUnitName(AlayaStrings strings, UnitCategory category) =>
    switch (category) {
      UnitCategory.weight => strings.unitBaseGrams,
      UnitCategory.volume => strings.unitBaseMillilitres,
      UnitCategory.count => strings.unitBasePieces,
    };
```

### `lib/features/settings/providers/app_settings_providers.dart`

```dart
/// View-model state for the currencies, appearance and security branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/domain/entities/currency.dart';

/// Every currency, enabled or not.
final currenciesSettingsProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchAll(),
);

/// The home currency's code, which cannot be disabled.
final homeCurrencyCodeProvider = FutureProvider<String?>(
  (ref) => ref.watch(settingsRepositoryProvider).readHomeCurrencyCode(),
);

/// Enables and disables currencies.
final currencyToggleProvider =
    NotifierProvider<CurrencyToggleNotifier, AsyncValue<void>>(
      CurrencyToggleNotifier.new,
    );

/// Writes a currency's enabled flag.
class CurrencyToggleNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Enables or disables [code].
  Future<bool> setEnabled({
    required String code,
    required bool isEnabled,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(currencyRepositoryProvider)
        .setEnabled(code: code, isEnabled: isEnabled);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('toggle failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// How many rows are in the trash, for the Data branch's row.
///
/// Phase 8B. Reads `trashPortProvider`, which is app-level — a feature watching another feature's provider would
/// be the coupling ARCH_5 §8 keeps out of the settings tree.
final settingsTrashCountProvider = StreamProvider<int>(
  (ref) => ref.watch(trashPortProvider).watchCount(),
);

/// Whether a lock is configured, for the security branch.
final lockConfiguredProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinServiceProvider).isEnabled,
);
```

### `lib/features/settings/providers/money_settings_providers.dart`

```dart
/// View-model state for the accounts, payment-method and payee branches (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/domain/entities/payee.dart';
import 'package:alaya/domain/entities/payment_method.dart';

/// Every account, archived ones included, so the branch can offer to un-archive.
final accountsSettingsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAllIncludingArchived(),
);

/// Every payment method.
final paymentMethodsSettingsProvider = StreamProvider<List<PaymentMethod>>(
  (ref) => ref.watch(paymentMethodRepositoryProvider).watchAll(),
);

/// Whether [payee] is one a person would recognise as theirs.
///
/// **The one place this rule is written.** Saving a split with unnamed participants has to create a payee
/// row for each of them — `split_shares.payee_id` is `NOT NULL REFERENCES payees(id)`, so otherwise the
/// split cannot be saved at all — and those rows are bookkeeping, not contacts.
///
/// Two providers need to agree about it: the list of payees, and the count on the settings row that labels
/// that list. The first attempt filtered inside the screen, the second filtered inside one provider, and
/// both times the other reader kept counting rows the list refused to show — a settings row saying *3
/// payees* above a screen listing one. A predicate with a name has one definition however many callers it
/// grows.
bool isContactPayee(Payee payee) => payee.kind != PayeeKind.splitPlaceholder;

/// Every payee a person would recognise as one.
///
/// Filters on [isContactPayee]. A placeholder stays reachable where it matters: a split balance row renders
/// one in italics with a **Who is this?** button, and naming it writes `kind: person` — at which point it
/// appears here on the next stream tick with nothing else to do.
final payeesSettingsProvider = StreamProvider<List<Payee>>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((all) => all.where(isContactPayee).toList()),
);

/// The home currency, as the default for a new account.
///
/// A new account in a currency the user never uses is a row they will edit before their first transaction, so
/// the default is the one currency they have already chosen (Law L9's setting, used as a hint rather than a rule).
final accountsHomeCurrencyProvider = FutureProvider<String>(
  (ref) async =>
      await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      'INR',
);

/// One account being edited, or null for a new one.
final accountDraftProvider = FutureProvider.autoDispose
    .family<Account?, String?>((ref, id) async {
      if (id == null) return null;
      return ref.watch(accountRepositoryProvider).byId(id);
    });

/// Saves and archives accounts.
final accountEditorProvider =
    NotifierProvider<AccountEditorNotifier, AsyncValue<void>>(
      AccountEditorNotifier.new,
    );

/// Writes an account, reporting the repository's own message on failure.
class AccountEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces [account], returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required AccountKind kind,
    required String currencyCode,
    required int openingMinor,
    required DateKey openingDate,
    required bool includeInNetWorth,
    required bool isArchived,
    required int sortOrder,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(accountRepositoryProvider)
        .save(
          Account(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            currencyCode: currencyCode,
            openingBalance: Money(openingMinor, currencyCode),
            openingBalanceDateKey: openingDate,
            isArchived: isArchived,
            includeInNetWorth: includeInNetWorth,
            sortOrder: sortOrder,
          ),
        );
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('save failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }

  /// Archives or restores [id].
  ///
  /// **Archive, not delete.** ARCH_3 §4 keeps an archived account out of every picker while its history stays
  /// intact and its balance stays out of net worth if the user said so — deleting one would orphan every
  /// transaction that ever named it.
  Future<bool> setArchived({
    required String id,
    required bool isArchived,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(accountRepositoryProvider)
        .setArchived(id: id, isArchived: isArchived);
    if (result.isFailure) {
      state = AsyncError<void>(
        result.failureOrNull ?? StateError('archive failed'),
        StackTrace.current,
      );
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payment method.
final paymentMethodEditorProvider =
    NotifierProvider<PaymentMethodEditorNotifier, AsyncValue<void>>(
      PaymentMethodEditorNotifier.new,
    );

/// Writes a payment method.
class PaymentMethodEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PaymentMethodKind kind,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(paymentMethodRepositoryProvider)
        .save(
          PaymentMethod(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            kind: kind,
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(paymentMethodRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Saves a payee.
final payeeEditorProvider =
    NotifierProvider<PayeeEditorNotifier, AsyncValue<void>>(
      PayeeEditorNotifier.new,
    );

/// Writes a payee.
class PayeeEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces one, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required PayeeKind kind,
    String? phone,
    String? note,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(payeeRepositoryProvider)
        .save(
          Payee(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            kind: kind,
            phone: phone,
            note: note,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(payeeRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
```

### `lib/features/settings/providers/settings_providers.dart`

```dart
/// View-model state for the settings tree (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/features/settings/providers/money_settings_providers.dart';

/// What the user has typed into the settings search field.
final settingsQueryProvider = NotifierProvider<SettingsQueryNotifier, String>(
  SettingsQueryNotifier.new,
);

/// Holds the settings search term.
class SettingsQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  /// Records [query].
  void set(String query) => state = query;
}

/// How many accounts exist, archived ones included.
///
/// **Archived included, unlike the pickers.** This row is the way to *reach* an archived account and
/// un-archive it, so a count that hid them would make the branch look emptier than the screen behind it —
/// and an archived account the user cannot find is one they will recreate by hand.
final settingsAccountCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(accountRepositoryProvider)
      .watchAllIncludingArchived()
      .map((accounts) => accounts.length),
);

/// How many payment methods exist.
final settingsPaymentMethodCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(paymentMethodRepositoryProvider)
      .watchAll()
      .map((rows) => rows.length),
);

/// How many payees the branch will show.
///
/// **Counts what [isContactPayee] admits, which is what the list shows.** This used to count every row the
/// repository had, while the branch it labels filtered out `PayeeKind.splitPlaceholder`. Both were correct
/// for what they read and they disagreed by the number of unnamed split participants: the row said *3
/// payees* above a screen listing one.
///
/// **Still a `StreamProvider<int>`, deliberately.** The first fix made it a `Provider<AsyncValue<int>>`
/// reading `payeesSettingsProvider`, which shares the source but changes the type — and every test harness
/// that overrides this with a stream stopped compiling. A shared *predicate* fixes the disagreement without
/// touching the shape, which is what an override is written against.
final settingsPayeeCountProvider = StreamProvider<int>(
  (ref) => ref
      .watch(payeeRepositoryProvider)
      .watchAll()
      .map((rows) => rows.where(isContactPayee).length),
);

/// How many tags exist.
final settingsTagCountProvider = StreamProvider<int>(
  (ref) =>
      ref.watch(tagRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many units exist.
final settingsUnitCountProvider = StreamProvider<int>(
  (ref) =>
      ref.watch(unitRepositoryProvider).watchAll().map((rows) => rows.length),
);

/// How many currencies are enabled, and how many exist.
final settingsCurrencyCountProvider =
    StreamProvider<({int enabled, int total})>((ref) {
      final repository = ref.watch(currencyRepositoryProvider);
      return repository.watchAll().asyncMap((all) async {
        final enabled = await repository.watchEnabled().first;
        return (enabled: enabled.length, total: all.length);
      });
    });
```

### `lib/features/settings/providers/split_settings_providers.dart`

```dart
/// Writing the split module's two settings (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/result/failure.dart';
import 'package:alaya/features/split/providers/split_providers.dart';
import 'package:alaya/features/split/providers/split_summary_provider.dart';

/// Saves who the user is, and how people can pay them.
final splitSettingsProvider = NotifierProvider<SplitSettings, AsyncValue<void>>(
  SplitSettings.new,
);

/// Writes `split.selfPayeeId` and `split.paymentHandle`.
class SplitSettings extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  /// Claims [payeeId] as the user.
  ///
  /// **Invalidating `splitSelfProvider` is not optional.** It is a `FutureProvider` over a one-shot
  /// read — the setting changes once, during setup, so a stream would be machinery for an event that
  /// happens a single time — and without the invalidation every balance screen keeps the null it was
  /// built with until the app restarts. The user would set the value, see no change, and reasonably
  /// conclude it did not work.
  Future<bool> setSelf(String payeeId) async {
    final result = await ref
        .read(splitGroupRepositoryProvider)
        .setSelfPayeeId(payeeId);
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull!, StackTrace.current);
      return false;
    }
    ref.invalidate(splitSelfProvider);
    return true;
  }

  /// Sets or clears how people can pay the user.
  ///
  /// **Free text, and deliberately unvalidated.** The field used to be a UPI id, which meant the app
  /// implicitly assumed India; it now holds whatever a user anywhere writes — a PayPal link, an IBAN,
  /// a Venmo handle, "cash is fine". Any validation would be a guess about which country somebody is
  /// in, and a wrong guess would reject a perfectly good answer.
  ///
  /// An empty string removes the row rather than storing a blank, so `SplitSummaryBuilder` sees null
  /// and omits the line instead of writing a label with nothing after it.
  Future<bool> setPaymentHandle(String value) async {
    final settings = ref.read(settingsRepositoryProvider);
    final trimmed = value.trim();
    final result = trimmed.isEmpty
        ? await settings.remove(splitPaymentHandleKey)
        : await settings.writeValue(
            key: splitPaymentHandleKey,
            value: trimmed,
            valueType: 'string',
          );
    if (result.isFailure) {
      state = AsyncError<void>(result.failureOrNull!, StackTrace.current);
      return false;
    }
    ref.invalidate(splitPaymentHandleProvider);
    return true;
  }

  /// The message from the last failure, or null.
  ///
  /// Typed, not cast: an `as dynamic` to reach `message` would compile against anything and fail at
  /// runtime the first time a non-`Failure` landed in the error slot.
  String? get lastError {
    final error = state.error;
    return error is Failure ? error.message : null;
  }
}
```

### `lib/features/settings/providers/tag_settings_providers.dart`

```dart
/// View-model state for the tags branch (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';

/// Every tag, deleted ones excluded.
final tagsSettingsProvider = StreamProvider<List<Tag>>(
  (ref) => ref.watch(tagRepositoryProvider).watchAll(),
);

/// The tags arranged as one level of parents with their children.
///
/// **One level, and the flattening is deliberate rather than a limitation.** ARCH_2 gives `tags.parentTagId`
/// no depth limit, but a tree deeper than one level cannot be shown in a picker without either indenting past
/// the width of a phone or hiding rows behind a disclosure nobody opens. A tag that is a child of a child is
/// rendered here as a child of its **top-most** ancestor, so it is reachable and grouped rather than lost.
final tagTreeProvider = Provider<List<({Tag parent, List<Tag> children})>>((
  ref,
) {
  final tags = ref.watch(tagsSettingsProvider).valueOrNull ?? const <Tag>[];
  final byId = {for (final tag in tags) tag.id: tag};

  String rootOf(Tag tag) {
    var current = tag;
    // Bounded by the number of tags, so a parent cycle written by a bad import cannot hang the screen. A cycle
    // is not supposed to be possible, and a UI that trusts that is a UI that freezes when it turns out to be.
    for (var hops = 0; hops < tags.length; hops++) {
      final parentId = current.parentTagId;
      if (parentId == null) return current.id;
      final parent = byId[parentId];
      if (parent == null) return current.id;
      current = parent;
    }
    return current.id;
  }

  final roots = [
    for (final tag in tags)
      if (tag.parentTagId == null) tag,
  ];
  final children = <String, List<Tag>>{};
  for (final tag in tags) {
    if (tag.parentTagId == null) continue;
    children.putIfAbsent(rootOf(tag), () => <Tag>[]).add(tag);
  }
  return [
    for (final root in roots)
      (parent: root, children: children[root.id] ?? const <Tag>[]),
  ];
});

/// One tag being edited, or null for a new one.
final tagDraftProvider = FutureProvider.autoDispose.family<Tag?, String?>((
  ref,
  id,
) async {
  if (id == null) return null;
  return ref.watch(tagRepositoryProvider).byId(id);
});

/// The tags that may be chosen as a parent for [id].
///
/// Excludes the tag itself and anything already beneath it, so the picker cannot be used to build a cycle —
/// the check belongs where the choice is offered, not in an error after the fact.
final tagParentChoicesProvider = Provider.family<List<Tag>, String?>((ref, id) {
  final tags = ref.watch(tagsSettingsProvider).valueOrNull ?? const <Tag>[];
  if (id == null)
    return [
      for (final tag in tags)
        if (tag.parentTagId == null) tag,
    ];
  final descendants = <String>{id};
  var grew = true;
  while (grew) {
    grew = false;
    for (final tag in tags) {
      final parentId = tag.parentTagId;
      if (parentId != null &&
          descendants.contains(parentId) &&
          descendants.add(tag.id)) {
        grew = true;
      }
    }
  }
  return [
    for (final tag in tags)
      if (!descendants.contains(tag.id)) tag,
  ];
});

/// Saves and deletes tags.
final tagEditorProvider = NotifierProvider<TagEditorNotifier, AsyncValue<void>>(
  TagEditorNotifier.new,
);

/// Writes a tag.
class TagEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces a tag, returning whether it was written.
  Future<bool> save({
    required String? id,
    required String name,
    required Set<TagScope> allowedScopes,
    required int sortOrder,
    String? parentTagId,
    int? colorArgb,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final result = await ref
        .read(tagRepositoryProvider)
        .save(
          Tag(
            id: id ?? ref.read(uidGeneratorProvider).generate(),
            name: name.trim(),
            normalizedName: ref.read(normalizerProvider).normalize(name),
            allowedScopes: allowedScopes,
            isSystem: isSystem,
            sortOrder: sortOrder,
            isDeleted: false,
            parentTagId: parentTagId,
            colorArgb: colorArgb,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [id].
  ///
  /// `delete`, which the repository implements as the soft delete ARCH_3 §4 requires — the row keeps its
  /// history and leaves every picker. A tag hard-removed would orphan the `transaction_tags` rows naming it.
  Future<bool> delete(String id) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(tagRepositoryProvider).delete(id);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}
```

### `lib/features/settings/providers/unit_settings_providers.dart`

```dart
/// View-model state for the units branch (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/core/quantity/unit_category.dart';
import 'package:alaya/domain/entities/unit.dart';

/// Every unit, system ones included.
final unitsSettingsProvider = StreamProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).watchAll(),
);

/// One unit being edited, or null for a new one.
final unitDraftProvider = FutureProvider.autoDispose.family<Unit?, String?>((
  ref,
  code,
) async {
  if (code == null) return null;
  return ref.watch(unitRepositoryProvider).byCode(code);
});

/// How many base-milli units one base unit is.
///
/// **The whole of ARCH_4 R18 lives in this number.** `factorToBaseMilli` counts *thousandths* of the base
/// unit, so a kilogram is 1,000,000 and not 1,000 — and R18 was three separate sites that divided by 1,000
/// instead of by the unit's factor, which valued two kilos of potatoes at a hundred thousand rupees. The
/// editor asks the user for base units and multiplies here, in one place, rather than asking anybody to
/// think in thousandths.
const int milliPerBaseUnit = 1000;

/// Saves and deletes units.
final unitEditorProvider =
    NotifierProvider<UnitEditorNotifier, AsyncValue<void>>(
      UnitEditorNotifier.new,
    );

/// Writes a unit.
class UnitEditorNotifier extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData<void>(null);

  /// Creates or replaces a unit from a factor expressed in **base units**.
  ///
  /// [baseUnitsPerUnit] is what the user typed — 1000 for a kilogram, 12 for a dozen, 14.79 for a
  /// tablespoon. It is multiplied by [milliPerBaseUnit] and rounded here, so no screen has to know that the
  /// column counts thousandths.
  Future<bool> save({
    required String code,
    required String displayName,
    required UnitCategory category,
    required double baseUnitsPerUnit,
    required int sortOrder,
    bool isSystem = false,
  }) async {
    state = const AsyncLoading<void>();
    final factor = (baseUnitsPerUnit * milliPerBaseUnit).round();
    if (factor <= 0) {
      // Guarded rather than trusted: a zero factor would make every quantity in that unit convert to nothing,
      // silently, and a division by it would take out the inventory valuation.
      state = AsyncError<void>(
        const _ZeroFactor(),
        StackTrace.current,
      );
      return false;
    }
    final result = await ref
        .read(unitRepositoryProvider)
        .save(
          Unit(
            code: code.trim(),
            category: category,
            factorToBaseMilli: factor,
            displayName: displayName.trim(),
            isSystem: isSystem,
            sortOrder: sortOrder,
          ),
        );
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  /// Deletes [code].
  Future<bool> delete(String code) async {
    state = const AsyncLoading<void>();
    final result = await ref.read(unitRepositoryProvider).delete(code);
    return _settle(result.isFailure ? result.failureOrNull : null);
  }

  bool _settle(Object? failure) {
    if (failure != null) {
      state = AsyncError<void>(failure, StackTrace.current);
      return false;
    }
    state = const AsyncData<void>(null);
    return true;
  }
}

/// Signals a factor of zero or less, so the screen can say so in its own words (Law U5).
class _ZeroFactor implements Exception {
  const _ZeroFactor();

  @override
  String toString() => 'factorMustBePositive';
}
```

### `lib/features/settings/state/appearance_settings.dart`

```dart
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';

/// How the appearance choices are stored, and how a stored string becomes a choice again.
///
/// **This closes ARCH_4 §5.1 item 23.** `activePaletteProvider` and `themeModeProvider` shipped in
/// Phase 5 as bare `StateProvider`s with no `app_settings` backing, so a user's dark-mode choice was
/// lost on every restart. The audit recorded it as 8A's work rather than a Phase 5 defect; this is the
/// storage half of the fix.
///
/// Both parsers **fall back rather than throw**, for the reason Law L13 gives about enums in the
/// database: a settings row is user data, a later version may write a palette name this build has
/// never heard of, and a theme choice is not worth failing app startup over.
abstract final class AppearanceSettings {
  /// The `app_settings` key holding the chosen palette's name.
  static const String paletteKey = 'appearance.palette';

  /// The `app_settings` key holding the chosen theme mode.
  static const String themeModeKey = 'appearance.themeMode';

  /// The palette a fresh install uses.
  ///
  /// `AlayaPresets.activePreset` and not a name of its own, so ARCH_3 §8.1's promise that one constant
  /// switches the shipped look survives the arrival of a picker.
  static AlayaPalette get fallbackPalette => AlayaPresets.activePreset;

  /// The theme mode a fresh install uses.
  ///
  /// Following the system is the only defensible default: a finance app opened at midnight should not
  /// be the one bright thing on the phone, and nobody should have to choose before they have seen it.
  static const ThemeMode fallbackThemeMode = ThemeMode.system;

  /// Parses a stored palette name, falling back for anything this build cannot offer.
  static AlayaPalette parsePalette(String? stored) {
    for (final palette in AlayaPresets.all) {
      if (palette.name == stored) return palette;
    }
    return fallbackPalette;
  }

  /// The value written back for [palette].
  static String storedPalette(AlayaPalette palette) => palette.name;

  /// Parses a stored theme mode, falling back for anything unrecognised.
  static ThemeMode parseThemeMode(String? stored) {
    for (final mode in ThemeMode.values) {
      if (mode.name == stored) return mode;
    }
    return fallbackThemeMode;
  }

  /// The value written back for [mode].
  static String storedThemeMode(ThemeMode mode) => mode.name;
}
```

### `test/features/lock/lock_screen_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/features/lock/presentation/screens/lock_screen.dart';
import 'package:alaya/features/lock/presentation/widgets/pin_pad.dart';
import 'package:alaya/shared/widgets/shake_on_error.dart';

import '../../support/settings_harness.dart';

/// `LockScreen` — archetype A's shape, all four states (Law U4, ARCH_5 §9.1).
///
/// **These tests exist only because `AppLock` is an interface.** `PinService` is `final class` and reaches
/// `flutter_secure_storage`, so there was no way to fake it and no way to run a platform channel here — the
/// contract is what makes the §9.1 gate reachable at all.
void main() {
  group('the four states', () {
    testWidgets('loading shows the keypad and no refusal', (tester) async {
      // The screen has no spinner: it is usable the instant it mounts, and the PIN length arriving a frame later
      // changes the dot count rather than gating the keys.
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      expect(find.byType(PinKeypad), findsOneWidget);
      expect(find.text('That PIN is not right.'), findsNothing);
    });

    testWidgets('populated draws one dot per configured digit', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, pinLength: 6),
        ),
      );
      await tester.pumpAndSettle();
      // Six, not four. `readPinLength` was added to the port for exactly this — a six-digit PIN entered into four
      // boxes is a confusing failure rather than a wrong one.
      final dots = tester.widget<PinDots>(find.byType(PinDots));
      expect(dots.length, 6);
    });

    testWidgets('a wrong PIN shakes, clears, and says so', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, correctPin: '9999'),
        ),
      );
      await tester.pumpAndSettle();
      final before = tester
          .widget<ShakeOnError>(find.byType(ShakeOnError))
          .trigger;

      for (final digit in ['1', '2', '3', '4']) {
        await tester.tap(find.text(digit));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.text('That PIN is not right.'), findsOneWidget);
      // The trigger increments, so two failures in a row shake twice rather than once (ARCH_5 §2.6).
      expect(
        tester.widget<ShakeOnError>(find.byType(ShakeOnError)).trigger,
        greaterThan(before),
      );
      // Cleared, so the next attempt starts empty rather than making the user delete four digits they already
      // know are wrong.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });

    testWidgets('a throttle states a duration and refuses taps', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(
            enabled: true,
            lockout: const Duration(seconds: 65),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // `m:ss` for anything past a minute, formatted in Dart because a plural on "second" cannot express 1:05.
      expect(find.textContaining('1:05'), findsOneWidget);
      expect(find.textContaining('The wait gets longer'), findsOneWidget);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      // Still nothing entered: a throttled keypad accepts no digits, so the delay cannot be spent guessing.
      expect(tester.widget<PinDots>(find.byType(PinDots)).filled, 0);
    });
  });

  group('the honest copy', () {
    testWidgets('says it does not encrypt, and shows no padlock', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();

      // **ARCH_3 §2.5, asserted rather than trusted.** This is the one string in the app whose absence would be a
      // Play listing risk as well as a lie, so the test names the phrase rather than the key.
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      // No padlock: a closed padlock is the universal icon for encryption and would undo the sentence beside it.
      expect(find.byIcon(Icons.lock), findsNothing);
      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.textContaining('bank-grade'), findsNothing);
      expect(find.textContaining('military'), findsNothing);
    });
  });

  group('the biometric shortcut', () {
    testWidgets('is absent, not disabled, where the device has none', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(),
        ),
      );
      await tester.pumpAndSettle();
      // A disabled control that can never become enabled is the dead affordance ARCH_5 §10 objects to.
      expect(find.byIcon(Icons.fingerprint), findsNothing);
    });

    testWidgets('appears where the device has one', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fingerprint), findsOneWidget);
    });
  });

  group('the gate', () {
    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true, pinLength: 6),
        ),
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('every target is large enough and named', (tester) async {
      await pumpSettings(
        tester,
        const LockScreen(),
        overrides: settingsOverrides(
          lock: FakeAppLock(enabled: true),
          biometric: FakeBiometricGate(available: true),
        ),
      );
      await tester.pumpAndSettle();
      // The keypad is why this passes without special pleading: every key is a labelled 48dp target, which the
      // system keyboard could not have guaranteed.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });
  });
}
```

### `test/features/settings/settings_tree_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/domain/entities/account.dart';
import 'package:alaya/core/enums/tag_scope.dart';
import 'package:alaya/domain/entities/tag.dart';
import 'package:alaya/features/settings/presentation/screens/accounts_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/currencies_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/security_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/settings_screen.dart';
import 'package:alaya/features/settings/providers/app_settings_providers.dart';
import 'package:alaya/features/settings/presentation/screens/tags_settings_screen.dart';
import 'package:alaya/features/settings/presentation/screens/units_settings_screen.dart';
import 'package:alaya/shared/widgets/alaya_list_skeleton.dart';
import 'package:alaya/shared/widgets/empty_state.dart';
import 'package:alaya/shared/widgets/error_state.dart';

import '../../support/settings_harness.dart';

/// Tall enough that a lazy `ListView` builds its whole body.
///
/// **Content assertions get this; the U15 gate does not.** A settings body is a lazy list, so at 320x640 a
/// row below the fold is never built and `findsNothing` passes for the wrong reason — the same trap 7B's
/// analytics sliver had. Splitting the two concerns is the fix: these tests ask *what exists*, and the
/// separate 320x640 tests ask *whether it fits*. Scrolling was the alternative and it is worse here, because
/// `find...last` on a not-yet-built widget throws `Bad state: No element` rather than failing an assertion.
const Size kTallViewport = Size(320, 2000);

/// The settings tree and its branches — four states each (Law U4, ARCH_5 §9.1).
void main() {
  group('the tree', () {
    testWidgets('groups every branch and declares no chrome of its own', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      // **By semantics label, not by text.** `SectionHeader` renders `label.toUpperCase()` and supplies the
      // original as `semanticsLabel` — so asserting the visible string would couple this test to a styling
      // choice, and asserting `'YOUR MONEY'` would break the day that choice changes.
      expect(find.bySemanticsLabel('Your money'), findsOneWidget);
      expect(find.bySemanticsLabel('Your things'), findsOneWidget);
      expect(find.bySemanticsLabel('The app'), findsOneWidget);
      // Exactly one Scaffold — the harness's stand-in for the drawer shell — and no AppBar, because `/settings`
      // is a shell destination and a bar declared here would be a second one inside it (Law U18).
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('search matches a keyword, not only a title', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'dark');
      await tester.pumpAndSettle();
      // Nothing in the app is called "dark", which is the whole point: a tree matching only headings would answer
      // "no results" for a setting sitting right there.
      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Accounts'), findsNothing);
    });

    testWidgets('a query matching nothing names the search, not the tree', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'zzzz');
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.textContaining('Nothing matches'), findsOneWidget);
    });

    testWidgets('renders at 320x640 with a doubled text scale', (tester) async {
      await pumpSettings(
        tester,
        const SettingsScreen(),
        overrides: settingsOverrides(),
        wrapInShell: true,
        textScale: 2,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('accounts', () {
    testWidgets('loading is a skeleton, not a spinner', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: const AsyncValue<List<Account>>.loading(),
        ),
      );
      expect(find.byType(AlayaListSkeleton), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('error carries the repository message', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue<List<Account>>.error(
            Exception('accounts table is locked'),
            StackTrace.empty,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      // Never a generic body (Law U9).
      expect(find.textContaining('accounts table is locked'), findsOneWidget);
    });

    testWidgets('empty names the next action', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: const AsyncValue.data(<Account>[]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('Add an account'), findsWidgets);
    });

    testWidgets('archived accounts are grouped, not hidden', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([
            account(),
            account(id: 'ac-2', name: 'Old wallet', isArchived: true),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // This screen is the only way to reach an archived account and restore it, so hiding them here would make
      // one unreachable — and an account nobody can find is one they recreate by hand.
      expect(find.text('Archived'), findsWidgets);
      expect(find.text('Old wallet'), findsOneWidget);
    });

    testWidgets('an excluded account says so on the row', (tester) async {
      await pumpSettings(
        tester,
        const AccountsSettingsScreen(),
        overrides: settingsOverrides(
          accounts: AsyncValue.data([account(includeInNetWorth: false)]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Not in net worth'), findsOneWidget);
    });
  });

  group('tags — the scoping matrix', () {
    testWidgets('every row states where the tag is offered', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(scopes: {TagScope.inventory, TagScope.shopping}),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // A scope only visible after opening the editor is one nobody notices is wrong.
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('Shopping lists'), findsOneWidget);
      expect(find.text('Income'), findsNothing);
    });

    testWidgets('a tag scoped nowhere is called out', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([tag(scopes: const {})]),
        ),
      );
      await tester.pumpAndSettle();
      // It cannot appear anywhere in the app, which makes it invisible everywhere except this screen — exactly
      // the dead row somebody would hunt for in the pickers first.
      expect(find.textContaining('not offered anywhere'), findsOneWidget);
    });

    testWidgets('a child is grouped under its parent, one level deep', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(),
            tag(id: 'tg-2', name: 'Fridge', parentTagId: 'tg-1'),
            // A grandchild, which must surface under the top-most ancestor rather than vanish.
            tag(id: 'tg-3', name: 'Freezer', parentTagId: 'tg-2'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kitchen'), findsOneWidget);
      expect(find.text('Fridge'), findsOneWidget);
      expect(find.text('Freezer'), findsOneWidget);
    });

    testWidgets('a parent cycle does not hang the screen', (tester) async {
      await pumpSettings(
        tester,
        const TagsSettingsScreen(),
        overrides: settingsOverrides(
          tags: AsyncValue.data([
            tag(id: 'a', name: 'A', parentTagId: 'b'),
            tag(id: 'b', name: 'B', parentTagId: 'a'),
          ]),
        ),
      );
      await tester.pumpAndSettle();
      // The root walk is bounded by the tag count. A cycle should be impossible, and a UI that trusts that is a
      // UI that freezes when it turns out not to be.
      expect(tester.takeException(), isNull);
    });
  });

  group('units', () {
    testWidgets('a row states what the unit equals, never its stored factor', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
      );
      await tester.pumpAndSettle();
      // 1,000,000 is the stored value and useless to read. `1 kg = 1,000 g` is the figure — and dividing by
      // `milliPerBaseUnit` rather than by 1,000 is the whole of ARCH_4 R18.
      expect(find.textContaining('1,000'), findsOneWidget);
      expect(find.textContaining('1,000,000'), findsNothing);
    });

    testWidgets('the fixed-categories rule is stated before anybody adds one', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const UnitsSettingsScreen(),
        overrides: settingsOverrides(units: AsyncValue.data([unit()])),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('only three kinds'), findsOneWidget);
    });
  });

  group('currencies', () {
    testWidgets('the home currency cannot be switched off', (tester) async {
      await pumpSettings(
        tester,
        const CurrenciesSettingsScreen(),
        overrides: settingsOverrides(
          currencies: AsyncValue.data([
            currency(),
            currency(code: 'JPY', isEnabled: false),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      final tiles = tester
          .widgetList<SwitchListTile>(find.byType(SwitchListTile))
          .toList();
      // Disabled rather than hidden, so it reads as an explanation and not a rendering fault (ARCH_5 §10).
      expect(tiles.first.onChanged, isNull);
      expect(tiles.last.onChanged, isNotNull);
      expect(find.textContaining('Cannot be turned off'), findsOneWidget);
    });
  });

  group('security', () {
    testWidgets('the honest paragraph is on the screen, above the switches', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('does not encrypt your data'), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('auto-erase is off by default and names the threshold', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        overrides: settingsOverrides(lock: FakeAppLock(enabled: true)),
        size: kTallViewport,
      );
      await tester.pumpAndSettle();

      final switches = tester.widgetList<SwitchListTile>(
        find.byType(SwitchListTile),
      );
      // An unset key reads as false, which is what "default off" has to mean for a feature that destroys data.
      expect(switches.every((tile) => tile.value == false), isTrue);
      expect(find.textContaining('10 wrong PIN attempts'), findsOneWidget);
    });

    testWidgets('neither PIN branch is guessed while storage answers', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        const SecuritySettingsScreen(),
        // **The provider is overridden to a future that never completes.** `FakeAppLock.isEnabled` is an
        // `async` getter, so it resolves within the first frame's microtask drain and the loading branch is
        // never observable — the test would have passed against a screen that had no loading branch at all.
        overrides: [
          ...settingsOverrides(lock: FakeAppLock(enabled: true)),
          lockConfiguredProvider.overrideWith((ref) => pendingFuture<bool>()),
        ],
      );
      expect(find.text('Checking…'), findsOneWidget);
      // A row saying "no PIN set" for one frame to somebody who has one would be alarming for the wrong reason.
      expect(find.text('Set a PIN'), findsNothing);
    });
  });
}
```
