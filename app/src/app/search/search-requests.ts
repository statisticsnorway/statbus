import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';

/**
 * Result type for data-only fetch (no count).
 */
export interface SearchDataResult {
  statisticalUnits: SearchResult['statisticalUnits'];
}

/**
 * Fetch statistical units data without any count (fastest).
 * Use this for immediate table rendering, then fetch count separately.
 */
export async function getStatisticalUnitsData(
  client: PostgrestClient<Database> | null = null, 
  searchParams: URLSearchParams
): Promise<SearchDataResult> {
  const isServer = typeof window === 'undefined';
  if (!client) {
    client = await getServerRestClient();
  }
  
  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  const url = new URL(`statistical_unit?${searchParams}`, baseUrl);
  
  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  const response = await fetcher(url.toString(), {
    method: "GET",
    headers: {
      Prefer: "count=none",
      "Range-Unit": "items",
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Error: ${response.statusText} (Status: ${response.status})`);
  }

  const data = await response.json();

  return {
    statisticalUnits: data,
  };
}

/**
 * Fetch only the count for statistical units (can be slow for large datasets).
 * Use this after the table has rendered to update the total count.
 */
export async function getStatisticalUnitsCount(
  client: PostgrestClient<Database> | null = null, 
  searchParams: URLSearchParams
): Promise<number> {
  const isServer = typeof window === 'undefined';
  if (!client) {
    client = await getServerRestClient();
  }
  
  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  
  // For count-only, we use HEAD request with limit=0 to avoid fetching data
  // Create a copy of params and set limit=0
  const countParams = new URLSearchParams(searchParams);
  countParams.set('limit', '0');
  
  const url = new URL(`statistical_unit?${countParams}`, baseUrl);
  
  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  const response = await fetcher(url.toString(), {
    method: "HEAD",
    headers: {
      Prefer: "count=exact",
      "Range-Unit": "items",
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Error: ${response.statusText} (Status: ${response.status})`);
  }

  const count_str = response.headers.get("content-range")?.split("/")[1];
  return parseInt(count_str ?? "0", 10);
}

/**
 * Legacy function that fetches both data and count in one request.
 * @deprecated Use getStatisticalUnitsData + getStatisticalUnitsCount for better UX
 */
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
