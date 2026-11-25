# flutter_inappwebview_android 1.1.3, patched

A copy of the pub.dev package (Apache 2.0, see LICENSE), used through
`dependency_overrides` in the app's pubspec.yaml. It comes in with
cloudflare_turnstile (the sign-in bot check).

The one change: `android/build.gradle` uses
`getDefaultProguardFile('proguard-android-optimize.txt')` instead of
`'proguard-android.txt'`, which Android Gradle Plugin 9 refuses (the Android
build failed while evaluating this plugin).

Drop this copy and the override once a release of the package fixes it.
