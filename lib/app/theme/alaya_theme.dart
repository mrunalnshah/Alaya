import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/app/theme/palettes/presets.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_radii.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Turns a palette plus the tokens into light and dark `ThemeData` (ARCH_3 §8).
///
/// Every component theme is configured here rather than left to Material's defaults, because a
/// default is a colour and a radius chosen by someone who had not seen this palette. Leaving them
/// unset is how an app ends up with a purple ripple on an indigo button.
abstract final class AlayaTheme {
  /// The light theme for [palette], defaulting to the active preset.
  static ThemeData light([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: false);

  /// The dark theme for [palette], defaulting to the active preset.
  static ThemeData dark([AlayaPalette palette = AlayaPresets.activePreset]) =>
      _build(palette: palette, isDark: true);

  static ThemeData _build({
    required AlayaPalette palette,
    required bool isDark,
  }) {
    final colors = palette.forMode(isDark: isDark);
    final scheme = _scheme(colors, isDark: isDark);
    final text = _textTheme(colors);

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: colors.surfaceBase,
      canvasColor: colors.surfaceBase,
      dividerColor: colors.divider,
      textTheme: text,
      // Splash and highlight derive from the accent rather than Material's default ink, so a tap
      // never flashes a colour that is not in the palette.
      splashColor: colors.accent.withValues(alpha: 0.10),
      highlightColor: colors.accent.withValues(alpha: 0.06),
      extensions: [AlayaSemanticColors.fromColorSet(colors)],
      visualDensity: VisualDensity.standard,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surfaceBase,
        foregroundColor: colors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AlayaTypography.screenTitle.copyWith(
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.sm,
          vertical: AlayaSpacing.sm,
        ),
        border: const OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.accent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AlayaRadii.borderSm,
          borderSide: BorderSide(color: colors.danger, width: 2),
        ),
        labelStyle: AlayaTypography.label.copyWith(color: colors.textSecondary),
        floatingLabelStyle: AlayaTypography.label.copyWith(
          color: colors.accent,
        ),
        hintStyle: AlayaTypography.body.copyWith(color: colors.textMuted),
        errorStyle: AlayaTypography.caption.copyWith(color: colors.danger),
        prefixIconColor: colors.textSecondary,
        suffixIconColor: colors.textSecondary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          disabledBackgroundColor: colors.surfaceSunken,
          disabledForegroundColor: colors.textMuted,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.primary,
          side: BorderSide(color: colors.divider),
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.lg),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.accent,
          minimumSize: const Size(0, AlayaSpacing.minTapTarget),
          padding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.sm),
          textStyle: AlayaTypography.button,
          shape: const RoundedRectangleBorder(
            borderRadius: AlayaRadii.borderSm,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colors.accent,
        foregroundColor: colors.onAccent,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderMd),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSunken,
        selectedColor: colors.primary,
        disabledColor: colors.surfaceSunken,
        labelStyle: AlayaTypography.overline.copyWith(
          color: colors.textSecondary,
        ),
        secondaryLabelStyle: AlayaTypography.overline.copyWith(
          color: colors.onPrimary,
        ),
        side: BorderSide(color: colors.divider),
        padding: const EdgeInsets.symmetric(
          horizontal: AlayaSpacing.xs,
          vertical: AlayaSpacing.xxs,
        ),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.sheetTop),
        showDragHandle: true,
        dragHandleColor: colors.divider,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceOverlay,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderLg),
        titleTextStyle: AlayaTypography.cardTitle.copyWith(
          color: colors.textPrimary,
        ),
        contentTextStyle: AlayaTypography.body.copyWith(
          color: colors.textSecondary,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(AlayaRadii.lg),
            bottomRight: Radius.circular(AlayaRadii.lg),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        titleTextStyle: AlayaTypography.body.copyWith(
          color: colors.textPrimary,
        ),
        subtitleTextStyle: AlayaTypography.caption.copyWith(
          color: colors.textSecondary,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AlayaSpacing.md),
        minVerticalPadding: AlayaSpacing.xs,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.surfaceOverlay,
        contentTextStyle: AlayaTypography.body.copyWith(
          color: colors.textPrimary,
        ),
        actionTextColor: colors.accent,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderSm),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.accent,
        linearTrackColor: colors.surfaceSunken,
        circularTrackColor: colors.surfaceSunken,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onAccent
              : colors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : colors.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.all(colors.divider),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.accent
              : Colors.transparent,
        ),
        checkColor: WidgetStateProperty.all(colors.onAccent),
        side: BorderSide(color: colors.divider, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: AlayaRadii.borderXs),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textMuted,
        labelStyle: AlayaTypography.bodyEmphasis,
        unselectedLabelStyle: AlayaTypography.body,
        indicatorColor: colors.accent,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: colors.divider,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        indicatorColor: colors.accent.withValues(alpha: 0.14),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.all(
          AlayaTypography.overline.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.accent
                : colors.textMuted,
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.surfaceOverlay,
          borderRadius: AlayaRadii.borderXs,
          border: Border.all(color: colors.divider),
        ),
        textStyle: AlayaTypography.caption.copyWith(color: colors.textPrimary),
        waitDuration: AlayaDurations.slow,
      ),
      iconTheme: IconThemeData(color: colors.textSecondary, size: 22),
    );
  }

  static ColorScheme _scheme(AlayaColorSet colors, {required bool isDark}) =>
      ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primary,
        onPrimary: colors.onPrimary,
        secondary: colors.accent,
        onSecondary: colors.onAccent,
        error: colors.danger,
        onError: colors.onStatus,
        surface: colors.surfaceBase,
        onSurface: colors.textPrimary,
        surfaceContainerLowest: colors.surfaceSunken,
        surfaceContainerLow: colors.surfaceBase,
        surfaceContainer: colors.surfaceRaised,
        surfaceContainerHigh: colors.surfaceRaised,
        surfaceContainerHighest: colors.surfaceOverlay,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.divider,
        outlineVariant: colors.divider,
      );

  /// The Material `TextTheme`, mapped from the app's semantic scale.
  ///
  /// Material's slots exist because framework widgets read them; the app's own widgets use
  /// `AlayaTypography` directly. Mapping both ways round would give two names for one style, so the
  /// rule is: framework widgets get this, Alaya widgets get the token.
  static TextTheme _textTheme(AlayaColorSet colors) {
    final primary = colors.textPrimary;
    final secondary = colors.textSecondary;
    return TextTheme(
      displayLarge: AlayaTypography.displayAmount.copyWith(color: primary),
      displayMedium: AlayaTypography.amountLarge.copyWith(color: primary),
      headlineSmall: AlayaTypography.screenTitle.copyWith(color: primary),
      titleLarge: AlayaTypography.screenTitle.copyWith(color: primary),
      titleMedium: AlayaTypography.cardTitle.copyWith(color: primary),
      titleSmall: AlayaTypography.label.copyWith(color: secondary),
      bodyLarge: AlayaTypography.body.copyWith(color: primary),
      bodyMedium: AlayaTypography.body.copyWith(color: primary),
      bodySmall: AlayaTypography.caption.copyWith(color: secondary),
      labelLarge: AlayaTypography.button.copyWith(color: primary),
      labelMedium: AlayaTypography.label.copyWith(color: secondary),
      labelSmall: AlayaTypography.overline.copyWith(color: secondary),
    );
  }
}
