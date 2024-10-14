import { NextRequest, NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("order")) {
    searchParams.set("order", "tax_reg_ident.desc");
  }

  if (!searchParams.has("select")) {
    searchParams.set("select", "*");
  }

  if (!searchParams.has("limit")) {
    searchParams.set("limit", "10");
  }

  const client = await createSupabaseSSRClient();
  try {
    const response = await getStatisticalUnits(client, searchParams);
    return NextResponse.json(response);
  } catch (error) {
    if (error instanceof Error) {
      // Log the error message from the error instance
      console.error('Error fetching statistical units:', error.message);
      return NextResponse.json({ error: error.message }, { status: 500 });
    } else {
      // Handle non-standard errors (if any other types could be thrown)
      console.error('Unknown error fetching statistical units:', error);
      return NextResponse.json({ error: 'An unexpected error occurred' }, { status: 500 });
    }
  }
}
