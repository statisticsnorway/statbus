import { NextResponse } from "next/server";
import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const authFetch = setupAuthorizedFetchFn();

  const response = await authFetch(
    `${process.env.SUPABASE_URL}/rest/v1/statistical_unit?${searchParams}`,
    {
      method: "GET",
      headers: {
        Prefer: "count=exact",
        "Range-Unit": "items",
      },
    }
  );

  if (!response.ok) {
    return NextResponse.json({ error: response.statusText }, { status: response.status });
  }

  const statisticalUnits = await response.json();
  const count = response.headers.get("content-range")?.split("/")[1];
  return NextResponse.json({
    statisticalUnits,
    count: parseInt(count ?? "-1", 10),
  });
}
