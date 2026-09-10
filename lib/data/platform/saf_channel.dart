import 'dart:async';

import 'package:flutter/services.dart';

import 'package:alaya/core/result/failure.dart';
import 'package:alaya/core/result/result.dart';

/// The Dart side of the Storage Access Framework bridge.
///
/// **This replaces `file_picker`, which cannot be used in this project.** ARCH_1 §7.4 documents why: the
/// resolvable version is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in
/// 2021 — so `pub get` succeeds and `assembleDebug` fails. §7 anticipated this and recommended "a small
/// SAF platform channel" instead; this is it, and it also removes five transitive desktop and web
/// dependencies an Android-only app never used.
///
/// **No permission is declared anywhere.** SAF's whole point is that the user picks the document in the
/// system's own sheet and the grant is scoped to that choice — no `WRITE_EXTERNAL_STORAGE`, no
/// `MANAGE_EXTERNAL_STORAGE` (ARCH_3 §3.3).
///
/// Both calls return **null when the sheet was dismissed**, which is not a failure: cancelling is the
/// commonest thing to do with a file chooser.
final class SafChannel {
  /// Creates the bridge. [channel] is injectable so a test can answer without a platform.
  const SafChannel({MethodChannel channel = const MethodChannel(channelName)})
    : _channel = channel;

  final MethodChannel _channel;

  /// The channel name, matched by `SafPlugin.kt`.
  static const String channelName = 'com.alaya/saf';

  /// Opens a document and returns a **cache copy's absolute path**.
  ///
  /// A copy rather than the URI, because `RestoreService` runs `ATTACH DATABASE` on a filesystem path and
  /// SQLite cannot open a `content://` URI — and because the read grant expires with the activity result,
  /// so a URI kept past it would be unreadable exactly when the restore needed it.
  Future<Result<String?, Failure>> openDocument({
    List<String> mimeTypes = const ['*/*'],
  }) async {
    try {
      final path = await _channel.invokeMethod<String>(
        'openDocument',
        <String, Object?>{'mimeTypes': mimeTypes},
      );
      return Result.ok(path);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          error.message ?? 'That file could not be opened.',
          cause: error,
        ),
      );
    } on MissingPluginException catch (error) {
      // Says which half is missing. A generic failure here sends somebody looking at their file manager
      // when the answer is that `SafPlugin` was never registered in `MainActivity`.
      return Result.failure(
        UnexpectedFailure(
          'File access is not available in this build.',
          cause: error,
        ),
      );
    }
  }

  /// Raises the create-document sheet and writes [sourcePath] into whatever the user chose.
  ///
  /// One round trip rather than two, so Dart never holds a URI it has no way to use.
  Future<Result<String?, Failure>> createDocument({
    required String sourcePath,
    required String fileName,
    String mimeType = 'application/octet-stream',
  }) async {
    try {
      final uri = await _channel.invokeMethod<String>(
        'createDocument',
        <String, Object?>{
          'sourcePath': sourcePath,
          'fileName': fileName,
          'mimeType': mimeType,
        },
      );
      return Result.ok(uri);
    } on PlatformException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          error.message ?? 'That file could not be saved.',
          cause: error,
        ),
      );
    } on MissingPluginException catch (error) {
      return Result.failure(
        UnexpectedFailure(
          'File access is not available in this build.',
          cause: error,
        ),
      );
    }
  }
}
