import ExcelJS from "@protobi/exceljs";
import { PassThrough } from "stream";
import { buildChartWorkbook } from "./chart-export";

// The import download writes its workbook with the streaming writer, through
// ExcelJS's zip archiver (archiver, zip-stream, readdir-glob, glob); the chart
// export and the upload read it back through unzipper. Both paths must keep
// producing a workbook Excel can open after dependency upgrades (STATBUS-630).
describe("streamed workbook", () => {
  it("writes formatted columns and committed rows that read back unchanged", async () => {
    const stream = new PassThrough();
    const chunks: Buffer[] = [];
    stream.on("data", (chunk: Buffer) => chunks.push(chunk));
    const done = new Promise((resolve) => stream.on("end", resolve));

    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const workbook = new (ExcelJS as any).stream.xlsx.WorkbookWriter({ stream });
    const sheet = workbook.addWorksheet("Data");
    sheet.addRow(["tax_ident", "birth_date", "employees"]).commit();
    sheet.addRow(["923609016", new Date(Date.UTC(2020, 4, 1)), 12]).commit();
    await sheet.commit();
    await workbook.commit();
    await done;

    const bytes = Buffer.concat(chunks);
    const loaded = new ExcelJS.Workbook();
    await loaded.xlsx.load(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer);
    const data = loaded.getWorksheet("Data");
    if (!data) throw new Error("Data worksheet was not written");
    expect(data.getRow(1).values).toEqual([undefined, "tax_ident", "birth_date", "employees"]);
    expect(data.getRow(2).getCell(1).value).toBe("923609016");
    expect(data.getRow(2).getCell(2).value).toEqual(new Date(Date.UTC(2020, 4, 1)));
    expect(data.getRow(2).getCell(2).type).toBe(ExcelJS.ValueType.Date);
    expect(data.getRow(2).getCell(3).value).toBe(12);
  });
});

describe("buildChartWorkbook", () => {
  it("preserves chart headers and writes typed date, number, text, and empty cells", async () => {
    const workbook = await buildChartWorkbook({
      rows: [
        ["DateTime", "Units", "Status", "Missing"],
        ["2024-01-15 00:00:00", 42.5, "Operating", null],
      ],
      dateColumnIndex: 0,
      dateNumberFormat: "yyyy-mm-dd",
    });
    const buffer = await workbook.xlsx.writeBuffer();
    const loadedWorkbook = new ExcelJS.Workbook();
    await loadedWorkbook.xlsx.load(buffer);
    const worksheet = loadedWorkbook.getWorksheet("Data");
    expect(worksheet).toBeDefined();
    if (!worksheet) throw new Error("Data worksheet was not created");

    expect(worksheet.getRow(1).values).toEqual([
      undefined,
      "DateTime",
      "Units",
      "Status",
      "Missing",
    ]);

    const row = worksheet.getRow(2);
    expect(row.getCell(1).value).toEqual(new Date(2024, 0, 15));
    expect(row.getCell(1).type).toBe(ExcelJS.ValueType.Date);
    expect(row.getCell(1).numFmt).toBe("yyyy-mm-dd");
    expect(row.getCell(2).value).toBe(42.5);
    expect(row.getCell(2).type).toBe(ExcelJS.ValueType.Number);
    expect(row.getCell(3).value).toBe("Operating");
    expect(row.getCell(3).type).toBe(ExcelJS.ValueType.String);
    expect(row.getCell(4).value).toBeNull();
    expect(row.getCell(4).type).toBe(ExcelJS.ValueType.Null);
  });

  it("stores yearly periods as dates with a year-only number format", async () => {
    const workbook = await buildChartWorkbook({
      rows: [
        ["DateTime", "Units"],
        ["2025-01-01 00:00:00", 7],
      ],
      dateColumnIndex: 0,
      dateNumberFormat: "yyyy",
    });
    const worksheet = workbook.getWorksheet("Data");
    expect(worksheet).toBeDefined();
    if (!worksheet) throw new Error("Data worksheet was not created");

    expect(worksheet.getCell("A2").value).toEqual(new Date(2025, 0, 1));
    expect(worksheet.getCell("A2").numFmt).toBe("yyyy");
  });
});
