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
