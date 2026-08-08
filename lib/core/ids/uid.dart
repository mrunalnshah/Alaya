import 'package:uuid/uuid.dart' as pkg_uuid;

/// Generates the identifiers used for every table's `TEXT` primary key (Law L5). Injected
/// wherever an id is created so tests can substitute a deterministic generator.
abstract interface class UidGenerator {
  /// A new, globally unique identifier.
  String generate();
}

/// The production [UidGenerator]: RFC 9562 UUIDv7, time-ordered so rows created later sort
/// after rows created earlier even without an extra `createdAt` index.
final class Uuid7Generator implements UidGenerator {
  /// Creates a generator backed by `package:uuid`.
  const Uuid7Generator();

  static const pkg_uuid.Uuid _uuid = pkg_uuid.Uuid();

  @override
  String generate() => _uuid.v7();
}

/// A deterministic [UidGenerator] for tests: returns `prefix-0`, `prefix-1`, ... in call
/// order, so fixtures and assertions can reference ids without reading generated values.
final class SequentialUidGenerator implements UidGenerator {
  /// Creates a generator whose ids are `'$prefix-$n'` for an incrementing counter `n`.
  SequentialUidGenerator({this.prefix = 'test'});

  /// The fixed prefix used for every generated id.
  final String prefix;

  int _next = 0;

  @override
  String generate() => '$prefix-${_next++}';
}