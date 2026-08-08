/// Reduces a display name to a canonical form used only for identity matching (e.g. two
/// Items are the same Item only if their normalized names are identical) — the normalized
/// form is never shown to a user. Deliberately does no stemming or singularisation: "tomato"
/// and "tomatoes" normalize to two different strings, and stay two different Items, because
/// silent fuzzy merging can corrupt data in ways a user can't easily notice or undo.
final class Normalizer {
  /// Creates a normalizer. Stateless — safe to use as a `const` singleton.
  const Normalizer();

  // \p{M} (combining marks) must stay allowed alongside \p{L}\p{N} — Devanagari vowel
  // signs, Arabic tashkeel, and similar combining diacritics are category M, not L, and
  // stripping them as "punctuation" would corrupt those scripts' words, not just declutter
  // them the way it does for Latin punctuation.
  static final RegExp _nonLetterDigitOrMark = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);
  static final RegExp _whitespaceRun = RegExp(r'\s+');

  /// Produces the canonical identity form of [input]: case-folded, common precomposed Latin
  /// diacritics stripped to their base letter, all other punctuation removed (any script,
  /// via a Unicode-aware letter/number/mark test — not a hardcoded ASCII punctuation list),
  /// internal whitespace collapsed to single spaces, and the result trimmed. Limitation:
  /// this folds precomposed Latin accents (`'é'` as one code point, how Android text input
  /// normally produces them) but not an `'e'` followed by a separate combining-accent code
  /// point, which is rare in practice and is left attached rather than risking corruption
  /// of combining marks in other scripts.
  String normalize(String input) {
    final caseFolded = input.toLowerCase();
    final withoutDiacritics = _stripDiacritics(caseFolded);
    final withoutPunctuation = withoutDiacritics.replaceAll(_nonLetterDigitOrMark, ' ');
    return withoutPunctuation.replaceAll(_whitespaceRun, ' ').trim();
  }

  String _stripDiacritics(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      final replacement = _diacriticMap[rune];
      if (replacement != null) {
        buffer.write(replacement);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  /// Maps lowercase Latin letters with diacritics/ligatures to their plain base form(s).
  /// Covers Latin-1 Supplement and the common Latin Extended-A range; scripts without this
  /// notion of "diacritics to strip" (Devanagari, Arabic, CJK, ...) pass through unchanged.
  /// Every rune of each key maps to the value, including the plain base letter that leads the
  /// multi-character groups — that self-mapping is a harmless no-op, and iterating all runes
  /// is what makes the single-character ligature entries (`æ`, `œ`, `ß`, `ð`, `þ`) work at all.
  static final Map<int, String> _diacriticMap = {
    for (final entry in const {
      'aàáâãäåāăą': 'a',
      'cçćĉċč': 'c',
      'dđď': 'd',
      'eèéêëēĕėęě': 'e',
      'gĝğġģ': 'g',
      'hĥħ': 'h',
      'iìíîïĩīĭįı': 'i',
      'jĵ': 'j',
      'kķ': 'k',
      'lĺļľł': 'l',
      'nñńņň': 'n',
      'oòóôõöøōŏő': 'o',
      'rŕŗř': 'r',
      'sśŝşš': 's',
      'tţťŧ': 't',
      'uùúûüũūŭůűų': 'u',
      'wŵ': 'w',
      'yýÿŷ': 'y',
      'zźżž': 'z',
      'æ': 'ae',
      'œ': 'oe',
      'ß': 'ss',
      'ð': 'd',
      'þ': 'th',
    }.entries)
      for (final variant in entry.key.runes) variant: entry.value,
  };
}