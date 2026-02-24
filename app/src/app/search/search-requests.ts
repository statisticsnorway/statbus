import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';

/**
 * Result type for data fetch with estimated count.
 */
export interface SearchDataResult {
  statisticalUnits: SearchResult['statisticalUnits'];
  estimatedCount: number | null;
}

function parseContentRangeCount(response: Response): number | null {
  const count_str = response.headers.get("content-range")?.split("/")[1];
  if (!count_str || count_str === "*") return null;
  return parseInt(count_str, 10);
}

async function getRestClient(client: PostgrestClient<Database> | null): Promise<PostgrestClient<Database>> {
  return client ?? await getServerRestClient();
}

/**
 * Fetch statistical units data with estimated count (fast).
 * Returns rows + planner estimate in a single request.
 */
export async function getStatisticalUnitsData(
  client: PostgrestClient<Database> | null = null,
  searchParams: URLSearchParams
): Promise<SearchDataResult> {
  const isServer = typeof window === 'undefined';
  client = await getRestClient(client);

  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  const url = new URL(`statistical_unit?${searchParams}`, baseUrl);

  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  const response = await fetcher(url.toString(), {
    method: "GET",
    headers: {
      Prefer: "count=estimated",
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
    estimatedCount: parseContentRangeCount(response),
  };
}

/**
 * Fetch exact count for statistical units (slow on large datasets).
 * Use in background after table has rendered with estimated count.
 */
export async function getStatisticalUnitsExactCount(
  client: PostgrestClient<Database> | null = null,
  searchParams: URLSearchParams
): Promise<number> {
  const isServer = typeof window === 'undefined';
  client = await getRestClient(client);

  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;

  const countParams = new URLSearchParams(searchParams);
  countParams.set('limit', '0');
  countParams.set('offset', '0');

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

  return parseContentRangeCount(response) ?? 0;
}

/**
 * Fetch statistical units with exact count (used by CSV export).
 * This is intentionally slow (count=exact) since the export fetches up to 100k rows anyway.
 */
export async function getStatisticalUnits(
  client: PostgrestClient<Database> | null = null,
  searchParams: URLSearchParams
): Promise<SearchDataResult> {
  const isServer = typeof window === 'undefined';
  client = await getRestClient(client);

  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  const url = new URL(`statistical_unit?${searchParams}`, baseUrl);

  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  const response = await fetcher(url.toString(), {
    method: "GET",
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

  const data = await response.json();

  return {
    statisticalUnits: data,
    estimatedCount: parseContentRangeCount(response),
  };
}
