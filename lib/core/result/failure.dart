/// A recoverable, expected failure returned by a repository or service instead of a thrown
/// exception, so UI code can pattern-match on the concrete subtype to decide how to respond.
sealed class Failure {
  const Failure(this.message);

  /// A developer-facing description. Never shown to a user verbatim without localisation.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The requested record does not exist, or is soft-deleted and the caller required active.
final class NotFoundFailure extends Failure {
  /// Records that [id] could not be found.
  const NotFoundFailure(super.message, {required this.id});

  /// The identifier that was looked up.
  final String id;
}

/// The operation would violate a uniqueness or identity rule (e.g. a duplicate account name).
final class ConflictFailure extends Failure {
  /// Describes the conflicting rule in [message].
  const ConflictFailure(super.message);
}

/// The change is blocked by a business rule, e.g. deleting an account with live transactions.
final class BusinessRuleFailure extends Failure {
  /// [rule] is a short machine-readable rule id (e.g. `'accountInUse'`) for the UI to switch
  /// on; [message] is the human-readable explanation.
  const BusinessRuleFailure(super.message, {required this.rule});

  /// A short, stable identifier for the violated rule.
  final String rule;
}

/// Input failed validation before it reached storage.
final class ValidationFailure extends Failure {
  /// [field] names the offending input when the failure is field-specific.
  const ValidationFailure(super.message, {this.field});

  /// The offending field name, or `null` if the failure isn't tied to one field.
  final String? field;
}

/// An unexpected, non-recoverable error was caught and wrapped so it can't crash the app.
final class UnexpectedFailure extends Failure {
  /// Wraps the original [cause], if one is available.
  const UnexpectedFailure(super.message, {this.cause});

  /// The underlying exception or error that was caught, if any.
  final Object? cause;
}

/// Why a decimal-text-to-integer parse (an amount or a quantity) did not succeed. Shared by
/// [MoneyParser] and [UnitConverter] since both parse a locale-formatted decimal string into
/// an exact integer and can fail in exactly these ways.
enum ParseFailure {
  /// The input was empty (or became empty after trimming).
  empty,

  /// The input has no digits, or has structural problems a plain digit/separator scan
  /// can't resolve (e.g. two decimal points).
  malformed,

  /// The input contains a character that isn't a digit, sign, or a locale separator.
  invalidCharacter,

  /// The input starts with a minus sign but the caller disallowed negative values.
  negativeNotAllowed,

  /// The input has more fractional digits than the target precision supports (e.g. typing
  /// "100.5" for a currency with 0 decimal digits, or a unit finer than the stored factor
  /// allows) and this parser refuses to silently round away typed precision.
  tooManyDecimalDigits,

  /// The input is implausibly long and was rejected before attempting to parse it, as a
  /// guard against integer overflow on a pathological string.
  tooLarge,
}