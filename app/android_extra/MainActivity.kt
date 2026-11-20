package com.futbolfantasy.futbol_fantasy

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ff/widget").setMethodCallHandler { call, res ->
            if (call.method == "actualizar") {
                try { ProximoWidget.actualizarTodos(this) } catch (_: Throwable) {}
                res.success(null)
            } else {
                res.notImplemented()
            }
        }
    }
}
