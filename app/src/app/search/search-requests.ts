import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";

export async function getStatisticalUnits(searchParams: URLSearchParams) {
  const authFetch = setupAuthorizedFetchFn();
  return await authFetch(
    `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/statistical_unit?${searchParams}`,
    {
      method: "GET",
      headers: {
        Prefer: "count=exact",
        "Range-Unit": "items",
      },
    }
  );
}
