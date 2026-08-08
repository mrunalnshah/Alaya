import 'package:alaya/core/time/clock.dart';

/// The `(createdAt, updatedAt)` pair to write for a save, and the one place that pair is
/// computed for every repository in this phase.
///
/// **Exists to prevent a real, easy-to-make bug.** Drift's `insertOnConflictUpdate` writes
/// every column present in the companion on conflict, `createdAt` included — passing `now` for
/// both timestamps on every save silently overwrites a row's true creation time on its second
/// edit. Verified against SQLite: a naive upsert corrupts `created_at` from its original value
/// to whatever the second call happened to pass. The fix is to read the existing row first and
/// thread its `createdAt` through unchanged; every `save()` in this phase does that via this one
/// function rather than reimplementing the read-then-decide logic eight times.
final class WriteTimestamps {
  const WriteTimestamps._();

  /// Resolves the pair to write, given [existingCreatedAt] (null when this is a fresh insert)
  /// and [clock] for the current instant.
  ///
  /// `createdAt` is [existingCreatedAt] when present, otherwise now — so a first save and every
  /// later save of the same row agree on when it was created. `updatedAt` is always now.
  static ({int createdAt, int updatedAt}) resolve({
    required int? existingCreatedAt,
    required Clock clock,
  }) {
    final now = clock.nowUtcMillis();
    return (createdAt: existingCreatedAt ?? now, updatedAt: now);
  }
}