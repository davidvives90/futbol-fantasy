// Responder «Voy / No voy» desde los botones de la notificación, sin abrir la app:
//   https://<proyecto>.supabase.co/functions/v1/responder?t=<token>&p=<partido>&r=voy|no
// El token (64 caracteres, tabla tokens_aviso, solo legible por el servidor) hace de contraseña.
// Se despliega con verify_jwt = false. Devuelve JSON {estado} o una página corta si se abre en el navegador.
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const textos: Record<string, string> = {
  confirmado: "¡Apuntado! ✅",
  espera: "Estás en lista de espera ⏳",
  baja: "Hecho: no vas ❌",
  cerrado: "Este partido ya no admite cambios",
  no_valido: "Enlace no válido",
};

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const t = url.searchParams.get("t") ?? "";
  const p = url.searchParams.get("p") ?? "";
  const r = url.searchParams.get("r") ?? "";
  let estado = "no_valido";
  if (t.length >= 32 && /^[0-9a-f-]{36}$/i.test(p) && (r === "voy" || r === "no")) {
    const { data, error } = await sb.rpc("responder_aviso", { p_token: t, p_partido: p, p_respuesta: r });
    if (error) return Response.json({ estado: "error" }, { status: 502 });
    estado = (data as string) ?? "no_valido";
  }
  if ((req.headers.get("accept") ?? "").includes("text/html")) {
    const html = `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">` +
      `<body style="font-family:sans-serif;text-align:center;padding:48px"><h2>${textos[estado] ?? estado}</h2>` +
      `<p>Fútbol Fantasy</p></body>`;
    return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8" } });
  }
  return Response.json({ estado });
});
