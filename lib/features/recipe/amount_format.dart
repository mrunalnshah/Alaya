/// Which units are vessels rather than dimensions.
library;

/// The unit codes that correspond to a physical measuring spoon or cup.
///
/// **This is about vessels, not dimensions.** Millilitres and litres are volumes too, but nobody owns a
/// "half-litre spoon" — you read those off a jug in whole numbers. A teaspoon, tablespoon and cup are
/// things in a drawer, and they come in fractions, which is why only these three get the quick amounts
/// and the fraction hint.
///
/// A user who adds their own `dessertspoon` will not get the chips. That is a small loss against
/// hard-coding a guess about what any future unit means.
const Set<String> kSpoonAndCupCodes = {'tsp', 'tbsp', 'cup'};

// **Three things were deleted from this file, and each had become a duplicate rather than dead weight.**
//
// `parseAmountMilli` accepted `1 1/2`, `3/4` and `.5` and had **no callers anywhere** — written,
// documented at length, and never wired to the field it was written for, which is why typing a fraction
// did nothing and the module read as strict. `core/quantity/measure_parser.dart` is that parser, wired,
// and it additionally reads the vulgar-fraction characters a pasted recipe carries.
//
// `renderAmount` matched a remainder against nine hardcoded thousandths and fell back to a decimal for
// anything else — so `1/16` displayed as `0.062` and the five-chip list was never the real ceiling.
// `MeasureFormatter` derives recognition from a round trip instead, and needs no table to extend.
//
// `kStandardFractions` held five thousandths as bare ints. `kMeasuringSet` in
// `core/quantity/fraction.dart` holds the same vocabulary as `Fraction` values, with the eighth this
// list was missing, and states why it cannot be computed from the `units` table.
