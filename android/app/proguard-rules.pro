# Alaya — R8 keep rules.
#
# Phase 9 turned on `isMinifyEnabled` and `isShrinkResources`. Flutter, drift and the Play Billing library all
# ship their own consumer rules, so this file is deliberately short: a long keep list is usually a sign that
# somebody silenced a warning rather than understanding it, and every unnecessary `-keep` gives back the size
# that shrinking was turned on to save.

# ── Play Core, referenced by Flutter's deferred-components support ─────────────────────────────
#
# Flutter's engine references `com.google.android.play.core.*` whether or not the app uses deferred components.
# Alaya does not, so the classes are absent and R8 warns about the dangling references. Warning suppressed rather
# than the classes kept: keeping absent classes is impossible, and the reference is never reached at runtime.
-dontwarn com.google.android.play.core.**

# ── Reflection-free by design ─────────────────────────────────────────────────────────────────
#
# No `-keep` for the app's own classes. Nothing in Alaya is looked up by name at runtime: there is no JSON
# reflection, no service loader and no dynamic instantiation. drift generates concrete Dart, and the platform
# channel resolves by string on the *Kotlin* side, which R8 does not touch.
#
# If a future release crashes with a `ClassNotFoundException`, the cause is a new dependency doing reflection —
# add its rule here with a comment naming the dependency, rather than a blanket keep.