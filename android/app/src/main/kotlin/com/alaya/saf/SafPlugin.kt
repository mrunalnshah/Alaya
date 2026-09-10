package com.alaya.saf

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * A minimal Storage Access Framework bridge: open a document, create a document, write to one.
 *
 * Written because `file_picker` cannot be used in this project. ARCH_1 §7.4 records why: the resolvable
 * version here is 3.0.4 from 2020, whose `android/build.gradle` calls `jcenter()` — shut down in 2021 —
 * so `pub get` succeeds and `assembleDebug` fails. ARCH_1 §7 anticipated this and said to "evaluate
 * whether a small SAF platform channel is preferable to the whole plugin". It is: this file replaces a
 * dependency that also dragged in `dbus`, `ffi`, `win32`, `web` and `flutter_web_plugins` — desktop and
 * web surface an Android-only app never uses.
 *
 * **No permissions are declared or needed.** That is the point of SAF: the user chooses the document in
 * the system's own picker, and the grant is scoped to what they chose. There is no
 * `WRITE_EXTERNAL_STORAGE` and no `MANAGE_EXTERNAL_STORAGE` anywhere in this app (ARCH_3 §3.3).
 *
 * Registered from `MainActivity.configureFlutterEngine`, using the v2 embedding's `ActivityAware`
 * contract, so the host activity's base class is untouched.
 */
class SafPlugin : FlutterPlugin, ActivityAware, MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var pending: MethodChannel.Result? = null
    private var pendingSourcePath: String? = null

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
        val host = activity
        if (host == null) {
            result.error("no_activity", "The picker needs a foreground activity.", null)
            return
        }
        when (call.method) {
            // Opens a document and copies it into the app's cache, returning that path.
            //
            // **A copy, not the URI.** `RestoreService` runs `ATTACH DATABASE` on a filesystem path, and
            // SQLite cannot open a `content://` URI. The grant is also scoped to this activity result, so a
            // URI held past it would be unreadable exactly when the restore needed it.
            "openDocument" -> {
                if (!claim(result)) return
                @Suppress("UNCHECKED_CAST")
                val types = (call.argument<List<String>>("mimeTypes") ?: listOf("*/*")).toTypedArray()
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = if (types.size == 1) types[0] else "*/*"
                    if (types.size > 1) putExtra(Intent.EXTRA_MIME_TYPES, types)
                }
                host.startActivityForResult(intent, REQUEST_OPEN)
            }

            // Raises the create-document sheet and writes an existing file into whatever the user chose.
            //
            // One round trip rather than two: the source path is held until the result arrives, so Dart
            // never has to hold a URI it cannot use.
            "createDocument" -> {
                if (!claim(result)) return
                pendingSourcePath = call.argument<String>("sourcePath")
                if (pendingSourcePath == null) {
                    finish(null, "no_source", "No file was given to save.")
                    return
                }
                val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = call.argument<String>("mimeType") ?: "application/octet-stream"
                    putExtra(Intent.EXTRA_TITLE, call.argument<String>("fileName") ?: "alaya.db")
                }
                host.startActivityForResult(intent, REQUEST_CREATE)
            }

            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_OPEN && requestCode != REQUEST_CREATE) return false
        val uri: Uri? = if (resultCode == Activity.RESULT_OK) data?.data else null
        // Dismissing the sheet returns null rather than an error: cancelling is the commonest outcome of a
        // file chooser, and reporting it as a failure would put a red message under a deliberate action.
        if (uri == null) {
            finish(null, null, null)
            return true
        }
        return when (requestCode) {
            REQUEST_OPEN -> { copyIn(uri); true }
            else -> { copyOut(uri); true }
        }
    }

    private fun copyIn(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        try {
            val name = "saf_${System.currentTimeMillis()}"
            val target = File(host.cacheDir, name)
            host.contentResolver.openInputStream(uri).use { input ->
                if (input == null) return finish(null, "unreadable", "That file could not be read.")
                target.outputStream().use { output -> input.copyTo(output) }
            }
            finish(target.absolutePath, null, null)
        } catch (error: Exception) {
            finish(null, "copy_failed", error.message)
        }
    }

    private fun copyOut(uri: Uri) {
        val host = activity ?: return finish(null, "no_activity", "The activity went away.")
        val source = pendingSourcePath
        if (source == null) return finish(null, "no_source", "No file was given to save.")
        try {
            host.contentResolver.openOutputStream(uri).use { output ->
                if (output == null) return finish(null, "unwritable", "That location could not be written to.")
                File(source).inputStream().use { input -> input.copyTo(output) }
            }
            finish(uri.toString(), null, null)
        } catch (error: Exception) {
            finish(null, "write_failed", error.message)
        }
    }

    /** Takes the pending slot, refusing a second concurrent picker. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            result.error("busy", "A file chooser is already open.", null)
            return false
        }
        pending = result
        return true
    }

    private fun finish(value: String?, code: String?, message: String?) {
        val result = pending
        pending = null
        pendingSourcePath = null
        if (result == null) return
        if (code != null) result.error(code, message, null) else result.success(value)
    }

    companion object {
        /** The channel name, matched by `saf_channel.dart`. */
        const val CHANNEL = "com.alaya/saf"
        private const val REQUEST_OPEN = 0x5AF0
        private const val REQUEST_CREATE = 0x5AF1
    }
}