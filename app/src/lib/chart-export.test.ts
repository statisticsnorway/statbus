import ExcelJS from "@protobi/exceljs";
import { buildChartWorkbook } from "./chart-export";

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
