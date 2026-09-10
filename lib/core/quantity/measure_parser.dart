import '../result/failure.dart';
import '../result/result.dart';
import 'fraction.dart';
import 'measure.dart';
import 'unit_converter.dart';

/// Parses the amounts cooks actually write.
///
/// **A sibling of [QtyParser], not a replacement, and the split is the point.** `QtyParser` refuses to
/// round: `0.5` of a teaspoon returns [ParseFailure.tooManyDecimalDigits], because 4929 is not divisible
/// by two and its contract is to never silently discard typed precision. That is correct for inventory,
/// where a recorded quantity is a fact about a shelf. It is wrong for a recipe, where "half a teaspoon"
/// is the most ordinary instruction in cooking and no cook is asserting 2.4645 millilitres.
///
/// So quantities stay exact and measures are allowed to approximate, and each has its own parser saying
/// so in its type. The alternative — relaxing `QtyParser` — would have made every inventory call site
/// quietly lossy to fix a recipe screen.
///
/// **The decimal path delegates to [UnitConverter].** That class already parses a locale-formatted
/// decimal into integer thousandths with half-up rounding and no rejection, and until this file it had no
/// callers anywhere — built, documented, and unreachable, which is `tool/reachability.py`'s whole subject.
/// Reusing it means one rounding implementation rather than a second one that drifts.
final class MeasureParser {
  /// Creates a parser. Stateless — safe to use as a `const` singleton.
  const MeasureParser();

  static const UnitConverter _decimals = UnitConverter();
  static const int _maxInputLength = 24;

  /// Thousandths per whole unit. [UnitConverter] converts into "milli of a thing"; passing 1000 as the
  /// factor makes that thing one unit, which is exactly [Measure]'s scale.
  static const int _milliPerUnit = 1000;

  /// Parses [input] into a [Measure].
  ///
  /// Accepted, all of which appear in real recipes:
  ///
  /// | Written | Means |
  /// |---|---|
  /// | `2`, `0.5`, `.5` | plain numbers, in the locale's own decimal separator |
  /// | `1/2`, `3/4`, `5/16` | any fraction |
  /// | `1 1/2`, `2 3/4` | a whole part and a fraction |
  /// | `½`, `⅔`, `⅜` | the vulgar-fraction characters a pasted recipe carries |
  /// | `1½`, `1 ½` | with or without the space |
  ///
  /// **Unicode fractions are accepted and never produced.** Reading them costs one lookup table and
  /// rescues every recipe pasted from a website. Writing them would risk a glyph the app's font does not
  /// carry, and `⅝` is invisible in a way that `5/8` cannot be — a rendering bug that looks like missing
  /// data. Input is generous, output is plain; see `MeasureFormatter`.
  Result<Measure, ParseFailure> parse(String input, {String localeTag = 'en'}) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return const Result.failure(ParseFailure.empty);
    if (trimmed.length > _maxInputLength) {
      return const Result.failure(ParseFailure.tooLarge);
    }
    if (trimmed.startsWith('-')) {
      // A recipe cannot call for a negative amount, and the failure names the reason rather than
      // reporting a malformed number.
      return const Result.failure(ParseFailure.negativeNotAllowed);
    }

    final text = _expandVulgarFractions(trimmed);
    final parts = text.split(RegExp(r'\s+'));
    if (parts.length > 2) return const Result.failure(ParseFailure.malformed);

    if (parts.length == 2) {
      final whole = int.tryParse(parts.first);
      if (whole == null) return const Result.failure(ParseFailure.malformed);
      final fraction = _parseFraction(parts[1]);
      if (fraction == null) return const Result.failure(ParseFailure.malformed);
      return Result.ok(Measure.of(whole, fraction));
    }

    if (text.contains('/')) {
      final fraction = _parseFraction(text);
      return fraction == null
          ? const Result.failure(ParseFailure.malformed)
          : Result.ok(Measure(fraction.milliOfUnit));
    }

    final decimal = _decimals.parseToMilliBase(
      text,
      unitFactorMilliBase: _milliPerUnit,
      localeTag: localeTag,
    );
    return decimal.isOk
        ? Result.ok(Measure(decimal.valueOrNull ?? 0))
        : Result.failure(decimal.failureOrNull ?? ParseFailure.malformed);
  }

  /// `3/4` into a [Fraction], or null for anything that is not one.
  ///
  /// A denominator beyond 1000 is rejected rather than rounded to nothing: `1/5000` would quantise to
  /// zero thousandths, and silently reading a typed amount as "none" is worse than saying no.
  Fraction? _parseFraction(String text) {
    final parts = text.split('/');
    if (parts.length != 2) return null;
    final numerator = int.tryParse(parts.first.trim());
    final denominator = int.tryParse(parts[1].trim());
    if (numerator == null || denominator == null) return null;
    if (numerator < 0 || denominator <= 0 || denominator > 1000) return null;
    return Fraction(numerator, denominator);
  }

  /// Rewrites `1½` as `1 1/2` so one code path handles both spellings.
  ///
  /// A space is inserted when a digit precedes the glyph, because `1½` and `1 ½` are the same amount and
  /// splitting on whitespace afterwards should see the same two tokens either way.
  static String _expandVulgarFractions(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      final replacement = _vulgar[rune];
      if (replacement == null) {
        out.writeCharCode(rune);
        continue;
      }
      final written = out.toString();
      if (written.isNotEmpty &&
          _isDigit(written.codeUnitAt(written.length - 1))) {
        out.write(' ');
      }
      out.write(replacement);
    }
    return out.toString();
  }

  static bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

  /// Every vulgar fraction in Latin-1 and Number Forms. Halves through tenths, which is everything a
  /// recipe site emits.
  static const Map<int, String> _vulgar = {
    0x00BD: '1/2',
    0x2153: '1/3',
    0x2154: '2/3',
    0x00BC: '1/4',
    0x00BE: '3/4',
    0x2155: '1/5',
    0x2156: '2/5',
    0x2157: '3/5',
    0x2158: '4/5',
    0x2159: '1/6',
    0x215A: '5/6',
    0x2150: '1/7',
    0x215B: '1/8',
    0x215C: '3/8',
    0x215D: '5/8',
    0x215E: '7/8',
    0x2151: '1/9',
    0x2152: '1/10',
  };
}
