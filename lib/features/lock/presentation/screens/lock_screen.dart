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
