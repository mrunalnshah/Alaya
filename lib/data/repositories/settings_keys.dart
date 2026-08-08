/// Well-known `app_settings` keys shared across repository implementations.
///
/// Exists so no repository impl needs to import another impl's file just to reference a key
/// string — `SettingsRepositoryImpl` and `TransactionRepositoryImpl` both use
/// [lastUsedAccountId], and importing one implementation class from another for a constant is
/// the kind of coupling this file avoids, even though nothing here touches Law L12 (both are
/// `data/`, so no layering rule is actually at stake — it is a design smell, not a violation).
abstract final class SettingsKeys {
  const SettingsKeys._();

  /// The user's chosen display currency for aggregated totals (Law L9 — display only). Seeded
  /// by Phase 1C on first launch.
  static const String homeCurrencyCode = 'homeCurrencyCode';

  /// The account quick-add falls back to when no last-used account is known. Seeded by Phase 1C
  /// on first launch.
  static const String defaultAccountId = 'defaultAccountId';

  /// The account `TransactionRepositoryImpl.create` writes after a successful save, and reads
  /// back to resolve quick-add's account (ARCH_2 §4.1). Absent until the first transaction is
  /// created — not part of Phase 1C's seed data.
  static const String lastUsedAccountId = 'lastUsedAccountId';
}