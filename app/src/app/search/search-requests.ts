import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';

export async function getStatisticalUnits(client: PostgrestClient<Database> | null = null, searchParams: URLSearchParams): Promise<SearchResult> {
  const isServer = typeof window === 'undefined';
  // If no client is provided, get one from RestClientStore
  if (!client) {
    client = await getServerRestClient();
  }
  // Use the PostgrestClient directly, that searchParams that is properly formatted for PostgREST can be used directly.
  // Ensure the base URL ends with a slash for proper URL construction
  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  const url = new URL(`statistical_unit?${searchParams}`, baseUrl);
  
  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  // Use the appropriate fetch function for the environment
  const response = await fetcher(url.toString(), {
    method: "GET",
    headers: {
      Prefer: "count=exact",
      "Range-Unit": "items",
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    // No credentials needed, fetchWithAuth/fetchWithAuthRefresh handles auth
  });

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
