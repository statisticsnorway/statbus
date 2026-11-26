/**
 * f69jcx: a Download menu states its rows once, above CSV and Excel as equal choices, and a finished
 * download is announced by a notification saying what was saved.
 */
import { EXCEL_MAX_DATA_ROWS } from "@/lib/excel-limits";
import { downloadedMessage, downloadMenuHeading, excelUnavailableReason } from "./download-menu-text";

describe("the Download menu heading", () => {
  it("states the rows once, thousands spaced", () => {
    expect(downloadMenuHeading(22445)).toBe("22 445 rows");
    expect(downloadMenuHeading(1)).toBe("1 row");
  });

  it("is absent when the count is not known", () => {
    expect(downloadMenuHeading(null)).toBeNull();
  });
});

describe("Excel in the Download menu", () => {
  it("is offered while the rows fit in one sheet", () => {
    expect(excelUnavailableReason(EXCEL_MAX_DATA_ROWS)).toBeNull();
    expect(excelUnavailableReason(null)).toBeNull();
  });

  it("says why it is not offered beyond the sheet's limit", () => {
    expect(excelUnavailableReason(EXCEL_MAX_DATA_ROWS + 1)).toBe("Excel holds at most 1 048 575 rows. Use CSV.");
  });
});

describe("the notification of a finished download", () => {
  it("names the rows and the time", () => {
    expect(downloadedMessage({ rows: 22445 }, 9400)).toBe("Downloaded 22 445 rows in 9s");
    expect(downloadedMessage({ rows: 2 }, 61000)).toBe("Downloaded 2 rows in 1m 1s");
  });

  it("names the size when the rows are not counted", () => {
    expect(downloadedMessage({ bytes: 2.5 * 1024 * 1024 }, 3000)).toBe("Downloaded 2.5 MB in 3s");
  });
});
