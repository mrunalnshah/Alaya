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
