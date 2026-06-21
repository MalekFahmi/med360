# Keep Flutter plugin registrants and Firebase model/runtime metadata stable
# while allowing R8 to shrink unused Java/Kotlin bytecode and resources.
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
