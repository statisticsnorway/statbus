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
