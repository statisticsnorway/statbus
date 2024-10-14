import { NextRequest, NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { toCSV } from "@/lib/csv-utils";
import { createSupabaseSSRClient } from "@/utils/supabase/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("order")) {
    searchParams.set("order", "tax_ident.desc");
  }

  if (!searchParams.has("select")) {
    searchParams.set("select", "*");
  }

  searchParams.set("limit", "100000");

  searchParams.set(
    "select",
    "tax_ident, name, unit_type, primary_activity_category_id, physical_region_id, employees, turnover, physical_country_iso_2, sector_code, sector_name, legal_form_code, legal_form_name"
  );

  try {
    const client = await createSupabaseSSRClient();
    const response = await getStatisticalUnits(client, searchParams);
    const { header, body } = toCSV(response.statisticalUnits);
    return new Response(header + body, {
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": 'attachment; filename="statistical_units.csv"',
      },
    });
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
