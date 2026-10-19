// TrueFocus device linking. The server relays public keys and a sealed box; it never sees
// the space key.
//
//   host  { pk }            -> { code, expires_at }  device that has the key shows the code
//   join  { code, pk }      -> { host_pk }           device joining types it in
//   wait  { code, host_pk } -> { guest_pk | null }   host polls for the joiner
//   seal  { code, host_pk, box } -> { ok }           host sends the key, sealed to the joiner,
//                                                    once both screens show the same match number
//   fetch { code, pk }      -> { box | null }       joiner polls; the code is gone after this
//
// Both devices derive the box key and a 4-digit match number from an X25519 exchange, so a
// server that swapped the public keys would show two different numbers.
//
// Codes are 6 digits, live 10 minutes, link one device. Failed joins are counted globally and
// the endpoint locks for everyone after 40 misses in 10 minutes. Tables are service-role only.
//
// Legacy (builds before end-to-end linking): create { key } / redeem { code } -> { key }.
// Remove once no device runs such a build.
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const TEN_MINUTES = 10 * 60 * 1000;
const MAX_FAILURES = 40;

type Body = { action?: string; key?: string; code?: string; pk?: string; host_pk?: string; box?: string };

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

/** A base64 X25519 public key (32 bytes, 44 characters). */
function publicKey(value: unknown): string | null {
  const s = typeof value === "string" ? value.trim() : "";
  return /^[A-Za-z0-9+/]{43}=$/.test(s) ? s : null;
}

function digits(value: unknown): string | null {
  const s = (typeof value === "string" ? value : "").replace(/\D/g, "");
  return s.length === 6 ? s : null;
}

async function insertWithCode(row: Record<string, unknown>, expires: string): Promise<Response> {
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = sixDigits();
    const { error } = await db.from("tf_pairings").insert({ code, expires_at: expires, ...row });
    if (!error) return json({ code, expires_at: expires });
  }
  return json({ error: "try again" }, 503);
}

async function tooManyFailures(now: number): Promise<boolean> {
  const since = new Date(now - TEN_MINUTES).toISOString();
  const { count } = await db.from("tf_pair_failures").select("*", { count: "exact", head: true }).gte("at", since);
  return (count ?? 0) >= MAX_FAILURES;
}

async function miss(): Promise<Response> {
  await db.from("tf_pair_failures").insert({});
  return json({ error: "code not found or expired" }, 404);
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }

  const now = Date.now();
  const nowISO = new Date(now).toISOString();
  await db.from("tf_pairings").delete().lt("expires_at", nowISO);

  switch (body.action) {
    case "host": {
      const pk = publicKey(body.pk);
      if (!pk) return json({ error: "invalid key" }, 400);
      // space_key stays empty: nothing secret is stored.
      return await insertWithCode({ host_pk: pk, space_key: "" }, new Date(now + TEN_MINUTES).toISOString());
    }

    case "join": {
      const code = digits(body.code);
      const pk = publicKey(body.pk);
      if (!code || !pk) return json({ error: "invalid code" }, 400);
      if (await tooManyFailures(now)) return json({ error: "too many attempts, wait a few minutes" }, 429);
      // Only the first joiner gets in; the update is conditional so two can't race.
      const { data } = await db.from("tf_pairings").update({ guest_pk: pk })
        .eq("code", code).not("host_pk", "is", null).is("guest_pk", null).gt("expires_at", nowISO)
        .select("host_pk").maybeSingle();
      if (!data) return await miss();
      await db.from("tf_pair_failures").delete().lt("at", new Date(now - TEN_MINUTES).toISOString());
      return json({ host_pk: data.host_pk });
    }

    case "wait": {
      const code = digits(body.code);
      const hostPK = publicKey(body.host_pk);
      if (!code || !hostPK) return json({ error: "invalid code" }, 400);
      const { data } = await db.from("tf_pairings").select("guest_pk")
        .eq("code", code).eq("host_pk", hostPK).gt("expires_at", nowISO).maybeSingle();
      if (!data) return json({ error: "code not found or expired" }, 404);
      return json({ guest_pk: data.guest_pk ?? null });
    }

    case "seal": {
      const code = digits(body.code);
      const hostPK = publicKey(body.host_pk);
      const box = typeof body.box === "string" ? body.box.trim() : "";
      if (!code || !hostPK || box.length < 40 || box.length > 1024) return json({ error: "invalid box" }, 400);
      const { data } = await db.from("tf_pairings").update({ box })
        .eq("code", code).eq("host_pk", hostPK).not("guest_pk", "is", null).is("box", null).gt("expires_at", nowISO)
        .select("code").maybeSingle();
      if (!data) return json({ error: "code not found or expired" }, 404);
      return json({ ok: true });
    }

    case "fetch": {
      const code = digits(body.code);
      const guestPK = publicKey(body.pk);
      if (!code || !guestPK) return json({ error: "invalid code" }, 400);
      const { data } = await db.from("tf_pairings").select("box")
        .eq("code", code).eq("guest_pk", guestPK).gt("expires_at", nowISO).maybeSingle();
      if (!data) return json({ error: "code not found or expired" }, 404);
      if (!data.box) return json({ box: null });
      await db.from("tf_pairings").delete().eq("code", code);
      return json({ box: data.box });
    }

    // Legacy: the key itself passes through the server.
    case "create": {
      const key = (body.key ?? "").trim();
      if (key.length < 32 || key.length > 256) return json({ error: "invalid key" }, 400);
      return await insertWithCode({ space_key: key }, new Date(now + TEN_MINUTES).toISOString());
    }

    case "redeem": {
      const code = digits(body.code);
      if (!code) return json({ error: "invalid code" }, 400);
      if (await tooManyFailures(now)) return json({ error: "too many attempts, wait a few minutes" }, 429);
      const { data } = await db.from("tf_pairings").select("space_key")
        .eq("code", code).neq("space_key", "").gt("expires_at", nowISO).maybeSingle();
      if (!data) return await miss();
      await db.from("tf_pairings").delete().eq("code", code);
      await db.from("tf_pair_failures").delete().lt("at", new Date(now - TEN_MINUTES).toISOString());
      return json({ key: data.space_key });
    }
  }

  return json({ error: "unknown action" }, 400);
});
