import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:alaya/app/l10n/generated/app_localizations.dart';
import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';
import 'package:alaya/shared/feedback/undo_snack.dart';

/// A name, a number, and a button that dials it.
///
/// **The only outbound action in the app, and it reports its own failure.** `launchUrl` returns false
/// when no handler exists for `tel:` — a tablet without a dialler, or a restricted profile — and a
/// button that silently does nothing is worse than one that says why (Law U9).
///
/// The number is rendered as plain selectable text beside the action so it stays useful when the call
/// cannot be placed at all.
class ContactAction extends StatelessWidget {
  /// Creates the block.
  const ContactAction({required this.phone, this.name, super.key});

  /// The number to dial.
  final String phone;

  /// Who answers, if known.
  final String? name;

  Future<void> _call(BuildContext context) async {
    final strings = AlayaStrings.of(context);
    // `Uri(scheme:, path:)` rather than a parsed string: a number containing spaces or a leading plus
    // is common and `Uri.parse('tel:+91 98…')` mangles it.
    final launched = await launchUrl(Uri(scheme: 'tel', path: phone));
    if (launched || !context.mounted) return;
    showFailureSnack(context, message: strings.callFailed);
  }

  @override
  Widget build(BuildContext context) {
    final strings = AlayaStrings.of(context);
    final semantic = context.semantic;
    final who = name;

    // A `Wrap`: the name, the number and the button all grow with text scale, and a `Row` would starve
    // whichever came first at 320dp (Law U21).
    return Wrap(
      spacing: AlayaSpacing.xs,
      runSpacing: AlayaSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (who != null && who.isNotEmpty)
          Text(
            who,
            style: AlayaTypography.body.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        // **Plain text, not a selectable widget.** `SelectableText` carries a `longPress` semantics
        // action, so the accessibility sweep counts it as a tap target and fails it at 162x16 — it is
        // 16px tall and cannot be 48 without dwarfing the row. The number is already reachable through
        // the Call button beside it, and long-press-to-copy on a 16px strip was never a real
        // affordance (Law U16).
        Text(
          phone,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _call(context),
          icon: const Icon(Icons.call, size: AlayaIconSize.sm),
          label: Text(strings.actionCall),
        ),
      ],
    );
  }
}
