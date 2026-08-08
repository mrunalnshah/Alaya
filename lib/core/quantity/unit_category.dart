/// The three fixed physical quantity categories [Qty] can hold. No fourth category is ever
/// added (ARCH_1 §5.3): if an amount can't be expressed in one of these, the correct action
/// is a new Item, never a new category — this keeps cross-category conversion permanently
/// impossible to express (Law L8), rather than merely discouraged.
enum UnitCategory {
  /// Measured by mass. Base unit: gram.
  weight,

  /// Measured by capacity. Base unit: millilitre.
  volume,

  /// Measured by count. Base unit: piece. Never decomposed into a bigger/smaller unit pair.
  count;

  /// The canonical base unit code for this category: `'g'`, `'ml'`, or `'pc'`.
  String get baseUnitCode => switch (this) {
    UnitCategory.weight => 'g',
    UnitCategory.volume => 'ml',
    UnitCategory.count => 'pc',
  };
}