/// What an analytics drill-down filters the ledger by.
///
/// The **kind** is a closed set because each arm is a different query against
/// `TransactionRepository`, and the **value** is an id or an enum name that the view-model resolves
/// to a display label. Neither carries the window: ARCH_5 §5.7 keeps a selected range in the
/// view-model rather than in the route, so a drill-down inherits whatever the analytics screen is
/// showing and the URL stays the record's identity.
///
/// **There is deliberately no `tag` arm, and the cause is one missing read rather than a design
/// choice.** Every kind here is answerable from what `TransactionRepository` already exposes — four
/// from fields the `Transaction` entity carries, and `item` from `watchLinesForItem`. A tag is not:
/// the link lives in `transaction_tags`, `Transaction` carries no tag ids, and
/// `TagRepository.watchForTransaction` is per-transaction, so filtering a window by tag would be one
/// query per row. The same gap is why 6A's `TransactionFilter` has no tag axis either — this phase
/// inherits it rather than introducing it.
///
/// So the tag surface drills **within analytics**, parent tag to child tags, which is exactly what
/// ARCH_5 §7.2 assigns to this phase. Closing the ledger path needs
/// `TagRepository.watchTransactionIdsFor(tagId)` over `transaction_tags` — one DAO query, one
/// contract method, one impl — and is recorded in this phase's coverage table with its owner.
enum DrillDownKind {
  /// One `TransactionSubtype` — the closed structural flow type.
  subtype,

  /// One payment method, by id.
  paymentMethod,

  /// One payee, by id.
  payee,

  /// One item, by id — the transactions whose lines reference it.
  item,

  /// Whether spending settled a recurring template. The value is `recurring` or `discretionary`.
  recurring;

  /// Parses a path parameter, or null when it names no kind this build knows.
  ///
  /// Null rather than a fallback, because a drill-down route is deep-linkable and guessing at the
  /// kind would filter by the wrong axis while looking like it worked.
  static DrillDownKind? parse(String? raw) {
    for (final kind in DrillDownKind.values) {
      if (kind.name == raw) return kind;
    }
    return null;
  }
}

/// One drill-down: an axis and the value on it.
class DrillDownSpec {
  /// Creates a spec.
  const DrillDownSpec({required this.kind, required this.value});

  /// Parses a spec from its two path parameters, or null when either is unusable.
  static DrillDownSpec? parse({String? kind, String? value}) {
    final parsed = DrillDownKind.parse(kind);
    if (parsed == null || value == null || value.isEmpty) return null;
    return DrillDownSpec(kind: parsed, value: value);
  }

  /// Which axis is filtered.
  final DrillDownKind kind;

  /// The id or enum name filtered on.
  final String value;

  /// Value equality, so a Riverpod family keyed on this caches one provider per drill-down rather
  /// than rebuilding on every navigation.
  @override
  bool operator ==(Object other) =>
      other is DrillDownSpec && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'DrillDownSpec(${kind.name}, $value)';
}
