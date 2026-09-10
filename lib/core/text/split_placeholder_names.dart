/// Naming a split participant nobody has identified yet.
///
/// **A split saves without names, and this is how without junking your contacts.** A share must name
/// somebody — `split_shares.payee_id` is `NOT NULL REFERENCES payees(id)` — so an unnamed participant
/// needs a payee row to exist at all.
///
/// The first attempt made those rows ordinary people called "Person 4", which was rejected for the
/// right reason: they pile up in Settings › Payees beside real contacts. The second idea was a schema
/// change making `payee_id` nullable, which needs the table rebuilt, a new drift snapshot and a
/// regenerated `schema_steps.dart`.
///
/// [PayeeKind.splitPlaceholder] costs neither. `SafeEnumConverter` stores an enum **by name**, so a new
/// member needs no migration; the row exists where balances need it and is filtered out of every list
/// where you would not want it.
library;

import 'package:alaya/core/enums/money_enums.dart';
import 'package:alaya/domain/entities/payee.dart';

/// Placeholder participants: how they are named, and how they are recognised.
abstract final class SplitPlaceholderNames {
  /// The word every placeholder starts with.
  ///
  /// Not localised, deliberately: the name is written to the database, so translating it would leave a
  /// user who changes language with half their placeholders called "Person" and half "Personne".
  static const String prefix = 'Person';

  /// Whether [payee] is a row this app created because nobody had been named.
  ///
  /// **Read from `kind`, not from the name.** An earlier version matched `Person \d+` with a regular
  /// expression, which meant somebody who genuinely typed "Person 5" got offered a rename, and a
  /// placeholder renamed to "Ravi" stopped being detectable only because the *name* changed rather
  /// than because anything said so. The kind is the fact; the name is a label on it.
  static bool isPlaceholder(Payee payee) =>
      payee.kind == PayeeKind.splitPlaceholder;

  /// [count] fresh placeholder names, numbered past everything in [existing].
  ///
  /// **Continues the sequence rather than restarting it**, so a second split does not create a second
  /// "Person 1" beside the first. Two strangers sharing a row is a wrong balance nobody would think to
  /// check, and renaming one does not free its number.
  ///
  /// [existing] should be every participant of any kind: a placeholder that has since become "Ravi" no
  /// longer matches the pattern, but the number it used is still spoken for by the rows referencing it.
  static List<String> nextNames({
    required int count,
    required Iterable<String> existing,
  }) {
    var top = 0;
    final pattern = RegExp('^$prefix\\s+(\\d+)\$');
    for (final name in existing) {
      final match = pattern.firstMatch(name.trim());
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!);
      if (value != null && value > top) top = value;
    }
    return [for (var i = 1; i <= count; i++) '$prefix ${top + i}'];
  }
}
