/**
 * Client-side Excel→CSV conversion using SheetJS.
 * Runs in the browser — no server round-trip for Excel parsing.
 * SheetJS (xlsx) is dynamically imported to avoid adding ~900KB to the initial bundle.
 */
import Papa from 'papaparse';

export interface FilePreview {
  fileName: string;
  fileSize: number;
  rowCount: number;
  columnNames: string[];
  sampleRows: string[][];
  isExcel: boolean;
  /** Cached arrayBuffer for Excel files — pass to convertExcelToCsvBlob to avoid re-reading */
  arrayBuffer?: ArrayBuffer;
}

/**
 * Inspect a file to get metadata and sample rows without full conversion.
 * For Excel: uses sheetRows:6 for fast partial parse, !fullref for total row count.
 * Returns the arrayBuffer so convertExcelToCsvBlob can reuse it.
 */
export async function inspectFile(file: File): Promise<FilePreview> {
  const fileName = file.name;
  const fileSize = file.size;
  const isExcel = fileName.toLowerCase().endsWith('.xlsx') || fileName.toLowerCase().endsWith('.xls');

  if (isExcel) {
    const XLSX = await import('xlsx');
    const arrayBuffer = await file.arrayBuffer();

    // Partial read: only parse 6 rows (fast even for huge files)
    // !fullref still contains the full XML dimension for accurate row count
    const workbook = XLSX.read(arrayBuffer, { type: 'array', sheetRows: 6 });
    const sheetName = workbook.SheetNames[0];
    const sheet = workbook.Sheets[sheetName];

    const fullRef = sheet['!fullref'] || sheet['!ref'] || 'A1';
    const range = XLSX.utils.decode_range(fullRef);
    const rowCount = range.e.r; // 0-based last row index = row count excluding header

    const data = XLSX.utils.sheet_to_json<string[]>(sheet, { header: 1 });
    const columnNames = (data[0] || []).map(String);
    const sampleRows = data.slice(1, 6).map(row =>
      row.map(cell => (cell === null || cell === undefined) ? '' : String(cell))
    );

    return { fileName, fileSize, rowCount, columnNames, sampleRows, isExcel, arrayBuffer };
  }

  // CSV: use PapaParser for proper quoted-field handling
  const text = await file.slice(0, 64 * 1024).text(); // first 64KB
  const parsed = Papa.parse(text, { header: false, skipEmptyLines: true });
  const rows = parsed.data as string[][];

  const columnNames = (rows[0] || []).map(String);
  const sampleRows = rows.slice(1, 6);

  // Estimate row count from file size and average line length
  const lines = text.split('\n').filter(l => l.trim());
  const avgLineLen = text.length / Math.max(lines.length, 1);
  const rowCount = Math.round(fileSize / avgLineLen) - 1; // subtract header

  return { fileName, fileSize, rowCount, columnNames, sampleRows, isExcel };
}

/**
 * Convert an Excel file to CSV. Returns a Blob of CSV data.
 * Accepts a cached ArrayBuffer (from inspectFile) to avoid re-reading the file.
 */
export async function convertExcelToCsvBlob(source: File | ArrayBuffer): Promise<Blob> {
  const XLSX = await import('xlsx');

  const arrayBuffer = source instanceof ArrayBuffer
    ? source
    : await source.arrayBuffer();

  const data = new Uint8Array(arrayBuffer);
  const workbook = XLSX.read(data, { type: 'array', cellDates: true });
  const sheetName = workbook.SheetNames[0];
  const sheet = workbook.Sheets[sheetName];

  // Convert to CSV — SheetJS handles date formatting automatically with cellDates
  const csv = XLSX.utils.sheet_to_csv(sheet, { dateNF: 'yyyy-mm-dd' });

  // Always normalize through Papa to fix SheetJS inconsistencies
  // (e.g. data rows having more columns than header due to empty trailing cells)
  const parsed = Papa.parse(csv, { header: false, skipEmptyLines: false });
  const rows = parsed.data as string[][];
  if (rows.length === 0) {
    return new Blob([csv], { type: 'text/csv' });
  }

  const headers = rows[0];
  const systemCols = new Set(['row_id', 'errors', 'warnings', '_errors', '_warnings']);
  const skipIndices = new Set<number>();
  headers.forEach((h, i) => {
    if (systemCols.has(h.trim())) skipIndices.add(i);
  });

  // Strip system columns and normalize row lengths to match header count
  const cleanedRows = rows
    .filter(row => row.some(cell => cell !== ''))
    .map(row => {
      const filtered = skipIndices.size > 0
        ? row.filter((_, i) => !skipIndices.has(i))
        : row;
      const targetLen = headers.length - skipIndices.size;
      if (filtered.length > targetLen) return filtered.slice(0, targetLen);
      return filtered;
    });
  const cleanedCsv = Papa.unparse(cleanedRows, { header: false, newline: '\n' });

  return new Blob([cleanedCsv + '\n'], { type: 'text/csv' });
}
