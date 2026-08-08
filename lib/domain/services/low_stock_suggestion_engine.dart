import 'package:alaya/core/enums/shopping_enums.dart';
import 'package:alaya/core/quantity/qty.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/entities/item_stock.dart';
import 'package:alaya/domain/entities/shopping_entry.dart';

/// What the engine decided to do about one item.
enum SuggestionAction {
  /// No auto entry exists and stock is low — create one.
  create,

  /// An active auto entry exists — refresh its quantity and stock reading.
  refresh,

  /// Leave the entry entirely alone.
  ///
  /// Either the user has taken ownership of it (`origin` promoted to `manual`), or they dismissed or
  /// snoozed it and the condition that would bring it back has not been met.
  leaveAlone,
}

/// One decision, ready for the caller to write.
class SuggestionDecision {
  /// Creates a decision.
  const SuggestionDecision({
    required this.itemId,
    required this.action,
    required this.reason,
    this.existingEntryId,
    this.suggestedQuantity,
    this.stockAtDecision,
  });

  /// The item this concerns.
  final String itemId;

  /// What to do.
  final SuggestionAction action;

  /// Why, in words — surfaced in logs and useful when a user asks why something reappeared.
  final String reason;

  /// The entry to update, when [action] is [SuggestionAction.refresh].
  final String? existingEntryId;

  /// How much to buy — the shortfall against the threshold.
  final Qty? suggestedQuantity;

  /// The stock reading at the moment of the decision, stored so a later dismissal can be compared
  /// against it.
  final Qty? stockAtDecision;

  /// True when the caller needs to write something.
  bool get requiresWrite => action != SuggestionAction.leaveAlone;
}

/// Decides which low-stock shopping suggestions should exist.
///
/// **Pure and idempotent.** Given the same stock and the same existing entries it returns the same
/// decisions, however many times it runs — which is what makes regeneration safe to call from a
/// foreground hook. The idempotency is a property of this function, not of the database: the partial
/// unique index `idx_shopping_auto` is a backstop, and one that cannot serve as an `ON CONFLICT`
/// target anyway (ARCH_2 §11.1), so correctness has to live here.
///
/// Phase 3C held this inside `ShoppingRepositoryImpl.regenerateLowStockSuggestions`. It lives here
/// now so the rule has one definition and can be tested without a database.
final class LowStockSuggestionEngine {
  /// Creates the engine.
  const LowStockSuggestionEngine();

  /// Decides what to do for every item in [lowStock].
  ///
  /// [existingAutoEntries] should be every entry on the list already keyed to an item, whatever its
  /// origin or state — including ones promoted to `manual`, because those are precisely the ones
  /// that must be recognised and left alone.
  List<SuggestionDecision> decide({
    required Iterable<ItemStock> lowStock,
    required Iterable<ShoppingEntry> existingAutoEntries,
    required DateKey today,
  }) {
    final byItem = <String, ShoppingEntry>{};
    for (final entry in existingAutoEntries) {
      final itemId = entry.itemId;
      if (itemId != null) byItem[itemId] = entry;
    }

    final decisions = <SuggestionDecision>[];
    for (final stock in lowStock) {
      decisions.add(
        _decideFor(stock: stock, existing: byItem[stock.itemId], today: today),
      );
    }
    return decisions;
  }

  SuggestionDecision _decideFor({
    required ItemStock stock,
    required ShoppingEntry? existing,
    required DateKey today,
  }) {
    final shortfall = stock.shortfall;
    if (shortfall == null || !shortfall.isPositive) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Not low on stock, or no threshold set.',
      );
    }

    if (existing == null) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.create,
        reason: 'Low on stock and nothing suggested yet.',
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    // The user has taken ownership. Editing an auto entry promotes its origin, and from that moment
    // the engine never touches it again — not its quantity, not its state (anomaly A22). Any other
    // behaviour would silently overwrite a deliberate edit on the next foreground.
    if (existing.origin != ShoppingEntryOrigin.autoLowStock) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'The user edited this entry, so it is theirs now.',
        existingEntryId: existing.id,
      );
    }

    if (existing.autoState != ShoppingEntryAutoState.active) {
      return _decideSuppressed(
        stock: stock,
        existing: existing,
        today: today,
        shortfall: shortfall,
      );
    }

    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Still low on stock; refreshing the suggested quantity.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }

  /// Whether a dismissed or snoozed suggestion has earned its way back.
  ///
  /// A dismissal is not a timer. Bringing the entry back after N days would nag about a shortage the
  /// user already declined; never bringing it back would mean they stop being told after they
  /// restock and run out again. The condition is therefore the stock itself: it returns only once
  /// stock has risen **above** the reading taken when they dismissed it — which can only happen if
  /// they bought some — and then fallen below the threshold again (anomaly A23).
  ///
  /// A snooze additionally has a date, and that date genuinely is a timer: the user asked to be
  /// reminded later, rather than saying no.
  SuggestionDecision _decideSuppressed({
    required ItemStock stock,
    required ShoppingEntry existing,
    required DateKey today,
    required Qty shortfall,
  }) {
    if (existing.autoState == ShoppingEntryAutoState.snoozed) {
      final until = existing.snoozeUntilDateKey;
      if (until != null && today.isBefore(until)) {
        return SuggestionDecision(
          itemId: stock.itemId,
          action: SuggestionAction.leaveAlone,
          reason: 'Snoozed until ${until.toIso()}.',
          existingEntryId: existing.id,
        );
      }
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.refresh,
        reason: 'The snooze has expired and stock is still low.',
        existingEntryId: existing.id,
        suggestedQuantity: shortfall,
        stockAtDecision: stock.totalRemaining,
      );
    }

    final atDecision = existing.stockAtGeneration;
    if (atDecision == null) {
      // No reading was stored, so the recovery condition cannot be evaluated. Staying suppressed is
      // the safer default: a suggestion that never returns is a missing nudge, whereas one that
      // returns on every foreground is the nag this rule exists to prevent.
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, with no stock reading to compare against.',
        existingEntryId: existing.id,
      );
    }

    final recovered = stock.totalRemaining.milliBase > atDecision.milliBase;
    if (!recovered) {
      return SuggestionDecision(
        itemId: stock.itemId,
        action: SuggestionAction.leaveAlone,
        reason: 'Dismissed, and stock has not been replenished since.',
        existingEntryId: existing.id,
      );
    }
    return SuggestionDecision(
      itemId: stock.itemId,
      action: SuggestionAction.refresh,
      reason: 'Restocked after being dismissed, and low again.',
      existingEntryId: existing.id,
      suggestedQuantity: shortfall,
      stockAtDecision: stock.totalRemaining,
    );
  }
}
