import 'package:flutter_test/flutter_test.dart';

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/core/text/split_placeholder_names.dart';
import 'package:alaya/domain/entities/payee.dart';

/// [SplitPlaceholderNames].
///
/// **The detection tests are rewritten, not repaired.** They used to assert a regular expression over
/// the *name* — which meant somebody who genuinely typed "Person 5" was treated as a placeholder, and
/// a placeholder renamed to "Ravi" stopped being one only because the name changed rather than because
/// anything said so. Detection now reads `kind`, so the tests assert the fact rather than a label on it.
void main() {
  Payee payee(String name, {PayeeKind kind = PayeeKind.person}) => Payee(
    id: 'p-$name',
    name: name,
    normalizedName: name.toLowerCase(),
    kind: kind,
  );

  group('numbering', () {
    test('starts at one when nobody exists', () {
      expect(
        SplitPlaceholderNames.nextNames(count: 3, existing: const []),
        ['Person 1', 'Person 2', 'Person 3'],
      );
    });

    test('continues past whatever is already there', () {
      // **A second split must not create a second "Person 1".** Two people who have never met sharing
      // a row is the failure this avoids, and it is invisible until somebody settles the wrong debt.
      expect(
        SplitPlaceholderNames.nextNames(
          count: 2,
          existing: const ['Person 1', 'Person 2', 'Person 3', 'Ravi'],
        ),
        ['Person 4', 'Person 5'],
      );
    });

    test('a renamed placeholder does not free its number', () {
      // "Person 1" became "Ravi", and the next name is still 4 — reusing 1 would put a fresh stranger
      // where a known person used to be in every historical split.
      expect(
        SplitPlaceholderNames.nextNames(
          count: 1,
          existing: const ['Ravi', 'Person 2', 'Person 3'],
        ),
        ['Person 4'],
      );
    });

    test('names that merely look similar are ignored', () {
      expect(
        SplitPlaceholderNames.nextNames(
          count: 1,
          existing: const ['Person', 'Personal', 'Person X', 'Persons 9'],
        ),
        ['Person 1'],
      );
    });

    test('asking for none gives none', () {
      expect(
        SplitPlaceholderNames.nextNames(count: 0, existing: const ['Person 1']),
        isEmpty,
      );
    });
  });

  group('detection reads the kind, not the name', () {
    test('a placeholder is one whatever it is called', () {
      // The kind survives a rename that has not happened yet, and it is what the balance row keys its
      // "Who is this?" affordance on.
      for (final name in ['Person 4', 'Ravi', '']) {
        expect(
          SplitPlaceholderNames.isPlaceholder(
            payee(name, kind: PayeeKind.splitPlaceholder),
          ),
          isTrue,
          reason: name,
        );
      }
    });

    test('somebody who typed "Person 5" themselves is not a placeholder', () {
      // **The bug the regular expression had.** A real contact called "Person 5" was offered a rename
      // prompt they never needed, and nothing in the data disagreed — because the data was never asked.
      expect(SplitPlaceholderNames.isPlaceholder(payee('Person 5')), isFalse);
    });

    test('naming one is what stops it being a placeholder', () {
      // Renaming writes `kind: person` and the real name in a single update. There is no flag to clear,
      // so a flag and a name can never disagree.
      final before = payee('Person 4', kind: PayeeKind.splitPlaceholder);
      final after = payee('Ravi');
      expect(SplitPlaceholderNames.isPlaceholder(before), isTrue);
      expect(SplitPlaceholderNames.isPlaceholder(after), isFalse);
    });

    test('no other kind is ever mistaken for one', () {
      for (final kind in PayeeKind.values) {
        expect(
          SplitPlaceholderNames.isPlaceholder(payee('Anybody', kind: kind)),
          kind == PayeeKind.splitPlaceholder,
          reason: kind.name,
        );
      }
    });
  });
}
