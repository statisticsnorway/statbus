import { NextRequest, NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { toCSV } from "@/lib/csv-utils";
import { createSupabaseSSRClient } from "@/utils/supabase/server";
import { getBaseData } from "@/app/BaseDataServer";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("order")) {
    searchParams.set("order", "name.asc");
  }

  const client = await createSupabaseSSRClient();
  const { externalIdentTypes, statDefinitions } = await getBaseData(client);

  const externalIdentColumns = externalIdentTypes.map(({ code }) => `${code}:external_idents->>${code}`);
  const statDefinitionColumns = statDefinitions.map(({ code }) => `${code}:stats_summary->${code}->sum`);

  searchParams.set(
    "select",
    [
      externalIdentColumns,
      [
        "name",
        "unit_type",
        "primary_activity_category_code",
        "secondary_activity_category_code",
        "physical_region_code",
      ],
      statDefinitionColumns,
      [
        "physical_country_iso_2",
        "sector_code",
       "legal_form_code",
      ]
    ].flat().join(",")
  );

  searchParams.set("limit", "100000");
  searchParams.set("offset", "0");


  try {
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
      console.error("Error fetching statistical units:", error.message);
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    // Handle non-standard errors (if any other types could be thrown)
    console.error("Unknown error fetching statistical units:", error);
    return NextResponse.json({ error: "An unexpected error occurred" }, { status: 500 });
  }
}
