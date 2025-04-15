import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { getServerRestClient } from '@/context/RestClientStore';

export async function getStatisticalUnits(client: PostgrestClient<Database> | null = null, searchParams: URLSearchParams): Promise<SearchResult> {
  // If no client is provided, get one from RestClientStore
  if (!client) {
    client = await getServerRestClient();
  }
  // Use the PostgrestClient directly
  const url = new URL(`statistical_unit?${searchParams}`, client.url);
  
  // Use the fetch method with proper headers
  const response = await fetch(url, {
    method: "GET",
    headers: {
      Prefer: "count=exact",
      "Range-Unit": "items",
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
    credentials: 'include', // Include cookies for auth
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
