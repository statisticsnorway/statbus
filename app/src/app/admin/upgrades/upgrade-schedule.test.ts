import {
  scheduleUpgrade,
  shouldRedirectAfterSchedule,
  upgradeScheduleAction,
  upgradeStateLabel,
  type UpgradeScheduleResult,
} from "./upgrade-schedule";

const scheduledResponse = [
  {
    schedule_result: "scheduled",
    upgrade_id: 1,
    upgrade_state: "scheduled",
    superseded_count: 0,
  },
];

describe("upgrade scheduling UI contract", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  test("available and every retryable state use the same RPC", async () => {
    const fetchMock = jest.spyOn(global, "fetch").mockResolvedValue({
      ok: true,
      json: async () => scheduledResponse,
    } as Response);
    const cases = [
      {
        state: "available",
        backup_path: null,
        recovery_parked_at: null,
      },
      {
        state: "failed",
        backup_path: null,
        recovery_parked_at: null,
      },
      {
        state: "rolled_back",
        backup_path: "/backup/from-attempt.dump",
        recovery_parked_at: null,
      },
      {
        state: "in_progress",
        backup_path: "/backup/parked.dump",
        recovery_parked_at: "2026-09-01T20:00:00Z",
      },
    ];

    for (const [index, upgrade] of cases.entries()) {
      expect(upgradeScheduleAction(upgrade)).toBe("rpc");
      await scheduleUpgrade(String(index).padStart(40, "a"));
    }

    expect(fetchMock).toHaveBeenCalledTimes(cases.length);
    for (const [index, call] of fetchMock.mock.calls.entries()) {
      expect(call[0]).toBe("/rest/rpc/upgrade_schedule");
      expect(call[1]).toEqual({
        method: "POST",
        headers: { "Content-Type": "application/json" },
        credentials: "include",
        body: JSON.stringify({
          p_commit_sha: String(index).padStart(40, "a"),
          p_recreate: false,
        }),
      });
    }
  });

  test("parked rows render Parked instead of Upgrading", () => {
    const parked = {
      state: "in_progress",
      backup_path: null,
      recovery_parked_at: "2026-09-01T20:00:00Z",
    };
    expect(upgradeStateLabel(parked, "Upgrading")).toBe("Parked");
  });

  test("failed rows with a retained backup require install and have no RPC action", () => {
    expect(
      upgradeScheduleAction({
        state: "failed",
        backup_path: "/backup/restore.dump",
        recovery_parked_at: null,
      })
    ).toBe("install");
  });

  test.each<UpgradeScheduleResult>([
    "superseded",
    "in_progress",
    "restore_reattempt_required",
    "unregistered",
  ])("%s keeps the operator on the upgrades page", (result) => {
    expect(shouldRedirectAfterSchedule(result)).toBe(false);
  });

  test.each<UpgradeScheduleResult>(["scheduled", "already_scheduled"])(
    "%s redirects to maintenance after refresh",
    (result) => {
      expect(shouldRedirectAfterSchedule(result)).toBe(true);
    }
  );
});
