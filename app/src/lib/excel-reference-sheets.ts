import type ExcelJS from '@protobi/exceljs';

export const COLUMN_REFERENCE_MAP: Record<string, {
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

export function typeToNumFmt(colType: string): string {
  if (colType === 'DATE') return 'yyyy-mm-dd';
  if (colType === 'INTEGER') return '0';
  if (colType === 'NUMERIC') return '#,##0.##';
  const match = colType.match(/^numeric\(\d+,(\d+)\)$/i);
  if (match) return '0.' + '0'.repeat(Number(match[1]));
  return '@'; // TEXT — prevents auto-conversion of codes like "01.11"
}

export function getExcelColumnLetters(colIdx: number): string {
  let result = '';
  let idx = colIdx;
  while (idx >= 0) {
    result = String.fromCharCode(65 + (idx % 26)) + result;
    idx = Math.floor(idx / 26) - 1;
  }
  return result;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type RestClient = { from: (table: any) => any };

export async function addReferenceSheets(
  workbook: ExcelJS.Workbook,
  sourceColumnNames: string[],
  client: RestClient,
  regionVersionId?: number | null,
): Promise<Map<string, string>> {
  // Determine which reference sheets are needed (deduplicated by sheetName)
  const neededRefs = new Map<string, typeof COLUMN_REFERENCE_MAP[string]>();
  for (const colName of sourceColumnNames) {
    const ref = COLUMN_REFERENCE_MAP[colName];
    if (ref && !neededRefs.has(ref.sheetName)) {
      neededRefs.set(ref.sheetName, ref);
    }
  }

  // Fetch all reference data in parallel
  const refEntries = Array.from(neededRefs.entries());
  const refDataResults = await Promise.all(
    refEntries.map(async ([sheetName, ref]) => {
      let query = client.from(ref.view).select(`${ref.codeColumn}, ${ref.nameColumn}`);

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

  // Create reference sheets and named ranges
  const rangeMap = new Map<string, string>();
  for (const { sheetName, ref, data } of refDataResults) {
    if (data.length === 0) continue;

    const ws = workbook.addWorksheet(sheetName);
    ws.addRow(['Code', 'Name', 'Code | Name']);
    ws.getRow(1).font = { bold: true };

    for (const row of data) {
      const code = row[ref.codeColumn];
      const name = row[ref.nameColumn];
      ws.addRow([code, name, `${code} | ${name}`]);
    }

    ws.getColumn(1).width = 15;
    ws.getColumn(2).width = 50;
    ws.getColumn(3).width = 65;

    // Named range points to column C (combined "code | name") for dropdown display
    const lastRow = data.length + 1;
    const safeSheetName = sheetName.includes(' ') ? `'${sheetName}'` : sheetName;
    workbook.definedNames.add(`${safeSheetName}!$C$2:$C$${lastRow}`, ref.rangeName);
    rangeMap.set(ref.rangeName, ref.rangeName);
  }

  return rangeMap;
}

export function applyColumnValidation(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  dataSheet: any,
  sourceColumnNames: string[],
  rangeMap: Map<string, string>,
  columnOffset: number = 0,
): void {
  for (let colIdx = 0; colIdx < sourceColumnNames.length; colIdx++) {
    const ref = COLUMN_REFERENCE_MAP[sourceColumnNames[colIdx]];
    if (!ref || !rangeMap.has(ref.rangeName)) continue;

    const colLetters = getExcelColumnLetters(colIdx + columnOffset);
    const range = `${colLetters}2:${colLetters}1048576`;
    dataSheet.dataValidations.model[range] = {
      type: 'list',
      allowBlank: true,
      formulae: [ref.rangeName],
      showErrorMessage: true,
      errorStyle: 'warning',
      errorTitle: 'Unknown code',
      error: `See the "${ref.sheetName}" sheet for valid codes.`,
    };
  }
}

/**
 * Returns per-column validation info for streaming row-by-row application.
 * Maps 1-based column index → validation config for use with row.getCell().dataValidation.
 * Only includes columns whose reference data was actually fetched (non-empty).
 */
export function getColumnValidationMap(
  sourceColumnNames: string[],
  refDataResults: Array<{ sheetName: string; ref: typeof COLUMN_REFERENCE_MAP[string]; data: Record<string, string>[] }>,
  columnOffset: number = 0,
): Map<number, { type: 'list'; allowBlank: true; formulae: [string]; showErrorMessage: true; errorStyle: 'warning'; errorTitle: string; error: string }> {
  // Build set of range names that will actually be written (non-empty data)
  const availableRanges = new Set<string>();
  for (const { ref, data } of refDataResults) {
    if (data.length > 0) availableRanges.add(ref.rangeName);
  }

  const map = new Map<number, { type: 'list'; allowBlank: true; formulae: [string]; showErrorMessage: true; errorStyle: 'warning'; errorTitle: string; error: string }>();
  for (let colIdx = 0; colIdx < sourceColumnNames.length; colIdx++) {
    const ref = COLUMN_REFERENCE_MAP[sourceColumnNames[colIdx]];
    if (!ref || !availableRanges.has(ref.rangeName)) continue;
    // 1-based column index
    map.set(colIdx + columnOffset + 1, {
      type: 'list',
      allowBlank: true,
      formulae: [ref.rangeName],
      showErrorMessage: true,
      errorStyle: 'warning',
      errorTitle: 'Unknown code',
      error: `See the "${ref.sheetName}" sheet for valid codes.`,
    });
  }
  return map;
}

/**
 * Fetches reference data and returns it without writing to a workbook.
 * Use writeReferenceSheets() to write the fetched data to a workbook/writer.
 */
export async function fetchReferenceData(
  sourceColumnNames: string[],
  client: RestClient,
  regionVersionId?: number | null,
): Promise<Array<{ sheetName: string; ref: typeof COLUMN_REFERENCE_MAP[string]; data: Record<string, string>[] }>> {
  const neededRefs = new Map<string, typeof COLUMN_REFERENCE_MAP[string]>();
  for (const colName of sourceColumnNames) {
    const ref = COLUMN_REFERENCE_MAP[colName];
    if (ref && !neededRefs.has(ref.sheetName)) {
      neededRefs.set(ref.sheetName, ref);
    }
  }

  const refEntries = Array.from(neededRefs.entries());
  return Promise.all(
    refEntries.map(async ([sheetName, ref]) => {
      let query = client.from(ref.view).select(`${ref.codeColumn}, ${ref.nameColumn}`);
      if (ref.needsVersionFilter && regionVersionId) {
        query = query.eq("version_id", regionVersionId);
      }
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
}

/**
 * Writes reference sheets to a workbook or WorkbookWriter.
 * For WorkbookWriter: commits each row and sheet for streaming output.
 * Returns the set of range names that were created.
 */
export function writeReferenceSheets(
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  workbook: any,
  refDataResults: Array<{ sheetName: string; ref: typeof COLUMN_REFERENCE_MAP[string]; data: Record<string, string>[] }>,
  streaming: boolean = false,
): Set<string> {
  const rangeNames = new Set<string>();
  for (const { sheetName, ref, data } of refDataResults) {
    if (data.length === 0) continue;

    const ws = workbook.addWorksheet(sheetName);

    // Set column widths BEFORE committing any rows — WorkbookWriter
    // serializes column metadata on the first row.commit() call.
    ws.getColumn(1).width = 15;
    ws.getColumn(2).width = 50;
    ws.getColumn(3).width = 65;

    const headerRow = ws.addRow(['Code', 'Name', 'Code | Name']);
    headerRow.font = { bold: true };
    if (streaming) headerRow.commit();

    for (const row of data) {
      const code = row[ref.codeColumn];
      const name = row[ref.nameColumn];
      const dataRow = ws.addRow([code, name, `${code} | ${name}`]);
      if (streaming) dataRow.commit();
    }

    const lastRow = data.length + 1;
    const safeSheetName = sheetName.includes(' ') ? `'${sheetName}'` : sheetName;
    workbook.definedNames.add(`${safeSheetName}!$C$2:$C$${lastRow}`, ref.rangeName);
    rangeNames.add(ref.rangeName);

    if (streaming) ws.commit();
  }
  return rangeNames;
}
