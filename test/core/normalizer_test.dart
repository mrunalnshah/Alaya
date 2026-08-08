import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/text/normalizer.dart';

void main() {
  const normalizer = Normalizer();

  group('casefolding', () {
    test('uppercase folds to lowercase', () {
      expect(normalizer.normalize('POTATO'), 'potato');
    });

    test('mixed case folds to lowercase', () {
      expect(normalizer.normalize('PoTaTo'), 'potato');
    });
  });

  group('diacritic stripping', () {
    test('strips a single acute accent', () {
      expect(normalizer.normalize('café'), 'cafe');
    });

    test('strips a tilde', () {
      expect(normalizer.normalize('jalapeño'), 'jalapeno');
    });

    test('strips diacritics on uppercase letters too, after casefolding', () {
      expect(normalizer.normalize('MÜNCHEN'), 'munchen');
    });

    test('folds ligatures to their letter pairs', () {
      expect(normalizer.normalize('œuf'), 'oeuf');
    });

    test('folds eszett to ss', () {
      expect(normalizer.normalize('straße'), 'strasse');
    });
  });

  group('punctuation stripping', () {
    test('a comma becomes whitespace and is collapsed', () {
      expect(normalizer.normalize('Rice, White'), 'rice white');
    });

    test('an apostrophe becomes whitespace, consistent with all other punctuation', () {
      expect(normalizer.normalize("Tomato's"), 'tomato s');
    });

    test('digits are preserved, only punctuation is stripped', () {
      expect(normalizer.normalize('Vitamin B-12!'), 'vitamin b 12');
    });
  });

  group('whitespace collapse and trim', () {
    test('multiple internal spaces collapse to one', () {
      expect(normalizer.normalize('Rice    Flour'), 'rice flour');
    });

    test('leading and trailing whitespace is trimmed', () {
      expect(normalizer.normalize('   Rice Flour   '), 'rice flour');
    });

    test('tabs and newlines count as whitespace', () {
      expect(normalizer.normalize('Rice\tFlour\n'), 'rice flour');
    });
  });

  group('combined pipeline', () {
    test('casefold, diacritics, punctuation, and whitespace all apply together', () {
      expect(normalizer.normalize('  CAFÉ-Au-Lait!!  '), 'cafe au lait');
    });
  });

  group('exact-match-only (no stemming, no singularisation) — A07', () {
    test('a plural and its singular remain two different normalized strings', () {
      expect(normalizer.normalize('tomato'), isNot(normalizer.normalize('tomatoes')));
      expect(normalizer.normalize('tomatoes'), 'tomatoes');
    });

    test('near-identical words are not silently merged', () {
      expect(normalizer.normalize('onion'), isNot(normalizer.normalize('onions')));
    });
  });

  group('non-Latin scripts pass through unchanged (beyond casefold/whitespace)', () {
    test('Devanagari text is preserved, not stripped as punctuation', () {
      expect(normalizer.normalize('टमाटर'), 'टमाटर');
    });

    test('Devanagari text still has its surrounding whitespace trimmed', () {
      expect(normalizer.normalize('  टमाटर  '), 'टमाटर');
    });
  });

  group('empty and whitespace-only input', () {
    test('an empty string normalizes to an empty string', () {
      expect(normalizer.normalize(''), '');
    });

    test('a whitespace-only string normalizes to an empty string', () {
      expect(normalizer.normalize('   '), '');
    });
  });
}