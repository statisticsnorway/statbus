import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';

function parseContentRangeCount(response: Response): number | null {
  const count_str = response.headers.get("content-range")?.split("/")[1];
  if (!count_str || count_str === "*") return null;
  return parseInt(count_str, 10);
}

async function getRestClient(client: PostgrestClient<Database> | null): Promise<PostgrestClient<Database>> {
  return client ?? await getServerRestClient();
}

/**
 * Fetch one page of statistical units, without a count: the total comes from
 * getStatisticalUnitsExactCount, so the page shows while the count runs.
 * (PostgREST's count=estimated runs the exact count when db-max-rows is unset,
 * fc9xbd, so asking for it here would count twice.)
 */
export async function getStatisticalUnitsData(
  client: PostgrestClient<Database> | null = null,
  searchParams: URLSearchParams,
  signal?: AbortSignal
): Promise<SearchResult['statisticalUnits']> {
  const isServer = typeof window === 'undefined';
  client = await getRestClient(client);

  const baseUrl = client.url.endsWith('/') ? client.url : `${client.url}/`;
  const url = new URL(`statistical_unit?${searchParams}`, baseUrl);

  const fetcher = isServer ? fetchWithAuth : fetchWithAuthRefresh;

  const response = await fetcher(url.toString(), {
    method: "GET",
    signal,
    headers: {
      "Content-Type": "application/json",
      "Accept": "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Error: ${response.statusText} (Status: ${response.status})`);
  }

  return response.json();
}

/**
 * Fetch the exact count for statistical units: one count per search, run
 * after the page of rows has shown.
 */
export async function getStatisticalUnitsExactCount(
  client: PostgrestClient<Database> | null = null,
  searchParams: URLSearchParams,
  signal?: AbortSignal
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
    signal,
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
