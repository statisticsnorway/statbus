import { getServerRestClient } from "@/context/RestClientStore";
import { Enums } from "@/lib/database.types";
import { NextRequest, NextResponse } from "next/server";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const resolution = searchParams.get(
    "resolution"
  ) as Enums<"history_resolution">;
  const unitType = searchParams.get("unit_type") as
    UnitType;
  const series_codes = searchParams.get("series_codes")?.split(",");
  const yearParam = searchParams.get("year");
  const year = yearParam ? parseInt(yearParam, 10) : undefined;

  const client = await getServerRestClient();
  const { data, error } = await client.rpc("statistical_history_highcharts", {
    p_resolution: resolution,
    p_unit_type: unitType,
    p_series_codes: series_codes,
    p_year: year,
  });

  if (error) {
    return NextResponse.json({ message: error.message });
  }

  return NextResponse.json(data);
}
