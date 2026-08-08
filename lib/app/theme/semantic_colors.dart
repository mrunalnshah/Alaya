import 'package:flutter/material.dart';

import 'package:alaya/app/theme/palettes/palette.dart';
import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/money/money.dart';

/// The app's semantic colours, reachable from any `BuildContext` (ARCH_3 §8).
///
/// A `ThemeExtension` rather than a set of top-level constants, because the palette can change at
/// runtime and a widget holding a `const` colour would not rebuild. Reached through
/// [AlayaSemanticColorsContext.semantic] on the context.
@immutable
class AlayaSemanticColors extends ThemeExtension<AlayaSemanticColors> {
  /// Creates the extension.
  const AlayaSemanticColors({
    required this.income,
    required this.expense,
    required this.transfer,
    required this.warning,
    required this.danger,
    required this.success,
    required this.muted,
    required this.onStatus,
    required this.surfaceBase,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.surfaceSunken,
  });

  /// Builds the extension from one mode of a palette.
  factory AlayaSemanticColors.fromColorSet(AlayaColorSet colors) =>
      AlayaSemanticColors(
        income: colors.income,
        expense: colors.expense,
        transfer: colors.transfer,
        warning: colors.warning,
        danger: colors.danger,
        success: colors.success,
        muted: colors.textMuted,
        onStatus: colors.onStatus,
        surfaceBase: colors.surfaceBase,
        surfaceRaised: colors.surfaceRaised,
        surfaceOverlay: colors.surfaceOverlay,
        surfaceSunken: colors.surfaceSunken,
      );

  /// Money arriving.
  final Color income;

  /// Money leaving.
  final Color expense;

  /// Money moving between the user's own accounts.
  final Color transfer;

  /// Something needs attention soon.
  final Color warning;

  /// Something is wrong or overdue.
  final Color danger;

  /// Something completed.
  final Color success;

  /// De-emphasised — and the colour a zero amount takes.
  final Color muted;

  /// Text and icons on a [warning], [danger] or [success] fill.
  final Color onStatus;

  /// Tier 0 — the screen.
  final Color surfaceBase;

  /// Tier 1 — a card.
  final Color surfaceRaised;

  /// Tier 2 — a sheet or dialog.
  final Color surfaceOverlay;

  /// Tier -1 — an inset well, such as a text field's fill.
  final Color surfaceSunken;

  /// **The red/green rule, implemented exactly once (ARCH_3 §8.1).**
  ///
  /// Every amount in the app takes its colour from this method and no other. That is what makes the
  /// convention uniform by construction rather than by 200 widgets each remembering it — and it is
  /// what makes the convention changeable, since inverting it for a user who reads red as auspicious
  /// is one edit here.
  ///
  /// Zero is [muted], not [income]. A zero amount has no direction, and colouring it green would
  /// assert something the number does not say.
  Color forAmount(Money amount) {
    if (amount.isZero) return muted;
    return amount.isNegative ? expense : income;
  }

  /// The colour for an amount belonging to a transaction of [kind].
  ///
  /// Delegates to [forAmount] for everything except a transfer, which is the one case the amount's
  /// sign cannot express: moving ₹5,000 between your own accounts is neither a gain nor a loss, but
  /// its leg is signed like any other. Colouring it green on the way in and red on the way out would
  /// make one movement of money look like income and expense at once.
  Color forTransactionKind(TransactionKind kind, Money amount) =>
      kind == TransactionKind.transfer ? transfer : forAmount(amount);

  /// The surface colour for [tier] 0 to 2, or -1 for a sunken well.
  Color surfaceForTier(int tier) => switch (tier) {
    -1 => surfaceSunken,
    0 => surfaceBase,
    1 => surfaceRaised,
    _ => surfaceOverlay,
  };

  /// Every semantic colour by name, so the Theme Lab enumerates them without a list to maintain.
  Map<String, Color> get byName => {
    'income': income,
    'expense': expense,
    'transfer': transfer,
    'warning': warning,
    'danger': danger,
    'success': success,
    'muted': muted,
    'surfaceBase': surfaceBase,
    'surfaceRaised': surfaceRaised,
    'surfaceOverlay': surfaceOverlay,
    'surfaceSunken': surfaceSunken,
  };

  @override
  AlayaSemanticColors copyWith({
    Color? income,
    Color? expense,
    Color? transfer,
    Color? warning,
    Color? danger,
    Color? success,
    Color? muted,
    Color? onStatus,
    Color? surfaceBase,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? surfaceSunken,
  }) => AlayaSemanticColors(
    income: income ?? this.income,
    expense: expense ?? this.expense,
    transfer: transfer ?? this.transfer,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    success: success ?? this.success,
    muted: muted ?? this.muted,
    onStatus: onStatus ?? this.onStatus,
    surfaceBase: surfaceBase ?? this.surfaceBase,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
  );

  @override
  AlayaSemanticColors lerp(AlayaSemanticColors? other, double t) {
    if (other == null) return this;
    return AlayaSemanticColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      transfer: Color.lerp(transfer, other.transfer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      success: Color.lerp(success, other.success, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      surfaceBase: Color.lerp(surfaceBase, other.surfaceBase, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceOverlay: Color.lerp(surfaceOverlay, other.surfaceOverlay, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
    );
  }
}

/// Reaches [AlayaSemanticColors] from a `BuildContext`.
extension AlayaSemanticColorsContext on BuildContext {
  /// This context's semantic colours.
  ///
  /// Throws if the extension is absent, which can only happen inside a `MaterialApp` that is not
  /// `AlayaTheme`'s — a programming error worth failing loudly rather than silently falling back to
  /// Material defaults and shipping a screen whose amounts are the wrong colour.
  AlayaSemanticColors get semantic {
    final extension = Theme.of(this).extension<AlayaSemanticColors>();
    assert(
      extension != null,
      'AlayaSemanticColors is missing. Wrap this subtree in AlayaTheme.light or AlayaTheme.dark.',
    );
    return extension ?? AlayaSemanticColors.fromColorSet(_fallback);
  }
}

const AlayaColorSet _fallback = AlayaColorSet(
  surfaceBase: Color(0xFFF6F5F1),
  surfaceRaised: Color(0xFFFFFFFF),
  surfaceOverlay: Color(0xFFFFFFFF),
  surfaceSunken: Color(0xFFECEAE3),
  primary: Color(0xFF2A3A6B),
  onPrimary: Color(0xFFFFFFFF),
  accent: Color(0xFF9A6A1E),
  onAccent: Color(0xFFFFFFFF),
  textPrimary: Color(0xFF1B2033),
  textSecondary: Color(0xFF515873),
  textMuted: Color(0xFF868CA3),
  divider: Color(0xFFDDDAD1),
  income: Color(0xFF2E7D5B),
  expense: Color(0xFF9E2A2B),
  transfer: Color(0xFF4A5578),
  warning: Color(0xFF9A6A1E),
  danger: Color(0xFF9E2A2B),
  success: Color(0xFF2E7D5B),
  onStatus: Color(0xFFFFFFFF),
);
