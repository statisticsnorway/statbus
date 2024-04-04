import { NextResponse } from "next/server";
import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";

export async function GET(request: Request) {
  const { searchParams: requestParams } = new URL(request.url);
  const params = new URLSearchParams(requestParams);
  const authFetch = setupAuthorizedFetchFn();
  const response = await authFetch(
    `${process.env.SUPABASE_URL}/rest/v1/rpc/statistical_unit_facet_drilldown?${params}`,
    {
      method: "GET",
    }
  );

  if (!response.ok) {
    return NextResponse.json({ error: response.statusText });
  }

  const data = await response.json();
  return NextResponse.json(data);
}
