/// View-model state for the analytics screens (ARCH_5 U19).
///
/// **Nothing here declares a repository or an engine.** The range, the resolved window, the display
/// precision and the cache action are screen state; `analyticsServiceProvider`,
/// `analyticsCacheServiceProvider` and every repository live in `lib/app/providers/` and are watched
/// from here (ARCH_1 §7.3, Law U19).
library;

import 'dart:async';

import 'package:alaya/core/time/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:alaya/app/providers/infrastructure_providers.dart';
import 'package:alaya/app/providers/repository_providers.dart';
import 'package:alaya/app/providers/service_providers.dart';
import 'package:alaya/core/enums/date_range_preset.dart';
import 'package:alaya/core/time/date_key.dart';
import 'package:alaya/domain/services/analytics/analytics_types.dart';
import 'package:alaya/features/analytics/state/analytics_range.dart';

/// The window every figure on the analytics screen is bounded by, restored from `app_settings`.
final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, DateRangePreset>(
      AnalyticsRangeNotifier.new,
    );

/// Holds and persists the chosen reporting window.
///
/// The same shape as 6F's `InsightSideNotifier`: a synchronous default so the first frame has a
/// window, then an unawaited restore. A `FutureProvider` here would make every chart on the screen
/// wait on a settings read to learn which month it is showing.
class AnalyticsRangeNotifier extends Notifier<DateRangePreset> {
  @override
  DateRangePreset build() {
    unawaited(_restore());
    return AnalyticsRange.fallback;
  }

  Future<void> _restore() async {
    final stored = await ref
        .read(settingsRepositoryProvider)
        .readValue(AnalyticsRange.settingsKey);
    final restored = AnalyticsRange.parse(stored);
    if (restored != state) state = restored;
  }

  /// Shows [preset] and remembers it.
  ///
  /// The write is not awaited: the charts should recompute on the frame the chip is tapped, and a
  /// settings row landing a millisecond later changes nothing the reader can see.
  void show(DateRangePreset preset) {
    state = preset;
    unawaited(
      ref
          .read(settingsRepositoryProvider)
          .writeValue(
            key: AnalyticsRange.settingsKey,
            value: AnalyticsRange.stored(preset),
            valueType: 'string',
          ),
    );
  }
}

/// The chosen preset resolved against today.
///
/// **`DateRange` and `AnalyticsWindow` are the same record type** — both are
/// `({DateKey from, DateKey to})` — so this needs no conversion and none is written. They are
/// declared separately because `DateRangeService` and the analytics layer were built in different
/// phases, and Dart's structural records make that free rather than a mapping to maintain.
///
/// `resolve` returns null only for [DateRangePreset.custom], which `AnalyticsRange.presets` does not
/// offer; the fallback covers a preset restored from a future version's settings row.
final analyticsWindowProvider = Provider<AnalyticsWindow>((ref) {
  final today = ref.watch(clockProvider).today();
  final preset = ref.watch(analyticsRangeProvider);
  final service = ref.watch(dateRangeServiceProvider);
  return service.resolve(preset, today) ??
      service.resolve(AnalyticsRange.fallback, today)!;
});

/// The window immediately before [analyticsWindowProvider], for a period-over-period comparison.
///
/// `precedingWindowOf` rather than `previousWholeMonth`: the honest comparison for "last 30 days" is
/// the 30 days before those, not a calendar month of a different length.
final analyticsPreviousWindowProvider = Provider<AnalyticsWindow>((ref) {
  return ref
      .watch(dateRangeServiceProvider)
      .precedingWindowOf(ref.watch(analyticsWindowProvider));
});

/// The home currency every converted figure is expressed in.
final analyticsCurrencyProvider = FutureProvider<String>((ref) async {
  return await ref.watch(settingsRepositoryProvider).readHomeCurrencyCode() ??
      analyticsFallbackHomeCurrencyCode;
});

/// The home currency's minor-unit precision (ARCH_1 §4.1).
///
/// Read rather than assumed, because `AmountText` defaults to 2 and JPY has none — rendering
/// `¥1,200.00` is wrong, and hardcoding `100` anywhere is what the `currencies` table exists to
/// prevent.
final analyticsDigitsProvider = FutureProvider<int>((ref) async {
  final code = await ref.watch(analyticsCurrencyProvider.future);
  final currency = await ref.watch(currencyRepositoryProvider).byCode(code);
  return currency?.decimalDigits ?? 2;
});

/// One named currency's minor-unit precision.
///
/// **Needed because not every figure on this screen is in the home currency.** A balance trend stays in
/// its account's own currency — converting each point at its own date would make the line move when
/// rates moved rather than when money did — and rendering a yen balance with the home currency's two
/// digits would print `¥1,200.00` for `¥1,200`. `AmountText` defaults to 2 and says a screen holding
/// the currency should pass the real value; this is how it gets it.
final analyticsDigitsForCurrencyProvider = FutureProvider.autoDispose
    .family<int, String>((ref, currencyCode) async {
      final currency = await ref
          .watch(currencyRepositoryProvider)
          .byCode(currencyCode);
      return currency?.decimalDigits ?? 2;
    });

/// How many amounts currently cannot be converted into the home currency.
///
/// The stream Phase 7B implemented over `UnconvertedCounter`; it was `Stream.value(0)` until this
/// phase (ARCH_3 §1.5, ARCH_5 §7.3). Watched here so the screen's header can report a partial total
/// once, rather than every card repeating the same caveat.
final analyticsUnconvertedProvider = StreamProvider<int>(
  (ref) => ref.watch(currencyRepositoryProvider).watchUnconvertedCount(),
);

/// Clears the memoised analytics results and reports the outcome.
///
/// **This is the whole of `analytics_cache`'s user-facing surface** (ARCH_5 §7.1, §7.3: "invisible by
/// design; only 'clear cache' ever surfaces").
///
/// ARCH_5 §7.1 assigns the control to Settings, and Settings is a `PlaceholderScreen` until Phase 8A
/// — so it ships on the analytics screen itself, as a quiet row after the figures in the manner of
/// archetype E's destructive actions. It could not go in the app bar: `Routes.insights` is a shell
/// destination and the app bar belongs to `_ShellScaffold`, so an action added there would appear on
/// all nine destinations. Phase 8A's Settings entry must call this same notifier rather than the
/// service directly (Law U22).
final analyticsCacheControllerProvider =
    NotifierProvider<AnalyticsCacheController, AsyncValue<DateKey?>>(
      AnalyticsCacheController.new,
    );

/// Owns the clear-cache action and the date it last succeeded on.
///
/// The state is an `AsyncValue` so the row can disable itself while clearing and render the
/// repository's own message on failure (Laws U4, U9) — not because the value itself is fetched.
class AnalyticsCacheController extends Notifier<AsyncValue<DateKey?>> {
  @override
  AsyncValue<DateKey?> build() => const AsyncData<DateKey?>(null);

  /// Invalidates every cached result, then recomputes what is on screen.
  ///
  /// Returns whether it succeeded, so the caller can choose between a result snack and a failure
  /// snack; the message stays in [state] for the row to render in place.
  ///
  /// **Coarse by design.** `AnalyticsCacheService.invalidateOnWrite` drops everything rather than
  /// tracking which of the twenty-four queries a row touches — that dependency graph is a thing to
  /// maintain and get wrong, and recomputing on the next open is cheap by comparison.
  Future<bool> clear() async {
    state = const AsyncLoading<DateKey?>();
    try {
      await ref.read(analyticsCacheServiceProvider).invalidateOnWrite();
      state = AsyncData<DateKey?>(ref.read(clockProvider).today());
      // Dropping the rows is not enough on its own: a provider that already resolved is holding the
      // figure it computed, and without this the screen would show the same numbers over an empty
      // cache and the action would look like it did nothing (Law U9).
      ref.invalidate(analyticsServiceProvider);
      return true;
    } catch (error, stackTrace) {
      // The service swallows its own read and write failures, so reaching here means the delete
      // itself failed. Surfaced rather than ignored: the alternative is a button that silently does
      // nothing, which U9 calls the worst outcome available.
      state = AsyncError<DateKey?>(error, stackTrace);
      return false;
    }
  }
}
