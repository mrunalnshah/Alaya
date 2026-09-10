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
