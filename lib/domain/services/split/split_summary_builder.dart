import 'package:alaya/core/money/money.dart';
import 'package:alaya/domain/entities/split_read_models.dart';

/// One line of a shareable summary.
final class SummaryLine {
  /// Creates a line.
  const SummaryLine({
    required this.payeeId,
    required this.name,
    required this.amount,
    required this.theyOweMe,
  });

  /// The counterparty.
  final String payeeId;

  /// Their display name.
  final String name;

  /// What is outstanding, without its direction.
  final Money amount;

  /// Whether they owe the user.
  final bool theyOweMe;
}

/// A summary of who owes what, ready to send to somebody who does not have the app.
final class SplitSummary {
  /// Creates a summary.
  const SplitSummary({required this.lines, required this.text});

  /// The lines, worst first.
  final List<SummaryLine> lines;

  /// The whole thing as plain text.
  final String text;

  /// Whether there is anything to send.
  bool get isEmpty => lines.isEmpty;
}

/// The sentences a summary needs, read from the ARB by the caller.
///
/// A named record rather than positional strings, so adding a fifth does not silently reorder the
/// existing four at every call site.
final class SummaryLabels {
  /// Creates the labels.
  const SummaryLabels({
    required this.heading,
    required this.owesYou,
    required this.youOwe,
    required this.payMeAt,
  });

  /// The first line.
  final String heading;

  /// Precedes a name that owes the user.
  final String owesYou;

  /// Precedes a name the user owes.
  final String youOwe;

  /// Introduces the user's payment details, when they have set any.
  final String payMeAt;
}

/// Builds the message that stands in for sync.
///
/// **This is the module's answer to the friction every review of every competitor names.** To split a
/// bill with six people on Splitwise, all six install it and create accounts, and in practice two
/// never will. Alaya is already on the right side of that — nobody else needs anything — but the gap
/// is outbound: without this there is no way to show them the same numbers.
///
/// ## Plain text, and no payment protocol
///
/// An earlier version emitted a `upi://pay` intent per line. **That was wrong for an app that ships
/// worldwide**: UPI is India's rail and the link is inert in the US, Europe, China and everywhere else,
/// so the feature was dead weight for most users and a maintenance burden for all of them — amount
/// formatting in major units, percent-encoding, a currency parameter, and a link that opens a payment
/// app with the wrong figure if any of it is subtly wrong.
///
/// What replaced it is one optional line of free text the user writes once: a UPI id, a PayPal.me
/// link, an IBAN, a Venmo handle, "cash is fine". It works in every country because it makes no claim
/// about how money moves, and it is one field instead of a protocol.
///
/// Dropping the link also removed [Money] formatting for machines from this class entirely, which is
/// why it no longer needs a per-currency precision. The only formatting left is [formatAmount], which
/// the caller supplies because a currency symbol comes from the `currencies` row and a pure builder
/// has no way to read one.
///
/// Pure: balances, names and labels in, a string out. No clock, no repository, no Flutter.
final class SplitSummaryBuilder {
  /// Creates the builder. Stateless.
  const SplitSummaryBuilder();

  /// Composes a summary of [balances].
  ///
  /// [labels] carries the copy, because a builder in `domain/` has no `BuildContext` and Law U5 keeps
  /// English out of anything below the widget layer.
  ///
  /// [paymentHandle] is whatever the user wrote under "How people can pay you". Supplied, it becomes a
  /// closing line; omitted, the summary is still perfectly useful text.
  SplitSummary build({
    required List<SplitBalance> balances,
    required String Function(String payeeId) nameOf,
    required String Function(Money amount) formatAmount,
    required SummaryLabels labels,
    String? paymentHandle,
  }) {
    final lines = <SummaryLine>[];
    for (final balance in balances) {
      if (balance.isSettled) continue;
      lines.add(
        SummaryLine(
          payeeId: balance.payeeId,
          name: nameOf(balance.payeeId),
          amount: balance.outstanding,
          theyOweMe: balance.theyOweMe,
        ),
      );
    }

    final buffer = StringBuffer()..writeln(labels.heading);
    for (final line in lines) {
      final amount = formatAmount(line.amount);
      buffer
        ..writeln()
        ..writeln(
          line.theyOweMe
              ? '${labels.owesYou} ${line.name}: $amount'
              : '${labels.youOwe} ${line.name}: $amount',
        );
    }

    // **Only when somebody owes the user.** A payment handle on a summary where the user owes everybody
    // is asking to be paid for a debt they hold, which reads as a mistake at best.
    final handle = paymentHandle?.trim();
    if (lines.any((line) => line.theyOweMe) &&
        handle != null &&
        handle.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('${labels.payMeAt} $handle');
    }

    return SplitSummary(lines: lines, text: buffer.toString().trimRight());
  }
}
