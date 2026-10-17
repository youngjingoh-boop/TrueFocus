// TrueFocus wake-up: after a device uploads changes it calls this, and every other iPhone in
// the same space gets a silent push so it syncs in the background (Lock Screen, Live Activity,
// shields follow a session started on the Mac).
//
//   POST (header x-tf-space: <key>) { except_token? } -> { sent, skipped? }
//
// Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_PRIVATE_KEY (.p8 contents), optional APNS_TOPIC.
// Without them it answers { sent: 0, skipped: "apns not configured" } and devices fall back to
// syncing whenever they're opened.
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const PRIVATE_KEY = (Deno.env.get("APNS_PRIVATE_KEY") ?? "").replace(/\\n/g, "\n");
const TOPIC = Deno.env.get("APNS_TOPIC") ?? "com.youngjingoh.truefocus";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

function b64url(bytes: Uint8Array | string): string {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

let cachedJWT: { token: string; at: number } | null = null;

async function apnsJWT(): Promise<string> {
  if (cachedJWT && Date.now() - cachedJWT.at < 40 * 60 * 1000) return cachedJWT.token;
  const pem = PRIVATE_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${header}.${claims}`)),
  );
  const token = `${header}.${claims}.${b64url(signature)}`;
  cachedJWT = { token, at: Date.now() };
  return token;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  const spaceKey = req.headers.get("x-tf-space") ?? "";
  if (spaceKey.length < 32) return json({ error: "missing space" }, 400);
  let exceptToken = "";
  try {
    exceptToken = (await req.json())?.except_token ?? "";
  } catch { /* empty body is fine */ }

  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY) return json({ sent: 0, skipped: "apns not configured" });

  const space = await sha256Hex(spaceKey);
  const { data: devices } = await db.from("tf_devices").select("token, environment")
    .eq("space", space).eq("platform", "ios");

  const jwt = await apnsJWT();
  let sent = 0;
  for (const device of devices ?? []) {
    if (device.token === exceptToken) continue;
    const host = device.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
    const res = await fetch(`https://${host}/3/device/${device.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": TOPIC,
        "apns-push-type": "background",
        "apns-priority": "5",
      },
      body: JSON.stringify({ aps: { "content-available": 1 }, tf: "sync" }),
    });
    if (res.ok) {
      sent++;
    } else if (res.status === 410 || res.status === 400) {
      const reason = (await res.json().catch(() => ({})))?.reason ?? "";
      if (res.status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") {
        await db.from("tf_devices").delete().eq("space", space).eq("token", device.token);
      }
    }
  }
  return json({ sent });
});
