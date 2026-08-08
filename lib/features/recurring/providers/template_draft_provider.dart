/// The one-shot channel a module uses to hand the template builder a starting point.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/core/money/money.dart';

/// A template another module has prepared for the user to finish.
class TemplateDraft {
  /// Creates a draft.
  const TemplateDraft({required this.name, this.amount});

  /// What to call it — a transaction line's description, usually.
  final String name;

  /// What it cost this time, offered as the usual amount.
  final Money? amount;
}

/// A draft waiting to be picked up by the next new-template builder.
///
/// **Set immediately before pushing the builder, consumed by its first load, then cleared.** A line
/// marked "Make it recurring" carries a name and an amount but no interval and no anchor — a receipt
/// cannot know how often something repeats, and inventing monthly-on-the-1st would create an
/// obligation nobody agreed to. So the line hands over what it knows and the user supplies the rest.
///
/// `take()` makes the one-shot explicit rather than leaving a stale draft to ambush the next blank
/// builder — the same reason `transactionDraftProvider` works this way.
final templateDraftProvider =
    NotifierProvider<TemplateDraftNotifier, TemplateDraft?>(
      TemplateDraftNotifier.new,
    );

/// Holds at most one pending draft.
class TemplateDraftNotifier extends Notifier<TemplateDraft?> {
  @override
  TemplateDraft? build() => null;

  /// Offers a draft to the next builder that opens.
  void offer(TemplateDraft draft) => state = draft;

  /// Returns the pending draft and clears it, so it is never applied twice.
  TemplateDraft? take() {
    final draft = state;
    state = null;
    return draft;
  }
}
