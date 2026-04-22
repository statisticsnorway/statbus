import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { PassThrough } from 'stream';
import ExcelJS from '@protobi/exceljs';
import fs from 'fs';
import path from 'path';
import Papa from 'papaparse';
import { typeToNumFmt, addReferenceSheets, applyColumnValidation } from '@/lib/excel-reference-sheets';
import { describeError } from "@/lib/error-format";

function parseValueForExcel(value: string, colType: string): string | number | Date {
  if (!value) return '';
  if (colType === 'DATE') {
    const d = new Date(value + 'T00:00:00');
    if (!isNaN(d.getTime())) return d;
    return value;
  }
  if (colType === 'INTEGER' || colType === 'NUMERIC' || /^numeric\(/i.test(colType)) {
    const n = Number(value);
    if (!isNaN(n)) return n;
    return value;
  }
  return value;
}

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const definitionId = searchParams.get("definitionId");

    if (!definitionId || isNaN(Number(definitionId))) {
      return NextResponse.json({ message: "Missing or invalid definitionId parameter" }, { status: 400 });
    }

    // Auth is enforced via RLS: getServerRestClient() passes the JWT cookie,
    // and import_source_column is only readable by authenticated/admin_user roles.
    const client = await getServerRestClient();

    // Fetch definition, source columns, and settings in parallel
    const [defResult, colResult, settingsResult] = await Promise.all([
      client
        .from("import_definition")
        .select("id, slug, name")
        .eq("id", Number(definitionId))
        .single(),
      client
        .from("import_source_column_type")
        .select("column_name, priority, target_pg_type")
        .eq("definition_id", Number(definitionId))
        .order("priority"),
      client
        .from("settings")
        .select("region_version_id")
        .single(),
    ]);

    if (defResult.error || !defResult.data) {
      return NextResponse.json(
        { message: `Import definition not found: ${defResult.error?.message || "No definition with that id"}` },
        { status: 404 }
      );
    }
    if (colResult.error || !colResult.data) {
      return NextResponse.json(
        { message: `Source columns not found: ${colResult.error?.message}` },
        { status: 400 }
      );
    }

    const definition = defResult.data;
    // Type assertion: PostgreSQL views always report columns as nullable in
    // information_schema.columns and pg_attribute, even when the underlying base
    // table columns are NOT NULL and the view uses COALESCE. There is no
    // pg_depend or view_column_usage metadata that maps view output columns to
    // base column NOT NULL constraints — the only way would be parsing the
    // internal query tree from pg_rewrite, which is impractical. So our type
    // generator correctly mirrors what PostgreSQL reports, and we assert here.
    const sourceColumns = colResult.data as { column_name: string; priority: number; target_pg_type: string }[];
    // settingsResult.error is non-fatal: if settings aren't configured,
    // code lists will show all region versions instead of filtering.
    const regionVersionId = settingsResult.data?.region_version_id;

    // Build column type map from source columns
    const typeMap = new Map<string, string>(
      sourceColumns.map(c => [c.column_name, c.target_pg_type])
    );

    // Build workbook — Data sheet first so it's the first tab
    const workbook = new ExcelJS.Workbook();
    const dataSheet = workbook.addWorksheet('Data', {
      properties: { tabColor: { argb: 'FF4472C4' } },
    });

    // Add reference sheets and named ranges via shared utility
    const sourceColumnNames = sourceColumns.map(c => c.column_name);
    const rangeMap = await addReferenceSheets(workbook, sourceColumnNames, client, regionVersionId);

    // Add headers
    const headers = sourceColumns.map(c => c.column_name);
    const headerRow = dataSheet.addRow(headers);
    headerRow.font = { bold: true, color: { argb: 'FFFFFFFF' } };
    headerRow.fill = {
      type: 'pattern',
      pattern: 'solid',
      fgColor: { argb: 'FF4472C4' },
    };

    // Set column widths and number formats
    for (let i = 0; i < headers.length; i++) {
      const col = dataSheet.getColumn(i + 1);
      col.width = Math.max(headers[i].length + 4, 15);
      const colType = typeMap.get(headers[i]) ?? 'TEXT';
      col.numFmt = typeToNumFmt(colType);
    }

    // Populate demo data BEFORE data validation. ExcelJS data validation
    // creates phantom cells; addRow after that overwrites them with empties.
    const demoFile = searchParams.get("demoFile");
    if (demoFile) {
      if (!/^[a-z0-9_]+\.csv$/.test(demoFile)) {
        return NextResponse.json({ message: "Invalid demoFile parameter" }, { status: 400 });
      }
      const demoPath = path.join(process.cwd(), 'public', 'demo', demoFile);
      if (!fs.existsSync(demoPath)) {
        return NextResponse.json({ message: `Demo file not found: ${demoFile}` }, { status: 404 });
      }
      const csvContent = fs.readFileSync(demoPath, 'utf-8');
      const parsed = Papa.parse<Record<string, string>>(csvContent, { header: true, skipEmptyLines: true });
      const csvHeaders = parsed.meta.fields ?? [];
      if (csvHeaders.length > 0 && parsed.data.length > 0) {
        // Map CSV column names to Data sheet column indices
        const csvToSheetMap: Array<{ csvField: string; sheetCol: number }> = [];
        for (const field of csvHeaders) {
          const sheetIdx = headers.indexOf(field);
          if (sheetIdx !== -1) {
            csvToSheetMap.push({ csvField: field, sheetCol: sheetIdx + 1 });
          }
        }
        for (const record of parsed.data) {
          const row = dataSheet.addRow(new Array(headers.length).fill(''));
          for (const { csvField, sheetCol } of csvToSheetMap) {
            const rawValue = record[csvField] ?? '';
            const colType = typeMap.get(headers[sheetCol - 1]) ?? 'TEXT';
            row.getCell(sheetCol).value = parseValueForExcel(rawValue, colType);
          }
        }
      }
    }

    // Apply data validation to code columns via shared utility
    applyColumnValidation(dataSheet, sourceColumnNames, rangeMap);

    // Stream response
    const passThrough = new PassThrough();
    const webStream = new ReadableStream({
      start(controller) {
        passThrough.on('data', (chunk: Buffer) => controller.enqueue(chunk));
        passThrough.on('end', () => controller.close());
        passThrough.on('error', (err) => controller.error(err));
      },
      cancel() { passThrough.destroy(); },
    });

    workbook.xlsx.write(passThrough).then(() => passThrough.end()).catch((err) => passThrough.destroy(err));

    const filename = demoFile
      ? `${definition.slug}-demo.xlsx`
      : `${definition.slug}-template.xlsx`;
    return new Response(webStream, {
      headers: {
        "Content-Type": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        "Content-Disposition": `attachment; filename="${filename}"`,
      },
    });
  } catch (error) {
    console.error("Error in template handler:", error);
    return NextResponse.json(
      { message: `Server error: ${describeError(error)}` },
      { status: 500 }
    );
  }
}
