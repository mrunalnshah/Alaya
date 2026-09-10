/// How a transaction moves money — which side gains, which side loses. See ARCH_1 §3.1.
/// Stored as `TEXT` via [SafeEnumConverter]; member names are a schema contract (Law L13).
enum TransactionKind {
  /// Money enters an account from outside it (salary, gift, refund, ...).
  deposit,

  /// Money leaves an account to outside it (grocery, bills, ...).
  withdrawal,

  /// Money moves between two of the user's own accounts. Never counted as income or
  /// expense — see `v_account_ledger` in ARCH_2 §12.1.
  transfer,

  /// A manual correction that increases a balance (e.g. reconciling an opening balance).
  adjustmentIncrease,

  /// A manual correction that decreases a balance.
  adjustmentDecrease,
}

/// The structural flow subtype of a transaction: decides which editor form appears and
/// which analytics bucket the transaction lands in. Distinct from a [Tag], which is an
/// open, user-defined label — see ARCH_1 §3.1 for why both exist.
enum TransactionSubtype {
  /// A grocery withdrawal; its lines may fan out into Inventory.
  grocery,

  /// A household-item withdrawal; its lines may fan out into Inventory.
  household,

  /// An electronics withdrawal; its lines may fan out into the Service Manager as an Asset.
  electronics,

  /// A bill payment, optionally linked to a Recurring Template.
  bill,

  /// A transfer to one of the user's own other accounts. Kind is `transfer`.
  transferSelf,

  /// A payment to someone else framed as "transfer" in the UI. Kind is `withdrawal`.
  transferOut,

  /// Recurring income such as salary. Kind is `deposit`.
  salaryIn,

  /// Any other deposit not covered by a more specific subtype.
  otherIn,

  /// Any other withdrawal not covered by a more specific subtype.
  otherOut,
}

/// What a container of money is, for display grouping and iconography.
enum AccountKind {
  /// Physical cash on hand.
  cash,

  /// A bank account.
  bank,

  /// A digital wallet (e.g. Paytm, Google Pay balance).
  wallet,

  /// A credit or debit card treated as its own balance-holding container.
  card,

  /// Anything not covered by the above.
  other,
}

/// The rail money travelled on. Carries no balance of its own — see [AccountKind] for that.
enum PaymentMethodKind {
  /// Physical cash handed over.
  cash,

  /// UPI (or an equivalent real-time payment rail).
  upi,

  /// A bank transfer (NEFT/IMPS/wire/ACH or equivalent).
  bankTransfer,

  /// A credit or debit card swipe/tap.
  card,

  /// A paper cheque.
  cheque,

  /// A digital wallet payment.
  wallet,

  /// Anything not covered by the above; the user's own custom rail.
  other,
}

/// The counterparty on a transaction — used for both `From` (deposits) and `To`
/// (withdrawals).
enum PayeeKind {
  /// An individual (friend, family member, tenant, ...).
  person,

  /// A shop or business.
  merchant,

  /// The user's employer, for salary deposits.
  employer,

  /// A utility or service company (electricity, telecom, ...).
  utility,

  /// Anything not covered by the above.
  other,

  /// A participant on a split whom nobody has named yet.
  ///
  /// **Not a person, and that distinction is the whole point.** `split_shares.payee_id` is
  /// `NOT NULL REFERENCES payees(id)`, so saving a split with an unnamed participant needs a payee row
  /// to exist — without one the split cannot be saved at all, which is friction charged at the moment
  /// everybody is standing up to leave the restaurant.
  ///
  /// The first attempt made those rows ordinary [person] entries called "Person 4". They worked, and
  /// they accumulated in Settings › Payees beside real contacts, which is not a trade anybody agreed
  /// to. This kind keeps the row where balances need it and out of every list where it would be noise.
  ///
  /// **Adding a member needs no migration.** `SafeEnumConverter` stores an enum by its `name`, and
  /// nothing reads `PayeeKind` by ordinal — which is exactly why Law L13 forbids *renaming* a member
  /// while adding one is free.
  ///
  /// Naming a placeholder writes `kind: person` and the real name in one update. There is no flag to
  /// clear, so a flag and a name can never disagree.
  splitPlaceholder,
}

/// What a [TransactionLine] produced elsewhere in the app, if anything. A line produces at
/// most one artefact, recorded by whichever `created*Id` column matches this value.
enum TransactionLineDestination {
  /// This line created nothing beyond itself.
  none,

  /// This line created (or added a batch to) an Inventory Item.
  inventory,

  /// This line created a Service Manager Asset.
  asset,

  /// This line created a Recurring Template.
  recurring,
}
