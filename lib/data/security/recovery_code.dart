import 'dart:math';

/// Generates and normalises the single recovery code that resets a forgotten PIN (ARCH_3 §2.1).
///
/// Ten characters from a 32-symbol alphabet is `32^10`, about `1.1 x 10^15` combinations. Against a
/// local-only check with the same throttle the PIN uses, that is far beyond brute force — and it
/// stays short enough to write on paper, which is the point of having one at all.
final class RecoveryCode {
  /// Creates a generator. [random] is injectable so tests can be deterministic; production must
  /// pass a [Random.secure].
  RecoveryCode({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  /// The 32 symbols a code may contain.
  ///
  /// The full `0-9A-Z` set is 36 symbols; removing the four that people transcribe wrongly — `0`
  /// against `O`, `1` against `I` — leaves exactly 32, which is precisely a base-32 alphabet with no
  /// padding waste. That the arithmetic works out this neatly is why the exclusion list is those
  /// four and not a longer set of near-misses.
  static const String alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';

  /// How many characters a code has.
  static const int length = 10;

  /// Where the display hyphen goes: `ABCDE-FGHJK`.
  static const int groupSize = 5;

  /// Generates a new code, unformatted.
  ///
  /// Draws from [Random.secure] by default. A predictable code would be worse than no recovery path,
  /// because the UI presents it as a secret worth writing down.
  String generate() {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// Generates a code formatted for display, hyphenated in two groups of five.
  String generateFormatted() => format(generate());

  /// Inserts the display hyphen into [code].
  String format(String code) {
    final normalized = normalize(code);
    if (normalized.length != length) return normalized;
    return '${normalized.substring(0, groupSize)}-${normalized.substring(groupSize)}';
  }

  /// Normalises user input into the canonical form used for hashing.
  ///
  /// Upper-cases, then keeps only characters that are in [alphabet] — which drops the display
  /// hyphen, any spaces, and the four excluded symbols.
  ///
  /// Dropping `0`, `O`, `1` and `I` rather than folding them onto neighbours is deliberate. Those
  /// four cannot appear in a real code, so typing one means the user misread a character. Folding
  /// `O` to `Q` would guess at which character they meant and could silently accept a wrong code;
  /// dropping it yields the wrong length, verification fails, and the UI can say plainly that a code
  /// is ten characters. A clear failure beats a lucky guess.
  String normalize(String input) {
    final upper = input.toUpperCase();
    final buffer = StringBuffer();
    for (final char in upper.split('')) {
      if (alphabet.contains(char)) buffer.write(char);
    }
    return buffer.toString();
  }

  /// True when [input] normalises to something this generator could have produced.
  bool isWellFormed(String input) {
    final normalized = normalize(input);
    return normalized.length == length &&
        normalized.split('').every(alphabet.contains);
  }
}
