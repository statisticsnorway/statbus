import { NextRequest, NextResponse } from "next/server";
import { PassThrough } from "stream";
import ExcelJS from "@protobi/exceljs";
import { getStatisticalUnits } from "@/app/search/search-requests";
import { toCSV } from "@/lib/csv-utils";
import { getServerRestClient } from "@/context/RestClientStore";
import { baseDataStore } from "@/context/BaseDataStore";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);

  if (!searchParams.has("order")) {
    searchParams.set("order", "name.asc");
  }

  const unitTypeFilter = searchParams.get("unit_type") || "";

  const unitType = unitTypeFilter.replace(/in\.\(|\)/g, "");
  const hasSingleUnitType = unitType && !unitType.includes(",");
  const isEstablishment = unitType === "establishment";

  const client = await getServerRestClient();
  // Use baseDataStore to get actual data
  const { externalIdentTypes, statDefinitions } = await baseDataStore.getBaseData(client);

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


  const format = searchParams.get("format") || "csv";
  searchParams.delete("format");
  if (!["csv", "xlsx"].includes(format)) {
    return NextResponse.json({ message: "format must be 'csv' or 'xlsx'" }, { status: 400 });
  }

  try {
    const response = await getStatisticalUnits(client, searchParams);
    const baseName = hasSingleUnitType ? `${unitType}s` : "statistical_units";

    if (format === "xlsx") {
      const units = response.statisticalUnits;
      const fields = units.length > 0
        ? Object.keys(units[0])
        : (searchParams.get("select") || "").split(",").map(s => {
            const aliased = s.split(":");
            return aliased[0].trim();
          }).filter(Boolean);
      const dateFields = new Set(["birth_date", "death_date"]);

      const workbook = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet("Data");
      worksheet.addRow(fields);

      for (let colIdx = 0; colIdx < fields.length; colIdx++) {
        if (dateFields.has(fields[colIdx])) {
          worksheet.getColumn(colIdx + 1).numFmt = 'yyyy-mm-dd';
        }
      }

      for (const unit of units) {
        const rec = unit as unknown as Record<string, unknown>;
        worksheet.addRow(fields.map(f => {
          const val = rec[f];
          if (val === null || val === undefined) return null;
          if (dateFields.has(f) && typeof val === "string") {
            // Append T00:00:00 so Date parses as local time, not UTC.
            // Without it, "2024-01-15" parses as UTC midnight and ExcelJS
            // converts to local time, which can shift the date by a day.
            const d = new Date(val + 'T00:00:00');
            if (!isNaN(d.getTime())) return d;
            return val;
          }
          return val;
        }));
      }

      const passThrough = new PassThrough();
      const webStream = new ReadableStream({
        start(controller) {
          passThrough.on("data", (chunk: Buffer) => controller.enqueue(chunk));
          passThrough.on("end", () => controller.close());
          passThrough.on("error", (err) => controller.error(err));
        },
        cancel() { passThrough.destroy(); },
      });

      workbook.xlsx.write(passThrough).then(() => passThrough.end()).catch((err) => passThrough.destroy(err));

      return new Response(webStream, {
        headers: {
          "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
          "Content-Disposition": `attachment; filename="${baseName}.xlsx"`,
        },
      });
    }

    const { header, body } = toCSV(response.statisticalUnits);
    return new Response(header + body, {
      headers: {
        "Content-Type": "text/csv",
        "Content-Disposition": `attachment; filename="${baseName}.csv"`,
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
