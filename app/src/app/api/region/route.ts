import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";
import { NextResponse } from "next/server";
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("select")) {
    searchParams.set("select", "*");
  }
  if (!searchParams.has("limit")) {
    searchParams.set("limit", "10");
  }
  const authFetch = setupAuthorizedFetchFn();
  const response = await authFetch(
    `${process.env.SUPABASE_URL}/rest/v1/region?${searchParams}`,
    {
      method: "GET",
      headers: {
        Prefer: "count=exact",
        "Range-Unit": "items",
      },
    }
  );
  if (!response.ok) {
    return NextResponse.json({ error: response.statusText });
  }
  const regions = await response.json();
  const count = response.headers.get("content-range")?.split("/")[1];
  return NextResponse.json({
    regions,
    count: parseInt(count ?? "-1", 10),
  });
}
