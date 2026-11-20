# Versión web

- Mismo código y misma base de datos que la app Android: cuentas, ligas y datos compartidos.
- Se compila y publica sola en cada cambio (job `web` del workflow) en la rama `gh-pages`.
- Dirección provisional: https://davidvives90.github.io/futbol-fantasy/ (política: …/privacidad.html).
- Adaptable: móvil (< 600 px, barra inferior), tableta (600–1199 px, menú lateral desde 720 px), ordenador (≥ 1200 px, app centrada máx. 1100 px).
- Publicidad web (AdSense, banners fijos): superior 320×50 / 468×60 / 728×90 según ancho; laterales en ordenador 160×600 (izq.) y 300×600 o 160×600 (der.).
  Sin AdSense configurado se ven recuadros «Publicidad» de muestra (variable WEB_ANUNCIOS_DEMO=false los oculta).
- Sin anuncios a pantalla completa ni notificaciones push en la web (de momento); los avisos se ven en la campana.
- Acceso: enlace mágico o código de 6 dígitos del correo (necesario en iPhone con la web añadida a la pantalla de inicio).

## Pasos pendientes (David)
1. GitHub › Settings › Pages › Source «Deploy from a branch» › `gh-pages` / `(root)`.
2. Supabase › Authentication › URL Configuration › Redirect URLs: añadir `https://davidvives90.github.io/futbol-fantasy/**` (y luego `https://<dominio>/**`).
3. Supabase › Authentication › Emails › «Magic Link»: añadir el código `{{ .Token }}` a la plantilla.
4. Con dominio: variable `WEB_DOMINIO` en GitHub (p. ej. `app.midominio.es`) + registro DNS CNAME `app` → `davidvives90.github.io`.
5. AdSense (requiere dominio propio): variables `ADSENSE_CLIENT` (ca-pub-…), `ADSENSE_SLOT_SUPERIOR`, `ADSENSE_SLOT_LATERAL`. El ads.txt se genera solo.
