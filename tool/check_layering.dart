import 'dart:io';

/// Enforces Law L12: `lib/domain/` may never import Flutter, drift, or `lib/data/`, and
/// `lib/core/` may never import Flutter. Run with `dart run tool/check_layering.dart`; exits
/// with code 1 and a list of violations if the rule is broken, or 0 if the tree is clean.
Future<void> main() async {
  final violations = <String>[
    ..._scan(
      directory: 'lib/domain',
      bannedImportPrefixes: const [
        'package:flutter/',
        'package:drift/',
        'package:alaya/data/',
      ],
      bannedRelativeSegment: '/data/',
    ),
    ..._scan(
      directory: 'lib/core',
      bannedImportPrefixes: const ['package:flutter/'],
      bannedRelativeSegment: null,
    ),
  ];

  if (violations.isEmpty) {
    stdout.writeln('check_layering: OK — no boundary violations found.');
    return;
  }

  stderr.writeln('check_layering: FAILED — ${violations.length} violation(s):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  exitCode = 1;
}

/// Scans every `.dart` file under [directory] and returns one description per import
/// statement that starts with a banned prefix or contains [bannedRelativeSegment].
List<String> _scan({
  required String directory,
  required List<String> bannedImportPrefixes,
  required String? bannedRelativeSegment,
}) {
  final root = Directory(directory);
  if (!root.existsSync()) return const [];

  final found = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;

    final lines = entity.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (!line.startsWith('import ') && !line.startsWith('export ')) continue;

      final isBannedPrefix = bannedImportPrefixes.any(
            (prefix) => line.contains("'$prefix") || line.contains('"$prefix'),
      );
      final isBannedRelative = bannedRelativeSegment != null &&
          line.contains(bannedRelativeSegment) &&
          !line.contains('package:');

      if (isBannedPrefix || isBannedRelative) {
        found.add('${entity.path}:${i + 1}: $line');
      }
    }
  }
  return found;
}