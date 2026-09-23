export function buildChartExportFilenameBase(
  chartType: string,
  unitType: UnitType,
  year: string | number | null | undefined
): string {
  const yearPart =
    year === null || year === undefined || year === "all" ? "all" : year;
  return `${chartType}_${unitType}_year-${yearPart}`;
}

export function joinSubtitleParts(
  parts: (string | null | undefined | false)[]
): string {
  return parts.filter((part): part is string => Boolean(part)).join(" · ");
}

export type ChartExportCell = number | string | null;

interface BuildChartWorkbookOptions {
  readonly rows: ChartExportCell[][];
  readonly dateColumnIndex?: number;
  readonly dateNumberFormat?: "yyyy" | "yyyy-mm-dd";
}

function parseHighchartsDate(value: ChartExportCell): ChartExportCell | Date {
  if (typeof value !== "string") return value;

  const match = /^(\d{4})-(\d{2})-(\d{2})(?: (\d{2}):(\d{2}):(\d{2}))?$/.exec(
    value
  );
  if (!match) return value;

  return new Date(
    Number(match[1]),
    Number(match[2]) - 1,
    Number(match[3]),
    Number(match[4] ?? 0),
    Number(match[5] ?? 0),
    Number(match[6] ?? 0)
  );
}

export async function buildChartWorkbook({
  rows,
  dateColumnIndex,
  dateNumberFormat,
}: BuildChartWorkbookOptions) {
  const { default: ExcelJS } = await import("@protobi/exceljs");
  const workbook = new ExcelJS.Workbook();
  const worksheet = workbook.addWorksheet("Data");

  rows.forEach((sourceRow, rowIndex) => {
    const values = sourceRow.map((value, columnIndex) => {
      if (value === "" || value === null || value === undefined) return null;
      if (rowIndex > 0 && columnIndex === dateColumnIndex) {
        return parseHighchartsDate(value);
      }
      return value;
    });
    worksheet.addRow(values);
  });

  if (dateColumnIndex !== undefined && dateNumberFormat) {
    worksheet.getColumn(dateColumnIndex + 1).numFmt = dateNumberFormat;
  }

  return workbook;
}

export async function downloadChartXlsx(
  rows: ChartExportCell[][],
  filenameBase: string,
  dateNumberFormat?: "yyyy" | "yyyy-mm-dd"
): Promise<void> {
  const workbook = await buildChartWorkbook({
    rows,
    dateColumnIndex: dateNumberFormat ? 0 : undefined,
    dateNumberFormat,
  });
  const buffer = await workbook.xlsx.writeBuffer();
  const blob = new Blob([buffer], {
    type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `${filenameBase}.xlsx`;
  anchor.click();
  URL.revokeObjectURL(url);
}
