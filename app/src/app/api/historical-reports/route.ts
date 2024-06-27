import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const client = createClient();

  let query = client.from("statistical_history").select();

  if (searchParams.has("year")) {
    query = query.eq("year", searchParams.get("year"));
  }
  if (searchParams.has("unit_type")) {
    query = query.eq("unit_type", searchParams.get("unit_type"));
  }

  if (searchParams.has("type")) {
    query = query.eq("type", searchParams.get("type"));
  }

  const history = await query;

  const mappedHistoryData = history.data?.map(
    ({ count, type, year, month }) => ({
      type: type,
      year: year,
      y: count,
      name: `${year}${month ? `-${month}` : ""}`,
    })
  );
  return NextResponse.json(mappedHistoryData);
}
