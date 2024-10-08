import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function getStatisticalUnits(searchParams: URLSearchParams) {
  const client = await createSupabaseSSRClient();
  const rangeStart = searchParams.get("range-start");
  const rangeEnd = searchParams.get("range-end");

  let query = client
    .from('statistical_unit')
    .select("*", { count: 'exact' });
    //.select(selectParam, { count: 'exact' });

  if (rangeStart !== null && rangeEnd !== null) {
    query = query.range(parseInt(rangeStart, 10), parseInt(rangeEnd, 10));
  }

  const response = await query;

  if (response.error) {
    throw new Error(response.error.message);
  }

  return {
    statistical_units: response.data,
    count: response.count,
    status: response.status,
    statusText: response.statusText,
  };
}
