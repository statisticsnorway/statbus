import { NextRequest, NextResponse } from "next/server";
import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  // Convert URLSearchParams to object
  const requestParams: any = {};
  searchParams.forEach((value, key) => {
    requestParams[key] = value;
  });

  const client = await createSupabaseSSRClient();
  const { data, error } = await client.rpc('statistical_unit_facet_drilldown', requestParams);

  if (error) {
    return NextResponse.json({ error: error.message });
  }

  return NextResponse.json(data);
}
