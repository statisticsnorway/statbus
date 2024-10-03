import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/utils/supabase/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const client = await createClient();
  const selectParam = searchParams.get("select") || "*";
  const rangeStart = searchParams.get("range-start");
  const rangeEnd = searchParams.get("range-end");

  let query = client
    .from('statistical_unit')
    .select(selectParam, { count: 'exact' });

  if (rangeStart !== null && rangeEnd !== null) {
    query = query.range(parseInt(rangeStart, 10), parseInt(rangeEnd, 10));
  }

  const { data: statisticalUnits, error, count } = await query;

  if (error) {
    return NextResponse.json({ error: error.message });
  }

  return NextResponse.json({
    statisticalUnits,
    count,
  });
}
