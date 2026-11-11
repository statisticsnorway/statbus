/**
 * API keys (public.api_key): a user's long-lived tokens for scripted access to
 * the REST API. Shown and copied from the command palette's "Show API key".
 */
import type { PostgrestClient } from "@supabase/postgrest-js";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type RpcClient = PostgrestClient<any, any, any>;

export interface ApiKeyRow {
  jti: string;
  description: string | null;
  created_at: string | null;
  expires_at: string | null;
}

const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * The display name inside an API key token. A key's claims are fixed when it is
 * created (auth.generate_api_key_token), so after the user's name changes in
 * the profile the key still carries the old one; tools that read the token,
 * such as the www.statbus.org course certificate, show that name. Null when
 * the token has no display name or cannot be read.
 */
export function tokenDisplayName(token: string): string | null {
  const payload = token.split(".")[1];
  if (!payload) return null;
  try {
    const base64 = payload.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(payload.length / 4) * 4, "=");
    const bytes = Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
    const claims = JSON.parse(new TextDecoder().decode(bytes));
    return typeof claims.display_name === "string" && claims.display_name ? claims.display_name : null;
  } catch {
    return null;
  }
}

/**
 * How long a key stays valid, for the dialog: its expiry as an ISO date and
 * the whole days left (0 once expired). Null for a key without an expiry.
 */
export function keyValidity(
  expiresAt: string | null,
  now: Date = new Date()
): { validUntil: string; daysLeft: number; expired: boolean } | null {
  if (!expiresAt) return null;
  const expires = new Date(expiresAt);
  const msLeft = expires.getTime() - now.getTime();
  return {
    validUntil: expires.toISOString().slice(0, 10),
    daysLeft: msLeft > 0 ? Math.floor(msLeft / DAY_MS) : 0,
    expired: msLeft <= 0,
  };
}

/** The key's lifetime in whole days, as create_api_key's duration; a year when it is not known. */
function lifetime(key: ApiKeyRow): string {
  if (!key.created_at || !key.expires_at) return "365 days";
  const days = Math.round((Date.parse(key.expires_at) - Date.parse(key.created_at)) / DAY_MS);
  return `${days > 0 ? days : 365} days`;
}

/**
 * Replaces a key the user wants to stop using, e.g. one that was exposed
 * (STATBUS-617). The new key gets the same description and lifetime; the old
 * one is revoked only once the new one exists, so a failure leaves the user
 * with a working key. A revoked token is refused at once
 * (auth.check_api_key_revocation).
 */
export async function recreateApiKey(client: RpcClient, current: ApiKeyRow): Promise<{ jti: string; token: string }> {
  const created = await client.rpc("create_api_key", {
    description: current.description ?? "Default API Key",
    duration: lifetime(current),
  });
  if (created.error) throw new Error(created.error.message);
  const revoked = await client.rpc("revoke_api_key", { key_jti: current.jti });
  if (revoked.error) throw new Error(revoked.error.message);
  return { jti: created.data.jti, token: created.data.token };
}
