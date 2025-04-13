import { NextRequest, NextResponse } from "next/server";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { toCSV } from "@/lib/csv-utils";
import { getServerClient } from "@/context/ClientStore";
import { getBaseData } from "@/app/BaseDataServer";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("order")) {
    searchParams.set("order", "name.asc");
  }

  const unitTypeFilter = searchParams.get("unit_type") || "";

  const unitType = unitTypeFilter.replace(/in\.\(|\)/g, "");
  const hasSingleUnitType = unitType && !unitType.includes(",");
  const isEstablishment = unitType === "establishment";

  const client = await getServerClient();
  const { externalIdentTypes, statDefinitions } = await getBaseData(client);

  const externalIdentColumns = externalIdentTypes.map(({ code }) => `${code}:external_idents->>${code}`);
  const statDefinitionColumns = statDefinitions.map(({ code }) => `${code}:stats_summary->${code}->sum`);

  searchParams.set(
    "select",
    [
      externalIdentColumns,
      [
        "name",
        ...(hasSingleUnitType ? [] : ["unit_type"]),
        "birth_date",
        "death_date",
        "primary_activity_category_code",
        "secondary_activity_category_code",
        ...(isEstablishment ? [] : ["sector_code", "legal_form_code"]),
        "physical_address_part1",
        "physical_address_part2",
        "physical_address_part3",
        "physical_postcode",
        "physical_postplace",
        "physical_region_code",
        "physical_country_iso_2",
        "physical_latitude",
        "physical_longitude",
        "physical_altitude",
        "postal_address_part1",
        "postal_address_part2",
        "postal_address_part3",
        "postal_postcode",
        "postal_postplace",
        "postal_region_code",
        "postal_country_iso_2",
        "postal_latitude",
        "postal_longitude",
        "postal_altitude",
        "web_address",
        "email_address",
        "phone_number",
        "landline",
        "mobile_number",
        "fax_number",
        "status_code",
        "unit_size_code",
      ],
      statDefinitionColumns,
    ]
      .flat()
      .join(",")
  );

  searchParams.set("limit", "100000");
  searchParams.set("offset", "0");


  try {
    const response = await getStatisticalUnits(client, searchParams);
    const { header, body } = toCSV(response.statisticalUnits);

    const filename = hasSingleUnitType
      ? `${unitType}s.csv`
      : "statistical_units.csv";

    return new Response(header + body, {
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": `attachment; filename="${filename}"`,
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
