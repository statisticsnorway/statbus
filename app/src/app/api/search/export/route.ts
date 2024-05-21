import { NextResponse } from "next/server";
import { Tables } from "@/lib/database.types";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { toCSV } from "@/lib/csv-utils";

export async function GET(request: Request) {
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
    "tax_ident, name, unit_type, primary_activity_category_id, physical_region_id, employees, physical_country_iso_2, sector_code, sector_name, legal_form_code, legal_form_name"
  );

  const statisticalUnitsResponse = await getStatisticalUnits(searchParams);

  if (!statisticalUnitsResponse.ok) {
    return NextResponse.error();
  }

  const statisticalUnits: Tables<Partial<"statistical_unit">>[] =
    await statisticalUnitsResponse.json();

  const { header, body } = toCSV(statisticalUnits);

  return new Response(header + body, {
    headers: {
      "Content-Type": "text/csv",
      "Content-Disposition": 'attachment; filename="statistical_units.csv"',
    },
  });
}
