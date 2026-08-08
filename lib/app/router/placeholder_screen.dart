// PLACEHOLDER: PHASE_06
import 'package:flutter/material.dart';

import 'package:alaya/app/theme/semantic_colors.dart';
import 'package:alaya/app/theme/tokens/alaya_spacing.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// Stands in for a feature screen until the phase that owns it lands.
///
/// One parameterised placeholder rather than nine near-identical stub files: nine stubs would each
/// need deleting, and a stub left behind is indistinguishable from a real screen that does nothing.
///
/// It carries no destination name of its own. The surrounding scaffold titles itself from
/// `AlayaDrawer.titleFor`, so every visible name is localised in one place instead of appearing here
/// as a dozen English literals that no translator would ever see.
class PlaceholderScreen extends StatelessWidget {
  /// Creates a placeholder owned by [owningPhase], e.g. `Phase 6A`.
  const PlaceholderScreen({required this.owningPhase, super.key});

  /// The phase that will replace this. Developer text, deliberately not localised.
  final String owningPhase;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AlayaSpacing.xxl),
        child: Text(
          owningPhase,
          style: AlayaTypography.caption.copyWith(color: semantic.muted),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
