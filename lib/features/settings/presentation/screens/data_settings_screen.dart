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
