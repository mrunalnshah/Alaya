import 'dart:async';

import 'package:flutter/material.dart';

import 'package:alaya/app/theme/tokens/alaya_durations.dart';
import 'package:alaya/app/theme/tokens/alaya_icon_size.dart';
import 'package:alaya/app/theme/tokens/alaya_typography.dart';

/// The search input for every catalogue screen (ARCH_5 §3 archetype D).
///
/// **A visible field rather than a magnifying glass in the app bar.** Catalogues in this app are
/// searched constantly — an item you are about to consume, an asset you are about to service — and
/// hiding the field behind a tap costs an interaction every single time.
///
/// Debounced through [AlayaDurations.debounce] so a query does not run per keystroke, and the timer
/// is cancelled on dispose so a pending callback cannot fire into a disposed widget.
class AlayaSearchField extends StatefulWidget {
  /// Creates a search field reporting through [onChanged].
  const AlayaSearchField({
    required this.onChanged,
    required this.clearLabel,
    this.hintText,
    this.initialValue,
    this.autofocus = false,
    super.key,
  });

  /// Called with the trimmed query once typing settles, and immediately on clear.
  final ValueChanged<String> onChanged;

  /// Accessibility label for the clear button, already localised.
  final String clearLabel;

  /// Placeholder text, already localised.
  final String? hintText;

  /// A starting query, for a screen restoring its state.
  final String? initialValue;

  /// Whether to focus on mount. False on a list screen — a keyboard the user did not ask for
  /// covers the content they came to read.
  final bool autofocus;

  @override
  State<AlayaSearchField> createState() => _AlayaSearchFieldState();
}

class _AlayaSearchFieldState extends State<AlayaSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue ?? '',
  );
  Timer? _debounce;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
  }

  void _handleChanged(String raw) {
    final nowHasText = raw.isNotEmpty;
    if (nowHasText != _hasText) setState(() => _hasText = nowHasText);
    _debounce?.cancel();
    _debounce = Timer(
      AlayaDurations.debounce,
      () => widget.onChanged(raw.trim()),
    );
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _hasText = false);
    // Immediate rather than debounced: clearing is a decision, not a keystroke on the way to one.
    widget.onChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: widget.autofocus,
    textInputAction: TextInputAction.search,
    style: AlayaTypography.body,
    decoration: InputDecoration(
      hintText: widget.hintText,
      prefixIcon: const Icon(Icons.search, size: AlayaIconSize.md),
      suffixIcon: _hasText
          ? IconButton(
              icon: const Icon(Icons.close, size: AlayaIconSize.md),
              tooltip: widget.clearLabel,
              onPressed: _clear,
            )
          : null,
    ),
    onChanged: _handleChanged,
  );
}
