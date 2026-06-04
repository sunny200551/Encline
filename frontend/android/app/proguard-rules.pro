# Flutter Proguard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Google ML Kit & Barcode Scanning (mobile_scanner)
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_vision_barcode.**
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }
-dontwarn com.google.android.gms.internal.mlkit_code_scanner.**

# CameraX and Vision dependencies
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.android.gms.vision.**

# Keep members used by reflection
-keepclassmembers class * extends com.google.android.gms.internal.mlkit_code_scanner.** {
    <fields>;
    <methods>;
}
-keepclassmembers class * extends com.google.android.gms.internal.mlkit_vision_barcode.** {
    <fields>;
    <methods>;
}

# Flutter WebRTC
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# General native method keeping
-keepclasseswithmembernames class * {
    native <methods>;
}
