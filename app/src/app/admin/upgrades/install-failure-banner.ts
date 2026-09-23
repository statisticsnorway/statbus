export interface SystemInfoRow {
  key: string;
  value: string;
  updated_at: string;
}

const INSTALL_FAILURE_KEYS = new Set([
  "install_last_error",
  "install_last_error_at",
  "install_last_bundle_path",
]);

export function filterStaleInstallFailure(
  rows: SystemInfoRow[],
  latestCompletedAt: string | null
): SystemInfoRow[] {
  if (!latestCompletedAt) return rows;

  const failureAt = rows.find(
    (row) => row.key === "install_last_error_at"
  )?.value;
  const failureTime = failureAt ? Date.parse(failureAt) : Number.NaN;
  const completionTime = Date.parse(latestCompletedAt);
  const failureIsNewer =
    Number.isFinite(failureTime) &&
    Number.isFinite(completionTime) &&
    failureTime > completionTime;

  return failureIsNewer
    ? rows
    : rows.filter((row) => !INSTALL_FAILURE_KEYS.has(row.key));
}
