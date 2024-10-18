import { SupabaseClient } from '@supabase/supabase-js';
import { SearchResult } from './search';
import { Fetch } from '@supabase/auth-js/src/lib/fetch';

export async function getStatisticalUnits(client: SupabaseClient, searchParams: URLSearchParams): Promise<SearchResult> {
  // Inspect inside the client and get the correct url,
  // as server side and client side code uses different urls.
  // due to running inside docker containers.
  const apiFetcher = (client as any).rest.fetch as Fetch;
  const supabase_url = (client as any).rest.url as String
  var response = await apiFetcher(
    `${supabase_url}/statistical_unit?${searchParams}`,
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
