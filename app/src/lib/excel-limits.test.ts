import {
  EXCEL_MAX_DATA_ROWS,
  EXCEL_MAX_ROWS,
  excelDataRowsFit,
} from "./excel-limits";

describe("excel-limits", () => {
  it("counts the header row against the sheet: 1,048,575 data rows at most", () => {
    expect(EXCEL_MAX_ROWS).toBe(1_048_576);
    expect(EXCEL_MAX_DATA_ROWS).toBe(1_048_575);
  });

  it("fits exactly the data rows a sheet can hold below its header, and not one more", () => {
    expect(excelDataRowsFit(0)).toBe(true);
    expect(excelDataRowsFit(1_048_575)).toBe(true);
    // 1,048,576 data rows + the header = 1,048,577 rows: does not fit. The
    // import download, its button and the command palette used to accept it.
    expect(excelDataRowsFit(1_048_576)).toBe(false);
  });
});
