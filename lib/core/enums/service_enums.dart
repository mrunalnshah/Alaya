/// What kind of durable, serviceable thing (or person) an Asset represents.
enum AssetType {
  /// A home appliance (fridge, washing machine, ...).
  appliance,

  /// A consumer electronics item (TV, laptop, phone, ...).
  electronics,

  /// A car, motorbike, or other vehicle.
  vehicle,

  /// Furniture.
  furniture,

  /// A property (house, flat, land, ...).
  property,

  /// A person providing an ongoing service (e.g. a house maid), tracked the same way as a
  /// physical asset so a single system covers both — see ARCH_2 §8.1.
  serviceProvider,

  /// A non-physical recurring subscription tracked here for its service history rather than
  /// only as a Recurring Template.
  subscription,

  /// Anything not covered by the above.
  other,
}

/// The current lifecycle state of an Asset. There is no "deleted" state — disposal is a
/// status change with a reason, never a delete (ARCH_3 §4.1).
enum AssetStatus {
  /// In normal use.
  active,

  /// Temporarily out of service, e.g. sent for repair.
  underRepair,

  /// No longer owned/in use. See [AssetDisposalReason] for why.
  disposed,
}

/// Why an Asset was disposed. Recorded so its purchase history and cost remain in analytics
/// even after disposal.
enum AssetDisposalReason {
  /// Sold to someone else.
  sold,

  /// Reached the end of its usable/warranty life.
  expired,

  /// Broken beyond economical repair.
  damaged,

  /// Given away.
  gifted,

  /// Lost or stolen.
  lost,

  /// Replaced by a newer Asset.
  replaced,

  /// Anything not covered by the above.
  other,
}

/// What kind of event a [ServiceRecord] represents.
enum ServiceRecordType {
  /// A routine service visit.
  service,

  /// A repair for a specific fault.
  repair,

  /// General maintenance not tied to a specific fault.
  maintenance,

  /// An inspection or checkup with no work performed.
  inspection,

  /// A salary payment to a [AssetType.serviceProvider] asset (e.g. a house maid).
  salaryPaid,

  /// Anything not covered by the above.
  other,
}