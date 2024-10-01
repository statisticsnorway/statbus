import { NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";

export async function GET(request: Request) {
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

  const statisticalUnitsResponse = await getStatisticalUnits(searchParams);

  if (!statisticalUnitsResponse.ok) {
    return NextResponse.json({ error: statisticalUnitsResponse.statusText });
  }

  const statisticalUnits = await statisticalUnitsResponse.json();
  const count = statisticalUnitsResponse.headers
    .get("content-range")
    ?.split("/")[1];
  return NextResponse.json({
    statisticalUnits,
    count: parseInt(count ?? "-1", 10),
  });
}
