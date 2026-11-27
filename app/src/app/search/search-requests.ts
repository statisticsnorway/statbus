import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { SearchResult } from './search';
import { fetchWithAuth, fetchWithAuthRefresh, getServerRestClient } from '@/context/RestClientStore';
import { parseQualityCheckParam } from '@/lib/quality-checks';
import { EXISTENCE_FROM, EXISTENCE_UNTIL } from '@/lib/unit-existence';
import { QUALITY_CHECK_PARAM, qualitySearchResource, type QualitySearchResource } from './quality-search';
import type { QualityCheckCount } from '@/app/dashboard/quality-checks-data';

/**
 * The PostgREST path and parameters a search reads: statistical_unit, or for a quality search the
 * resource qualitySearchResource chooses by the check's count at the time frame. The URL's
 * rule[:code] is mapped to the check's id and kind through public.quality_check, and the count is
 * read first from public.quality_check_count (milliseconds).
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
  const abort = signal ?? new AbortController().signal;
  let statDefinitionId: number | null = null;
  if (parsed.statCode) {
    const { data, error } = await client
      .from('stat_definition')
      .select('id')
      .eq('code', parsed.statCode)
      .abortSignal(abort)
      .maybeSingle();
    if (error) throw new Error(`Reading the variable ${parsed.statCode} failed: ${error.message}`);
    if (!data) throw new Error(`No statistical variable ${parsed.statCode}`);
    statDefinitionId = data.id;
  }
  let checkQuery = client.from('quality_check').select('id,kind').eq('rule', parsed.rule);
  checkQuery = statDefinitionId === null
    ? checkQuery.is('stat_definition_id', null)
    : checkQuery.eq('stat_definition_id', statDefinitionId);
  const { data: check, error: checkError } = await checkQuery.abortSignal(abort).maybeSingle();
  if (checkError) throw new Error(`Reading the check ${parsed.rule} failed: ${checkError.message}`);
  if (!check) throw new Error(`No quality check ${parsed.rule}${parsed.statCode ? `:${parsed.statCode}` : ''}`);
  const { data: counts, error } = await client
    .rpc('quality_check_count', { valid_on: validOn })
    .eq('check_id', check.id)
    .abortSignal(abort);
  if (error || !counts) {
    throw new Error(`Counting the check ${parsed.rule} failed: ${error?.message ?? 'no count'}`);
  }
  // A check not in use (public.in_use, bxt67q) is absent from the counts: it lists no units.
  const units = (counts as unknown as QualityCheckCount[])[0]?.units ?? 0;
  return qualitySearchResource(params, { id: check.id, rule: parsed.rule, kind: check.kind }, units);
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
