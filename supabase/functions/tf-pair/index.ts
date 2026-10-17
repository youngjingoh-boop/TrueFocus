// TrueFocus device linking.
//
//   POST { action: "create", key }  -> { code, expires_at }   (device that has the key)
//   POST { action: "redeem", code } -> { key }                 (device joining)
//
// Codes are 6 digits, live 10 minutes, work once. Failed redeems are counted globally and
// the endpoint locks for everyone after 40 misses in 10 minutes, which keeps guessing a
// code impractical. Tables are service-role only.
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const TEN_MINUTES = 10 * 60 * 1000;
const MAX_FAILURES = 40;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function sixDigits(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: { action?: string; key?: string; code?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  const now = Date.now();
  await db.from("tf_pairings").delete().lt("expires_at", new Date(now).toISOString());

  if (body.action === "create") {
    const key = (body.key ?? "").trim();
    if (key.length < 32 || key.length > 256) return json({ error: "invalid key" }, 400);
    const expires = new Date(now + TEN_MINUTES).toISOString();
    for (let attempt = 0; attempt < 5; attempt++) {
      const code = sixDigits();
      const { error } = await db.from("tf_pairings").insert({ code, space_key: key, expires_at: expires });
      if (!error) return json({ code, expires_at: expires });
    }
    return json({ error: "try again" }, 503);
  }

  if (body.action === "redeem") {
    const code = (body.code ?? "").replace(/\D/g, "");
    if (code.length !== 6) return json({ error: "invalid code" }, 400);

    const since = new Date(now - TEN_MINUTES).toISOString();
    const { count } = await db.from("tf_pair_failures").select("*", { count: "exact", head: true }).gte("at", since);
    if ((count ?? 0) >= MAX_FAILURES) return json({ error: "too many attempts, wait a few minutes" }, 429);

    const { data } = await db.from("tf_pairings").select("space_key, expires_at").eq("code", code).maybeSingle();
    if (!data || new Date(data.expires_at).getTime() < now) {
      await db.from("tf_pair_failures").insert({});
      return json({ error: "code not found or expired" }, 404);
    }
    await db.from("tf_pairings").delete().eq("code", code);
    await db.from("tf_pair_failures").delete().lt("at", since);
    return json({ key: data.space_key });
  }

  return json({ error: "unknown action" }, 400);
});
