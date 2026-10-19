// TrueFocus space maintenance, for the device that holds the space.
//
//   POST (x-tf-space: <legacy space key>) { action: "rekey", access } -> { moved }
//     One-time move of a space from its legacy id, sha256(space key), to sha256(access token).
//     Builds before access tokens keyed spaces by the key itself; each device calls this once,
//     the last time the raw key travels. Merges by last writer wins (the tf_records_stamp
//     trigger skips an older modified_at), so devices can upgrade in any order.
//
//   POST (x-tf-space: <access token>) { action: "delete" } -> { ok }
//     Deletes every record and push token the server holds for the space ("Delete server copy").
//
// Service role, scoped to the space the header proves membership of.
import { createClient } from "jsr:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const PAGE = 500;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** The space for a header value, as public.tf_space() computes it. */
async function spaceFor(header: string | null): Promise<string | null> {
  const h = header ?? "";
  return h.length >= 32 && h.length <= 256 ? await sha256Hex(h) : null;
}

async function rekey(from: string, to: string): Promise<number> {
  let moved = 0;
  for (let offset = 0; ; offset += PAGE) {
    const { data, error } = await db.from("tf_records")
      .select("id, kind, data, deleted, modified_at")
      .eq("space", from).order("id").range(offset, offset + PAGE - 1);
    if (error) throw error;
    if (!data || data.length === 0) break;
    const rows = data.map((r) => ({ ...r, space: to }));
    const { error: upsertError } = await db.from("tf_records").upsert(rows, { onConflict: "space,id" });
    if (upsertError) throw upsertError;
    moved += rows.length;
    if (data.length < PAGE) break;
  }
  const { data: devices, error: devicesError } = await db.from("tf_devices")
    .select("token, platform, environment, updated_at").eq("space", from);
  if (devicesError) throw devicesError;
  if (devices && devices.length > 0) {
    const { error } = await db.from("tf_devices")
      .upsert(devices.map((d) => ({ ...d, space: to })), { onConflict: "space,token" });
    if (error) throw error;
  }
  // Only once everything is copied: a failure above leaves the legacy space intact to retry.
  await remove(from);
  return moved;
}

async function remove(space: string): Promise<void> {
  const records = await db.from("tf_records").delete().eq("space", space);
  if (records.error) throw records.error;
  const devices = await db.from("tf_devices").delete().eq("space", space);
  if (devices.error) throw devices.error;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let body: { action?: string; access?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid json" }, 400);
  }
  const space = await spaceFor(req.headers.get("x-tf-space"));
  if (!space) return json({ error: "invalid space" }, 400);

  try {
    if (body.action === "rekey") {
      const target = await spaceFor(typeof body.access === "string" ? body.access : null);
      if (!target) return json({ error: "invalid access" }, 400);
      if (target === space) return json({ moved: 0 });
      return json({ moved: await rekey(space, target) });
    }
    if (body.action === "delete") {
      await remove(space);
      return json({ ok: true });
    }
  } catch (error) {
    console.error("tf-space", body.action, error);
    return json({ error: "server error" }, 500);
  }
  return json({ error: "unknown action" }, 400);
});
