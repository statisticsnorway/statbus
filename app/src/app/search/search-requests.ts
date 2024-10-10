import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function getStatisticalUnits(searchParams: URLSearchParams) {
  const client = await createSupabaseSSRClient();
  const apiFetcher = async (url: string, init: RequestInit) => {
      const session = await client.auth.getSession();
      return fetch(url, {
        ...init,
        headers: {
          ...init.headers,
          Authorization: `Bearer ${session.data.session?.access_token}`,
          apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        },
      });
    };

  var response = await apiFetcher(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/statistical_unit?${searchParams}`,
    {
      method: "GET",
      headers: {
        Prefer: "count=exact",
        "Range-Unit": "items",
      },
    }
  ) as Response;

  if (!response.ok) {
    return { error: response.statusText };
  }

  const data = await response.json();
  const count_str = response.headers.get("content-range")?.split("/")[1]
  const count = parseInt(count_str ?? "0", 10);

  // What is a suitable return structure?
  // Either an error or the data?
  return {
    statistical_units: data,
    count: count,
    status: response.status,
    statusText: response.statusText,
    ok: response.ok
  };
}
