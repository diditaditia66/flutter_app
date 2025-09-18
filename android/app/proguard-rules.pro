# Retain classes required for networking (HTTP client)
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keepnames class okhttp3.** { *; }
-keepnames class okio.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Prevent obfuscation of Flutter classes
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**
