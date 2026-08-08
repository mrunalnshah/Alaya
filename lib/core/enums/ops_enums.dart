/// What kind of event a scheduled local notification is for. Paired with a stable Android
/// notification id in `notification_schedule` so it can be cancelled when the underlying
/// record changes (ARCH_3 §7).
enum NotificationKind {
  /// An inventory batch is approaching (or has passed) its expiry date.
  expiry,

  /// An Asset's next service is due.
  serviceDue,

  /// A Recurring Template's occurrence is due.
  recurringDue,

  /// An Item has fallen below its low-stock threshold.
  lowStock,

  /// An Asset's warranty is ending soon.
  warrantyEnd,
}

/// The lifecycle state of one scheduled local notification.
enum NotificationStatus {
  /// Scheduled with the OS but not yet fired.
  scheduled,

  /// Already delivered.
  fired,

  /// Cancelled before firing, e.g. because the underlying record was deleted or resolved.
  cancelled,
}

/// How a backup was produced, recorded in `backup_history` for the user's own reference.
enum BackupKind {
  /// Explicitly triggered by the user.
  manual,

  /// Produced by a scheduled background job.
  auto,
}