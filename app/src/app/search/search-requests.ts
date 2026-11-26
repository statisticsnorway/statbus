import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';
import { parseQualityCheckParam } from '@/lib/quality-checks';
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from '@/lib/unit-existence';
import { QUALITY_CHECK_PARAM, qualitySearchResource, type QualitySearchResource } from './quality-search';

/**
 * The PostgREST path and parameters a search reads: statistical_unit, or for a quality search the
 * resource qualitySearchResource chooses by the check's count at the time frame, which is read from
 * quality_finding first (one count on its 14 MB index, milliseconds).
 */
export async function resolveSearchResource(
  client: PostgrestClient<Database>,
  searchParams: URLSearchParams,
  signal?: AbortSignal
): Promise<QualitySearchResource> {
  const parsed = parseQualityCheckParam(searchParams.get(QUALITY_CHECK_PARAM));
  if (!parsed) return { path: 'statistical_unit', params: searchParams };
  const params = new URLSearchParams(searchParams);
  params.delete(QUALITY_CHECK_PARAM);
  const validOn = /^lte\.(.+)$/.exec(params.get(EXISTENCE_FROM) ?? '')?.[1];
  if (!validOn || !params.get(EXISTENCE_UNTIL)) {
    throw new Error('A quality search needs the time frame');
  }
  let statDefinitionId: number | null = null;
  if (parsed.statCode) {
    const { data, error } = await client
      .from('stat_definition')
      .select('id')
      .eq('code', parsed.statCode)
      .abortSignal(signal ?? new AbortController().signal)
      .maybeSingle();
    if (error) throw new Error(`Reading the variable ${parsed.statCode} failed: ${error.message}`);
    if (!data) throw new Error(`No statistical variable ${parsed.statCode}`);
    statDefinitionId = data.id;
  }
  let count = client
    .from('quality_finding')
    .select('', { count: 'exact', head: true })
    .eq('rule', parsed.rule)
    .lte('existence_from', validOn)
    .gt('existence_until', validOn);
  count = statDefinitionId === null ? count.is('stat_definition_id', null) : count.eq('stat_definition_id', statDefinitionId);
  const { count: units, error } = await count.abortSignal(signal ?? new AbortController().signal);
  if (error || units === null) {
    throw new Error(`Counting the check ${parsed.rule} failed: ${error?.message ?? 'no count'}`);
  }
  return qualitySearchResource(params, { rule: parsed.rule, statDefinitionId }, units);
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
  const resource = await resolveSearchResource(client, searchParams, signal);
  const url = new URL(`${resource.path}?${resource.params}`, baseUrl);

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

  const resource = await resolveSearchResource(client, searchParams, signal);
  const countParams = new URLSearchParams(resource.params);
  countParams.set('limit', '0');
  countParams.set('offset', '0');

  const url = new URL(`${resource.path}?${countParams}`, baseUrl);

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
