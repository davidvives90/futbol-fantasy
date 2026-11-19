// Edge Function «enviar-push»: envía por FCM (HTTP v1) las notificaciones con push_estado = 'pendiente'.
// Secreto necesario: FCM_SERVICE_ACCOUNT = JSON de la cuenta de servicio de Firebase (Configuración del proyecto →
// Cuentas de servicio → Generar nueva clave privada). SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY los pone Supabase.
// La invoca pg_cron cada minuto solo si hay pendientes (0103). Idempotente: se puede llamar de más sin efectos.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function tokenGoogle(sa: { client_email: string; private_key: string }): Promise<string> {
  const key = await importPKCS8(sa.private_key, "RS256");
  const ahora = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(ahora)
    .setExpirationTime(ahora + 3600)
    .sign(key);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  if (!r.ok) throw new Error(`OAuth Google: ${r.status} ${await r.text()}`);
  return (await r.json()).access_token;
}

Deno.serve(async () => {
  const bruto = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!bruto) return Response.json({ ok: false, motivo: "Falta el secreto FCM_SERVICE_ACCOUNT" });
  const sa = JSON.parse(bruto);

  const { data: pendientes, error } = await sb
    .from("notificaciones")
    .select("id, perfil_id, titulo, cuerpo, ruta, liga_id")
    .eq("push_estado", "pendiente")
    .order("id")
    .limit(200);
  if (error) return Response.json({ ok: false, error: error.message }, { status: 500 });
  if (!pendientes?.length) return Response.json({ ok: true, enviadas: 0 });

  const perfiles = [...new Set(pendientes.map((n) => n.perfil_id))];
  const { data: disp } = await sb.from("dispositivos").select("token, perfil_id").in("perfil_id", perfiles);
  const porPerfil = new Map<string, string[]>();
  for (const d of disp ?? []) porPerfil.set(d.perfil_id, [...(porPerfil.get(d.perfil_id) ?? []), d.token]);

  const acceso = await tokenGoogle(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let enviadas = 0;

  for (const n of pendientes) {
    const tokens = porPerfil.get(n.perfil_id) ?? [];
    let estado = tokens.length ? "error" : "sin_dispositivo";
    for (const token of tokens) {
      const r = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${acceso}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: n.titulo, body: n.cuerpo },
            data: { ruta: n.ruta ?? "", liga_id: n.liga_id ?? "", id: String(n.id) },
            android: { priority: "HIGH", notification: { tag: String(n.id) } },
          },
        }),
      });
      if (r.ok) {
        estado = "enviada";
        enviadas++;
      } else {
        const cuerpo = await r.text();
        // Token caducado o app desinstalada: se borra
        if (r.status === 404 || cuerpo.includes("UNREGISTERED") || cuerpo.includes("INVALID_ARGUMENT")) {
          await sb.from("dispositivos").delete().eq("token", token);
        }
      }
    }
    await sb.from("notificaciones").update({ push_estado: estado }).eq("id", n.id);
  }
  return Response.json({ ok: true, enviadas, procesadas: pendientes.length });
});
