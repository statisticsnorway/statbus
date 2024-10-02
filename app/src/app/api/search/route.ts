import { NextRequest, NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";

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

  const response = await getStatisticalUnits(searchParams);

  if (response.statusText != '') {
    return NextResponse.json({ error: response.statusText });
  }

  return NextResponse.json({
    statisticalUnits: response.statistical_units,
    count: response.count,
  });
}
