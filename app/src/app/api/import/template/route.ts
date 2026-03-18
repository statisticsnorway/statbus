import { NextRequest, NextResponse } from "next/server";
import { getServerRestClient } from "@/context/RestClientStore";
import { PassThrough } from 'stream';
import ExcelJS from 'exceljs';
import fs from 'fs';
import path from 'path';

function typeToNumFmt(colType: string): string {
  if (colType === 'DATE') return 'yyyy-mm-dd';
  if (colType === 'INTEGER') return '0';
  if (colType === 'NUMERIC') return '#,##0.##';
  const match = colType.match(/^numeric\(\d+,(\d+)\)$/i);
  if (match) return '0.' + '0'.repeat(Number(match[1]));
  return '@'; // TEXT — prevents auto-conversion of codes like "01.11"
}

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

const COLUMN_REFERENCE_MAP: Record<string, {
  view: string;
  codeColumn: string;
  nameColumn: string;
  sheetName: string;
  rangeName: string;
  needsVersionFilter?: boolean;
}> = {
  primary_activity_category_code:   { view: 'activity_category_enabled', codeColumn: 'code', nameColumn: 'name', sheetName: 'Activity Categories', rangeName: 'ActivityCategoryCodes' },
  secondary_activity_category_code: { view: 'activity_category_enabled', codeColumn: 'code', nameColumn: 'name', sheetName: 'Activity Categories', rangeName: 'ActivityCategoryCodes' },
  legal_form_code:                  { view: 'legal_form_enabled',        codeColumn: 'code', nameColumn: 'name', sheetName: 'Legal Forms',          rangeName: 'LegalFormCodes' },
  sector_code:                      { view: 'sector_enabled',            codeColumn: 'code', nameColumn: 'name', sheetName: 'Sectors',              rangeName: 'SectorCodes' },
  physical_region_code:             { view: 'region',                    codeColumn: 'code', nameColumn: 'name', sheetName: 'Regions',              rangeName: 'RegionCodes', needsVersionFilter: true },
  postal_region_code:               { view: 'region',                    codeColumn: 'code', nameColumn: 'name', sheetName: 'Regions',              rangeName: 'RegionCodes', needsVersionFilter: true },
  physical_country_iso_2:           { view: 'country_enabled',           codeColumn: 'iso_2', nameColumn: 'name', sheetName: 'Countries',           rangeName: 'CountryCodes' },
  postal_country_iso_2:             { view: 'country_enabled',           codeColumn: 'iso_2', nameColumn: 'name', sheetName: 'Countries',           rangeName: 'CountryCodes' },
  data_source_code:                 { view: 'data_source_enabled',       codeColumn: 'code', nameColumn: 'name', sheetName: 'Data Sources',         rangeName: 'DataSourceCodes' },
  status_code:                      { view: 'status_enabled',            codeColumn: 'code', nameColumn: 'name', sheetName: 'Statuses',             rangeName: 'StatusCodes' },
  unit_size_code:                   { view: 'unit_size_enabled',         codeColumn: 'code', nameColumn: 'name', sheetName: 'Unit Sizes',           rangeName: 'UnitSizeCodes' },
  rel_type_code:                    { view: 'legal_rel_type_enabled',    codeColumn: 'code', nameColumn: 'name', sheetName: 'Relationship Types',   rangeName: 'RelTypeCodes' },
};

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const definitionId = searchParams.get("definitionId");

    if (!definitionId || isNaN(Number(definitionId))) {
      return NextResponse.json({ message: "Missing or invalid definitionId parameter" }, { status: 400 });
    }

    const client = await getServerRestClient();

    // Fetch definition, source columns, settings, and column types in parallel
    const [defResult, colResult, settingsResult, typeResult] = await Promise.all([
      client
        .from("import_definition")
        .select("id, slug, name")
        .eq("id", Number(definitionId))
        .single(),
      client
        .from("import_source_column")
        .select("column_name, priority")
        .eq("definition_id", Number(definitionId))
        .order("priority"),
      client
        .from("settings")
        .select("region_version_id")
        .single(),
      client
        .rpc("import_definition_source_column_types" as any, { p_definition_id: Number(definitionId) }) as unknown as { data: { column_name: string; column_type: string }[] | null; error: any },
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
    const sourceColumns = colResult.data;
    const regionVersionId = settingsResult.data?.region_version_id;

    // Build column type map from database metadata
    const typeMap = new Map<string, string>(
      (typeResult.data ?? []).map((r: { column_name: string; column_type: string }) => [r.column_name, r.column_type])
    );

    // Determine which reference sheets are needed (deduplicated by sheetName)
    const neededRefs = new Map<string, typeof COLUMN_REFERENCE_MAP[string]>();
    for (const col of sourceColumns) {
      const ref = COLUMN_REFERENCE_MAP[col.column_name];
      if (ref && !neededRefs.has(ref.sheetName)) {
        neededRefs.set(ref.sheetName, ref);
      }
    }

    // Fetch all reference data in parallel
    const refEntries = Array.from(neededRefs.entries());
    const refDataResults = await Promise.all(
      refEntries.map(async ([sheetName, ref]) => {
        let query = client.from(ref.view as any).select(`${ref.codeColumn}, ${ref.nameColumn}`);

        if (ref.needsVersionFilter && regionVersionId) {
          query = query.eq("version_id", regionVersionId);
        }

        // Filter out empty codes
        if (ref.codeColumn === 'iso_2') {
          query = query.not(ref.codeColumn, 'is', null);
        } else {
          query = query.neq(ref.codeColumn, '').not(ref.codeColumn, 'is', null);
        }

        query = query.order(ref.codeColumn);

        const { data, error } = await query;
        if (error) {
          console.error(`Error fetching ${ref.view}:`, error.message);
          return { sheetName, ref, data: [] as Record<string, string>[] };
        }
        return { sheetName, ref, data: (data || []) as unknown as Record<string, string>[] };
      })
    );

    // Build workbook — Data sheet first so it's the first tab
    const workbook = new ExcelJS.Workbook();
    const dataSheet = workbook.addWorksheet('Data', {
      properties: { tabColor: { argb: 'FF4472C4' } },
    });

    // Create reference sheets and named ranges
    const rangeMap = new Map<string, string>();
    for (const { sheetName, ref, data } of refDataResults) {
      if (data.length === 0) continue;

      const ws = workbook.addWorksheet(sheetName);
      ws.addRow(['Code', 'Name', 'Code # Name']);
      ws.getRow(1).font = { bold: true };

      for (const row of data) {
        const code = row[ref.codeColumn];
        const name = row[ref.nameColumn];
        ws.addRow([code, name, `${code} # ${name}`]);
      }

      ws.getColumn(1).width = 15;
      ws.getColumn(2).width = 50;
      ws.getColumn(3).width = 65;

      // Named range points to column C (combined "code # name") for dropdown display
      const lastRow = data.length + 1;
      const safeSheetName = sheetName.includes(' ') ? `'${sheetName}'` : sheetName;
      workbook.definedNames.add(`${safeSheetName}!$C$2:$C$${lastRow}`, ref.rangeName);
      rangeMap.set(ref.rangeName, ref.rangeName);
    }

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

    // Apply data validation to code columns (rows 2-1001)
    for (let colIdx = 0; colIdx < sourceColumns.length; colIdx++) {
      const ref = COLUMN_REFERENCE_MAP[sourceColumns[colIdx].column_name];
      if (!ref || !rangeMap.has(ref.rangeName)) continue;

      const colNumber = colIdx + 1;
      for (let rowIdx = 2; rowIdx <= 1001; rowIdx++) {
        dataSheet.getCell(rowIdx, colNumber).dataValidation = {
          type: 'list',
          allowBlank: true,
          formulae: [ref.rangeName],
          showErrorMessage: true,
          errorStyle: 'warning' as any,
          errorTitle: 'Unknown code',
          error: `See the "${ref.sheetName}" sheet for valid codes.`,
        };
      }
    }

    // Populate demo data if demoFile parameter is provided
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
      const csvLines = csvContent.split('\n').filter(line => line.trim() !== '');
      if (csvLines.length > 1) {
        const csvHeaders = csvLines[0].split(',').map(h => h.trim());
        // Map CSV column indices to Data sheet column indices
        const csvToSheetMap: Array<{ csvIdx: number; sheetCol: number }> = [];
        for (let ci = 0; ci < csvHeaders.length; ci++) {
          const sheetIdx = headers.indexOf(csvHeaders[ci]);
          if (sheetIdx !== -1) {
            csvToSheetMap.push({ csvIdx: ci, sheetCol: sheetIdx + 1 });
          }
        }
        for (let ri = 1; ri < csvLines.length; ri++) {
          const fields = csvLines[ri].split(',').map(f => f.trim());
          const row = dataSheet.addRow(new Array(headers.length).fill(''));
          for (const { csvIdx, sheetCol } of csvToSheetMap) {
            const rawValue = fields[csvIdx] ?? '';
            const colType = typeMap.get(headers[sheetCol - 1]) ?? 'TEXT';
            row.getCell(sheetCol).value = parseValueForExcel(rawValue, colType);
          }
        }
      }
    }

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

    workbook.xlsx.write(passThrough).then(() => passThrough.end());

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
      { message: `Server error: ${error instanceof Error ? error.message : String(error)}` },
      { status: 500 }
    );
  }
}
