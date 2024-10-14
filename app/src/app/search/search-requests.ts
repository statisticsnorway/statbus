import { SupabaseClient } from '@supabase/supabase-js';
import { SearchResult } from './search';

export async function getStatisticalUnits(client: SupabaseClient, searchParams: URLSearchParams): Promise<SearchResult> {
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
    throw new Error(`Error: ${response.statusText} (Status: ${response.status})`);
  }

  const data = await response.json();
  const count_str = response.headers.get("content-range")?.split("/")[1]
  const count = parseInt(count_str ?? "0", 10);

  return {
      statisticalUnits: data,
      count: count,
    };
}
