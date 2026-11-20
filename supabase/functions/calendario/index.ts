// Calendario suscribible de una liga (.ics). Lo piden las apps de calendario sin sesión:
//   https://<proyecto>.supabase.co/functions/v1/calendario?t=<token del jugador>
// El token (64 caracteres, en miembros.token_calendario) hace de contraseña. Se despliega con verify_jwt = false.
import { createClient } from "jsr:@supabase/supabase-js@2";

// Clave de servidor: nunca sale de aquí y solo se usa para llamar a calendario_ics.
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const token = (url.searchParams.get("t") ?? "").replace(/\.ics$/, "");
  if (token.length < 32) return new Response("Calendario no encontrado", { status: 404 });

  const { data, error } = await sb.rpc("calendario_ics", { p_token: token });
  if (error) return new Response("Error al generar el calendario", { status: 502 });
  if (!data) return new Response("Calendario no encontrado", { status: 404 });

  return new Response(data as string, {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="futbol-fantasy.ics"',
      "Cache-Control": "public, max-age=900",
    },
  });
});
