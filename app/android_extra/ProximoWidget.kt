package com.futbolfantasy.futbol_fantasy

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/** Widget de la pantalla de inicio: el próximo partido, cuántos van y si vas tú. Lo rellena la app. */
class ProximoWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, mgr: AppWidgetManager, ids: IntArray) {
        for (id in ids) mgr.updateAppWidget(id, vista(ctx))
    }

    companion object {
        private fun vista(ctx: Context): RemoteViews {
            val p = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val v = RemoteViews(ctx.packageName, R.layout.widget_proximo)
            v.setTextViewText(R.id.w_titulo, p.getString("flutter.widget_titulo", null) ?: "Fútbol Fantasy")
            v.setTextViewText(R.id.w_linea, p.getString("flutter.widget_linea", null) ?: "Abre la app para ver el próximo partido")
            v.setTextViewText(R.id.w_estado, p.getString("flutter.widget_estado", null) ?: "")
            val abrir = Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            v.setOnClickPendingIntent(
                R.id.w_raiz,
                PendingIntent.getActivity(ctx, 0, abrir, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            )
            return v
        }

        fun actualizarTodos(ctx: Context) {
            val mgr = AppWidgetManager.getInstance(ctx)
            val ids = mgr.getAppWidgetIds(ComponentName(ctx, ProximoWidget::class.java))
            for (id in ids) mgr.updateAppWidget(id, vista(ctx))
        }
    }
}
