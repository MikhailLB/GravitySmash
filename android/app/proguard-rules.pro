# =============================================================
# Gravity Smash ProGuard rules.
#
# Keep just enough of the Flutter engine, Firebase, AppsFlyer
# and WebView plugin internals to survive R8 with the rest of
# the binary minified and shrunk.
# =============================================================

# Flutter engine + embedding
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Google Play Core (deferred components) — keep the stubs we ship
-dontwarn com.google.android.play.core.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AppsFlyer
-keep class com.appsflyer.** { *; }
-dontwarn com.appsflyer.**

# webview_flutter / file_picker
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# JNI / native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Parcelable + Serializable
-keep class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Strip noisy Android logging at runtime
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
