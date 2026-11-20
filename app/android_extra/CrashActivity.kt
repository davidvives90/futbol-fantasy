package com.futbolfantasy.futbol_fantasy

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast

/** Pantalla de error (proceso aparte): se puede copiar o compartir para enviarlo. */
class CrashActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val traza = (intent.getStringExtra("traza") ?: "Sin detalles") +
            "\n\nAndroid ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT}) · ${Build.MANUFACTURER} ${Build.MODEL}"
        val texto = "Fútbol Fantasy se ha cerrado por este error:\n\n$traza"
        val caja = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(32, 64, 32, 32) }
        caja.addView(Button(this).apply {
            text = "Compartir el error"
            setOnClickListener {
                startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, texto), "Compartir"))
            }
        })
        caja.addView(Button(this).apply {
            text = "Copiar"
            setOnClickListener {
                (getSystemService(CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("error", texto))
                Toast.makeText(this@CrashActivity, "Copiado", Toast.LENGTH_SHORT).show()
            }
        })
        caja.addView(TextView(this).apply { text = texto; textSize = 12f; setTextIsSelectable(true) })
        setContentView(ScrollView(this).apply { addView(caja) })
    }
}
