/**
 * Client-side Excel→CSV conversion using SheetJS.
 * Runs in the browser — no server round-trip for Excel parsing.
 */
import * as XLSX from 'xlsx';

export interface FilePreview {
  fileName: string;
  fileSize: number;
  rowCount: number;
  columnNames: string[];
  sampleRows: string[][];
  isExcel: boolean;
}

/**
 * Inspect a file to get metadata and sample rows without full conversion.
 */
export async function inspectFile(file: File): Promise<FilePreview> {
  const fileName = file.name;
  const fileSize = file.size;
  const isExcel = fileName.toLowerCase().endsWith('.xlsx') || fileName.toLowerCase().endsWith('.xls');

  if (isExcel) {
    const arrayBuffer = await file.arrayBuffer();

    // Full read to get row count from sheet range (only parses metadata + cell refs, not heavy)
    const workbook = XLSX.read(arrayBuffer, { type: 'array' });
    const sheetName = workbook.SheetNames[0];
    const sheet = workbook.Sheets[sheetName];

    const range = XLSX.utils.decode_range(sheet['!ref'] || 'A1');
    const rowCount = range.e.r; // 0-based last row index = row count excluding header

    // Extract sample rows from the already-loaded workbook
    const data = XLSX.utils.sheet_to_json<string[]>(sheet, { header: 1 });
    const columnNames = (data[0] || []).map(String);
    const sampleRows = data.slice(1, 6).map(row =>
      row.map(cell => (cell === null || cell === undefined) ? '' : String(cell))
    );

    return { fileName, fileSize, rowCount, columnNames, sampleRows, isExcel };
  }

  // CSV: read first few lines
  const text = await file.slice(0, 64 * 1024).text(); // first 64KB
  const lines = text.split('\n').filter(l => l.trim());
  const columnNames = lines[0]?.split(',').map(h => h.trim().replace(/^"|"$/g, '')) || [];
  const sampleRows = lines.slice(1, 6).map(line =>
    line.split(',').map(cell => cell.trim().replace(/^"|"$/g, ''))
  );

  // Estimate row count from file size and average line length
  const avgLineLen = text.length / Math.max(lines.length, 1);
  const rowCount = Math.round(fileSize / avgLineLen) - 1; // subtract header

  return { fileName, fileSize, rowCount, columnNames, sampleRows, isExcel };
}

/**
 * Convert an Excel file to CSV. Returns a Blob of CSV data.
 * Handles date serial numbers, system column stripping, etc.
 */
export function convertExcelToCsvBlob(file: File): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        const data = new Uint8Array(e.target!.result as ArrayBuffer);
        const workbook = XLSX.read(data, { type: 'array', cellDates: true });
        const sheetName = workbook.SheetNames[0];
        const sheet = workbook.Sheets[sheetName];

        // Convert to CSV — SheetJS handles date formatting automatically with cellDates
        const csv = XLSX.utils.sheet_to_csv(sheet, { dateNF: 'yyyy-mm-dd' });

        // Strip system columns (row_id, errors, warnings) if present
        const lines = csv.split('\n');
        if (lines.length === 0) {
          resolve(new Blob([csv], { type: 'text/csv' }));
          return;
        }

        const headers = lines[0].split(',').map(h => h.trim().replace(/^"|"$/g, ''));
        const systemCols = new Set(['row_id', 'errors', 'warnings', '_errors', '_warnings']);
        const skipIndices = new Set<number>();
        headers.forEach((h, i) => {
          if (systemCols.has(h)) skipIndices.add(i);
        });

        if (skipIndices.size === 0) {
          resolve(new Blob([csv], { type: 'text/csv' }));
          return;
        }

        // Rebuild CSV without system columns
        const cleanedLines = lines.map(line => {
          if (!line.trim()) return line;
          // Simple CSV split — SheetJS output is well-formed
          const cells = parseCsvLine(line);
          return cells.filter((_, i) => !skipIndices.has(i)).join(',');
        });

        resolve(new Blob([cleanedLines.join('\n')], { type: 'text/csv' }));
      } catch (err) {
        reject(err);
      }
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsArrayBuffer(file);
  });
}

/** Simple CSV line parser that handles quoted fields */
function parseCsvLine(line: string): string[] {
  const result: string[] = [];
  let current = '';
  let inQuotes = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (inQuotes) {
      if (ch === '"' && line[i + 1] === '"') {
        current += '"';
        i++;
      } else if (ch === '"') {
        inQuotes = false;
      } else {
        current += ch;
      }
    } else {
      if (ch === '"') {
        inQuotes = true;
      } else if (ch === ',') {
        result.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
  }
  result.push(current);
  return result;
}
