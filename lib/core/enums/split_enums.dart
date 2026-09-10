/// Enums the split schema stores. Names are a schema contract (Law L13) — renaming a member
/// renames it in every existing row, so a member is added or deprecated, never renamed.
library;

/// How a split expense's shares were specified.
///
/// Recorded on `split_expenses` so the editor can reopen a split the way it was made rather than as
/// a list of amounts the user has to reverse-engineer. A 40/30/30 split must come back as 40/30/30.
enum SplitMethod {
  /// Everyone takes an equal share of the remainder.
  equal,

  /// Each participant's amount was typed directly.
  exactAmounts,

  /// Basis points of the total.
  percent,

  /// Weights against the other weighted participants.
  shares,

  /// Each `transaction_lines` row is split among its own participants.
  ///
  /// Needs the receipt, so it is only available on an expense the user paid for.
  perLine,
}

/// How one participant's share was specified.
///
/// Stored per row on `split_shares` rather than derived from [SplitMethod], because a mixed split is
/// the commonest real instruction: "the drinks were Ravi's, split the rest between us" is one
/// [extra] beside three [equal]s, and the header's method cannot express both.
enum ShareInputKind {
  /// An equal share of whatever is left after exact amounts, extras and percentages.
  equal,

  /// A fixed amount that is this person's **entire** share.
  ///
  /// "Priya owes exactly ₹500, full stop." She takes no part in dividing the remainder.
  exact,

  /// A fixed amount charged to this person **on top of** their equal share of the remainder.
  ///
  /// **The one input the module was missing, and it turns out to be two features.**
  ///
  /// *"Ravi bought his own drinks."* A ₹5,000 dinner where ₹400 of it was Ravi's round: the ₹400 is
  /// his, the remaining ₹4,600 splits four ways, and Ravi pays ₹1,550 while everybody else pays
  /// ₹1,150.
  ///
  /// *"I'll put in ₹2,000 and we'll split the rest."* Identical arithmetic from the other direction —
  /// ₹2,000 is charged to the payer, the remaining ₹3,000 splits four ways, and the payer's total is
  /// ₹2,750.
  ///
  /// The difference from [exact] is the whole point: an exact amount **replaces** a person's share,
  /// an extra **adds to** it. Getting that wrong is how an app tells four people they owe ₹400 each
  /// for one person's drinks.
  ///
  /// A participant with an extra takes a **weight of one** in the remainder. Combining an extra with
  /// a custom weight is deliberately not expressible: it is a fourth way to describe the same bill
  /// and this module's stated purpose is splitting simply.
  extra,

  /// Basis points of the **total** — 2500 is 25%. Basis points rather than a percentage so the
  /// stored value is an integer and Law L1 is never at risk.
  percent,

  /// A weight against the other weighted participants.
  shares,
}
