// A unit can have multiple temporal rows. Together these columns identify a
// row of statistical_unit_def, even when names and dates are shared.
export function exportOrder(order: string | null): string {
  const columns = (order || "name.asc").split(",").map((part) => part.trim());
  for (const key of ["unit_type", "unit_id", "valid_from", "valid_to"]) {
    if (!columns.some((column) => column.split(".")[0] === key)) {
      columns.push(`${key}.asc`);
    }
  }
  return columns.join(",");
}
