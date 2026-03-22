import { NextRequest, NextResponse } from "next/server";
import Papa from "papaparse";
import ExcelJS from "exceljs";

const SYSTEM_COLUMNS = new Set(["row_id", "errors", "warnings", "row_number"]);

export async function POST(request: NextRequest) {
  try {
    const formData = await request.formData();
    const file = formData.get("file") as File | null;

    if (!file) {
      return NextResponse.json({ error: "No file provided" }, { status: 400 });
    }

    const name = file.name.toLowerCase();
    let headers: string[];

    if (name.endsWith(".csv") || name.endsWith(".tsv") || name.endsWith(".txt")) {
      const text = await file.text();
      const result = Papa.parse(text, { preview: 1, skipEmptyLines: true });
      if (!result.data || result.data.length === 0) {
        return NextResponse.json({ error: "No data found in file" }, { status: 400 });
      }
      headers = (result.data[0] as string[]).map((h) => h.trim()).filter(Boolean);
    } else if (name.endsWith(".xlsx") || name.endsWith(".xls")) {
      const arrayBuffer = await file.arrayBuffer();
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.load(arrayBuffer);
      const worksheet = workbook.worksheets[0];
      if (!worksheet) {
        return NextResponse.json({ error: "No worksheet found" }, { status: 400 });
      }
      const row = worksheet.getRow(1);
      headers = [];
      row.eachCell({ includeEmpty: false }, (cell) => {
        const val = cell.value;
        if (val !== null && val !== undefined) {
          headers.push(String(val).trim());
        }
      });
    } else {
      return NextResponse.json(
        { error: "Unsupported file type. Use .csv, .tsv, .xlsx, or .xls" },
        { status: 400 },
      );
    }

    headers = headers.filter((h) => !SYSTEM_COLUMNS.has(h.toLowerCase()));

    return NextResponse.json({ headers });
  } catch (err) {
    return NextResponse.json(
      { error: `Failed to parse file: ${err instanceof Error ? err.message : String(err)}` },
      { status: 500 },
    );
  }
}
