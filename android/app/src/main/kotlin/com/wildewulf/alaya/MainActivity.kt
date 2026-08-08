package com.wildewulf.alaya

import com.alaya.saf.SafPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * The host activity.
 *
 * **The base class is deliberately unchanged.** `SafPlugin` registers through the v2 embedding's
 * `ActivityAware` contract, so it works against whatever `MainActivity` already extends — which matters
 * because `local_auth` would eventually want `FlutterFragmentActivity`, and that is a separate decision
 * with its own dependency consequences. Nothing here forecloses it.
 *
 * The only addition is `configureFlutterEngine`. If your file already overrides it, add the one
 * `add(SafPlugin())` line to what is there rather than replacing the method.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(SafPlugin())
    }
}