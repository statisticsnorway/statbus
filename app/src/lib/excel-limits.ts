/**
 * Excel (.xlsx) format limits: the ONE definition every export imports
 * (STATBUS-421).
 *
 * A worksheet holds at most 1,048,576 rows INCLUDING the header row, so an
 * export with a header carries at most EXCEL_MAX_DATA_ROWS = 1,048,575 data
 * rows. Comparing a data-row count against EXCEL_MAX_ROWS is the classic
 * off-by-one: 1,048,576 data rows plus the header do not fit.
 */
export const EXCEL_MAX_ROWS = 1_048_576;

/** Data rows that fit in one sheet below its header row. */
export const EXCEL_MAX_DATA_ROWS = EXCEL_MAX_ROWS - 1;

/** Characters a single cell may hold. */
export const EXCEL_MAX_CELL_CHARS = 32_767;

/** True when `dataRows` rows plus a header row fit in one sheet. */
export function excelDataRowsFit(dataRows: number): boolean {
  return dataRows <= EXCEL_MAX_DATA_ROWS;
}
