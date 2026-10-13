# Flutter Core & Platform Channel Plumbing
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.common.** { *; }

# Flutter Classic Bluetooth native plugin classes
-keep class com.flutter_classic_bluetooth.** { *; }
-keep class com.flutter_classic_bluetooth.flutter_classic_bluetooth.** { *; }
-keep class com.almasum.flutter_classic_bluetooth.** { *; }
-dontwarn com.flutter_classic_bluetooth.**
-dontwarn com.almasum.flutter_classic_bluetooth.**

# Permission Handler plugin classes
-keep class com.baseflow.permissionhandler.** { *; }
-dontwarn com.baseflow.permissionhandler.**

# Android Bluetooth APIs and reflection methods (e.g. removeBond)
-keepclassmembers class android.bluetooth.BluetoothDevice {
    public *;
}
-keepclassmembers class android.bluetooth.BluetoothAdapter {
    public *;
}
-keepclassmembers class android.bluetooth.BluetoothSocket {
    public *;
}
-keepclassmembers class android.bluetooth.BluetoothServerSocket {
    public *;
}

# Preserve all MethodCallHandler and StreamHandler implementations
-keep class * implements io.flutter.plugin.common.MethodChannel$MethodCallHandler { *; }
-keep class * implements io.flutter.plugin.common.EventChannel$StreamHandler { *; }
