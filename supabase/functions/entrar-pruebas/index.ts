// Cuentas de prueba: escribir «admin1» … «admin5» en el campo del email entra sin código.
// POST {codigo} → {email, token}; la app hace verifyOTP(email, token, type: email).
// Solo funciona si config_pruebas.activo = true (apagar antes de publicar). verify_jwt = false.
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const json = (o: unknown, status = 200) => Response.json(o, { status, headers: cors });
  try {
    const { codigo } = await req.json().catch(() => ({ codigo: "" }));
    const m = String(codigo ?? "").toLowerCase().replace(/[\s_-]/g, "").match(/^admin([1-5])$/);
    if (!m) return json({ error: "codigo_no_valido" }, 400);

    const { data: cfg } = await sb.from("config_pruebas").select("activo").eq("id", 1).maybeSingle();
    if (!cfg?.activo) return json({ error: "pruebas_desactivadas" }, 403);

    const n = m[1];
    const email = `admin${n}@pruebas.futbolfantasy.app`;

    // Crea la cuenta la primera vez (ya confirmada) y su perfil
    const creado = await sb.auth.admin.createUser({ email, email_confirm: true });
    let uid = creado.data.user?.id;
    if (!uid) {
      const { data } = await sb.auth.admin.generateLink({ type: "magiclink", email });
      uid = data.user?.id;
    }
    if (uid) {
      await sb.from("perfiles").upsert({ id: uid, nombre: `Admin ${n}`, apodo: `Admin${n}` }, {
        onConflict: "id",
        ignoreDuplicates: true,
      });
    }

    // Código de un solo uso, como el del correo, pero sin enviarlo
    const { data, error } = await sb.auth.admin.generateLink({ type: "magiclink", email });
    if (error || !data?.properties?.email_otp) return json({ error: "no_se_pudo_generar" }, 500);
    return json({ email, token: data.properties.email_otp });
  } catch (_) {
    return json({ error: "error" }, 500);
  }
});
