import { setupAuthorizedFetchFn } from "@/lib/supabase/request-helper";
import { NextResponse } from "next/server";
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const authFetch = setupAuthorizedFetchFn();

  if (!searchParams.has("select")) {
    searchParams.set("select", "*");
  }
  if (!searchParams.has("order")) {
    searchParams.set("order", "path");
  }
  if (!searchParams.has("limit")) {
    searchParams.set("limit", "10");
  }

  const response = await authFetch(
    `${process.env.SUPABASE_URL}/rest/v1/activity_category_available?${searchParams}`,
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
  const activityCategories = await response.json();
  const count = response.headers.get("content-range")?.split("/")[1];
  return NextResponse.json({
    activityCategories,
    count: parseInt(count ?? "-1", 10),
  });
}
