/// Converts between a Dart enum and its stored `TEXT` representation, mapping any string
/// that doesn't match a current member to a declared [fallback] instead of throwing
/// (Law L13). This is what lets an older build of the app open a database written by a
/// newer one — an unrecognised value degrades to a safe default rather than crashing — and
/// why the stored form is always the enum's own name (`"grocery"`, not `3`): a plain-text
/// backup file stays human-readable, and Law L13 forbids ever renaming an enum value once
/// shipped, since that would silently change what every existing stored row means.
final class SafeEnumConverter<T extends Enum> {
  /// Creates a converter for an enum whose members are [values] (pass `T.values`), falling
  /// back to [fallback] for any unrecognised stored string.
  const SafeEnumConverter(this.values, this.fallback);

  /// All members of the enum, in declaration order.
  final List<T> values;

  /// The member returned when a stored string matches no current member's name.
  final T fallback;

  /// The stored `TEXT` representation of [value] — always its Dart enum name.
  String toSql(T value) => value.name;

  /// The enum member whose name matches [raw], or [fallback] if none does.
  T fromSql(String raw) {
    for (final candidate in values) {
      if (candidate.name == raw) return candidate;
    }
    return fallback;
  }
}