import { createClient } from "@/utils/supabase/server";

/**
 * This function returns a fetch function that is authorized to access Supabase REST API.
 */
export const setupAuthorizedFetchFn = () => {
  const supabase = createClient(null);
  return async (url: string, init: RequestInit) => {
    const session = await supabase.client.auth.getSession();
    return fetch(url, {
      ...init,
      headers: {
        ...init.headers,
        Authorization: `Bearer ${session.data.session?.access_token}`,
        apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      },
    });
  };
};
