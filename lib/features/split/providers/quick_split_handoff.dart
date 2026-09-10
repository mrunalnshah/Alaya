/// Carrying a quick split through to the full screen (ARCH_5 U19).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';

/// A split worked out on the home card, on its way to being named and saved.
typedef QuickSplit = ({Money total, int people, bool iPaid});

/// Hands a quick split from the home card to [SplitBillScreen].
///
/// **A provider rather than `GoRouterState.extra`, and the reason is testability.** `extra` is
/// `Object?` — the receiving builder casts and hopes — while this is typed at both ends and can be
/// overridden in a widget test without a router at all.
///
/// **Read once and cleared**, so returning to the bill screen later does not silently repopulate it
/// with a bill from an hour ago. The clear happens in the reader, not the writer, because only the
/// reader knows it has been consumed.
final quickSplitHandoffProvider =
    NotifierProvider<QuickSplitHandoff, QuickSplit?>(QuickSplitHandoff.new);

/// Holds at most one pending quick split.
class QuickSplitHandoff extends Notifier<QuickSplit?> {
  @override
  QuickSplit? build() => null;

  /// Stores [split] for the next screen to pick up.
  void offer(QuickSplit split) => state = split;

  /// Returns the pending split and forgets it.
  QuickSplit? take() {
    final pending = state;
    state = null;
    return pending;
  }
}
