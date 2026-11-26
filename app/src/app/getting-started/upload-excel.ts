/**
 * Excel for the getting-started uploads (owner 2026-11-26, 5yxn4w): a chosen .xlsx is read in the
 * browser into the CSV the upload views take, and every example offered as CSV is offered as Excel
 * too, made in the browser from the same rows, so the two never differ.
 */
import Papa from "papaparse";
import { convertExcelToCsvBlob } from "@/lib/excel-to-csv";

/** Whether a chosen file is an Excel workbook (its first sheet is read). */
export function isExcelFile(file: File): boolean {
  const name = file.name.toLowerCase();
  return name.endsWith(".xlsx") || name.endsWith(".xls");
}

/** A chosen file as CSV text: Excel's first sheet converted, a CSV file as it is, without a BOM. */
export async function fileAsCsvText(file: File): Promise<string> {
  const text = isExcelFile(file) ? await (await convertExcelToCsvBlob(file)).text() : await file.text();
  return text.replace(/^\uFEFF/, "");
}

/** Saves `blob` as `filename` through a temporary link. */
export function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

/**
 * CSV text as an Excel workbook of one sheet. Every cell is text, so codes such as 03 keep their
 * leading zero when the file comes back.
 */
export async function csvTextToExcelBlob(csv: string, sheetName = "Sheet1"): Promise<Blob> {
  const XLSX = await import("xlsx");
  const rows = (Papa.parse(csv.replace(/^\uFEFF/, ""), { header: false, skipEmptyLines: true }).data as string[][]).map(
    (row) => row.map((cell) => String(cell))
  );
  const sheet = XLSX.utils.aoa_to_sheet(rows);
  for (const address of Object.keys(sheet)) {
    if (address.startsWith("!")) continue;
    const cell = sheet[address] as { t: string; z?: string };
    cell.t = "s";
    cell.z = "@";
  }
  const book = XLSX.utils.book_new();
  XLSX.utils.book_append_sheet(book, sheet, sheetName);
  const bytes = XLSX.write(book, { type: "array", bookType: "xlsx" }) as ArrayBuffer;
  return new Blob([bytes], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" });
}

/** An example file offered both ways: the CSV as it is, and the same rows as Excel. */
export async function downloadCsvAsExcel(csvHref: string, filename: string): Promise<void> {
  const response = await fetch(csvHref);
  if (!response.ok) throw new Error(`${csvHref}: ${response.status}`);
  saveBlob(await csvTextToExcelBlob(await response.text()), filename);
}
