/// A rough classification of what a Recurring Template represents, for grouping and
/// iconography.
enum RecurringKind {
  /// A recurring bill (electricity, water, ...).
  bill,

  /// A recurring subscription (streaming, software, ...).
  subscription,

  /// Rent, paid or received.
  rent,

  /// Salary, paid or received.
  salary,

  /// A recurring fee for a service (e.g. a house maid's monthly payment).
  serviceFee,

  /// Anything not covered by the above.
  other,
}

/// Which way money moves when a Recurring Template's occurrence is settled. This is what
/// lets salary live in the same system as bills, rather than needing a second, parallel
/// mechanism (ARCH_1 §3.2).
enum RecurringDirection {
  /// Settling an occurrence creates a withdrawal (a bill, a subscription, ...).
  outflow,

  /// Settling an occurrence creates a deposit (salary, recurring income, ...).
  inflow,
}

/// The unit a Recurring Template's repeat interval is counted in.
enum RecurringIntervalUnit {
  /// Every N days.
  day,

  /// Every N weeks.
  week,

  /// Every N months, anchored to a day-of-month that is clamped (never mutated) at render
  /// time for short months — see ARCH_2 §7.1.
  month,

  /// Every N years.
  year,
}

/// The settlement state of one dated instance of a Recurring Template. `due` past its date
/// renders as overdue — a derived state, never stored separately.
enum RecurringOccurrenceStatus {
  /// Materialised but not yet acted on.
  due,

  /// Settled — money moved and is linked back via `paidTransactionId`.
  paid,

  /// The user explicitly chose not to pay this occurrence.
  skipped,

  /// The user dismissed this occurrence without it ever being due in a meaningful sense
  /// (e.g. a template was paused retroactively).
  dismissed,
}