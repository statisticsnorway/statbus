import {
  filterStaleInstallFailure,
  SystemInfoRow,
} from "./install-failure-banner";

const failureRows: SystemInfoRow[] = [
  {
    key: "install_last_error",
    value: "install failed",
    updated_at: "2026-09-23T10:00:00Z",
  },
  {
    key: "install_last_error_at",
    value: "2026-09-23T10:00:00Z",
    updated_at: "2026-09-23T10:00:00Z",
  },
  {
    key: "install_last_bundle_path",
    value: "tmp/support.tar.gz",
    updated_at: "2026-09-23T10:00:00Z",
  },
  {
    key: "upgrade_channel",
    value: "stable",
    updated_at: "2026-09-23T10:00:00Z",
  },
];

describe("install failure banner temporal guard", () => {
  test("hides a failure older than a later completed upgrade", () => {
    const rows = filterStaleInstallFailure(failureRows, "2026-09-23T10:01:00Z");

    expect(rows).toEqual([failureRows[3]]);
  });

  test("shows a failure newer than the latest completed upgrade", () => {
    const rows = filterStaleInstallFailure(failureRows, "2026-09-23T09:59:00Z");

    expect(rows).toBe(failureRows);
  });
});
