

export function buildChartExportFilenameBase(
  chartType: string,
  unitType: UnitType,
  year: string | number | null | undefined
): string {
  const yearPart = year === null || year === undefined || year === "all" ? "all" : year;
  return `${chartType}_${unitType}_year-${yearPart}`;
}

export function joinSubtitleParts(parts: (string | null | undefined | false)[]): string {
  return parts.filter((part): part is string => Boolean(part)).join(" · ");
}

