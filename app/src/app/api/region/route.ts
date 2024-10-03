import { createClient } from "@/utils/supabase/server";
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const client = createClient();

  let query = client.from('region')
    .select(
      searchParams.get("select") || "*",
      { count: 'exact', head: true }
    );
  if (!searchParams.has("order")) {
    query = query.order("path");
  }
  if (!searchParams.has("limit")) {
    query = query.limit(10);
  }

  const { data: regions, error, status, count } = await query;

  if (error && status !== 406) {
    console.log(error);
    throw error;
  }
  return NextResponse.json({
    regions,
    count,
  });
}
