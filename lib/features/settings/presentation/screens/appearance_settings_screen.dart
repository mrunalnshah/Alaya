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
