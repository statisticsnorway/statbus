import { SupabaseClient } from '@supabase/supabase-js';
import { SearchResult } from './search';
import { Fetch } from '@supabase/auth-js/src/lib/fetch';

export async function getStatisticalUnits(client: SupabaseClient, searchParams: URLSearchParams): Promise<SearchResult> {
  // Extract the API URL and fetcher from the client
  // We use the Supabase client for type safety, but extract these properties
  // to make direct API calls to PostgREST with our custom authentication.
  // We're NOT using Supabase as a service, only their client libraries.
  // This approach gives us more control over the request while still
  // benefiting from the type safety and consistent API of the Supabase client
  const apiFetcher = (client as any).rest.fetch as Fetch;
  const api_url = (client as any).rest.url as String
  var response = await apiFetcher(
    `${api_url}/statistical_unit?${searchParams}`,
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
