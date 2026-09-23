import {
  compareCalendarVersions,
  compareUpgradeCandidates,
} from "./upgrade-ordering";

describe("upgrade candidate ordering", () => {
  test("ranks rc.31 ahead of rc.30 even when rc.31 has the lower insertion id", () => {
    const candidates = [
      {
        id: 162949,
        display_name: "v2026.09.1-rc.30",
        release_status: "prerelease" as const,
        committed_at: "2026-09-23T05:12:11Z",
      },
      {
        id: 162948,
        display_name: "v2026.09.1-rc.31",
        release_status: "prerelease" as const,
        committed_at: "2026-09-23T07:13:55Z",
      },
    ];

    candidates.sort(compareUpgradeCandidates);

    expect(candidates.map((candidate) => candidate.display_name)).toEqual([
      "v2026.09.1-rc.31",
      "v2026.09.1-rc.30",
    ]);
  });

  test("uses committed_at only when calendar versions compare equal", () => {
    const candidates = [
      {
        display_name: "v2026.09.1-rc.31",
        release_status: "prerelease" as const,
        committed_at: "2026-09-23T05:12:11Z",
      },
      {
        display_name: "vv2026.09.1-rc.31",
        release_status: "prerelease" as const,
        committed_at: "2026-09-23T07:13:55Z",
      },
    ];

    candidates.sort(compareUpgradeCandidates);
    expect(candidates[0].display_name).toBe("vv2026.09.1-rc.31");
  });

  test("matches release ordering semantics for stable and prerelease versions", () => {
    expect(compareCalendarVersions("v2026.09.1", "v2026.09.1-rc.31")).toBe(1);
    expect(compareCalendarVersions("v2026.10.0-rc.1", "v2026.09.9-rc.99")).toBe(
      1
    );
    expect(compareCalendarVersions("v2026.09.1-rc.10", "v2026.09.1-rc.9")).toBe(
      1
    );
  });
});
