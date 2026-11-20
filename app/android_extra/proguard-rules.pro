# WorkManager / Room: se crean por reflexión al arrancar (si R8 los quita, la app se cierra al abrir)
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.** { *; }
-keep class androidx.room.** { *; }
-keep class androidx.startup.** { *; }
-dontwarn androidx.work.**
