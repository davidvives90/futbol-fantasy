package com.futbolfantasy.futbol_fantasy

import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Process
import java.io.PrintWriter
import java.io.StringWriter
import kotlin.system.exitProcess

/** Si la app se cae (incluso antes de arrancar Flutter), muestra el error en pantalla en vez de cerrarse sin más. */
class App : Application() {
    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base)
        val anterior = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { hilo, e ->
            try {
                val sw = StringWriter()
                e.printStackTrace(PrintWriter(sw))
                val traza = sw.toString().take(12000)
                val i = Intent(base, CrashActivity::class.java)
                    .putExtra("traza", traza)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
                base.startActivity(i)
                Process.killProcess(Process.myPid())
                exitProcess(10)
            } catch (_: Throwable) {
                anterior?.uncaughtException(hilo, e)
            }
        }
    }
}
