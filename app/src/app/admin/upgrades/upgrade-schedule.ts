export type UpgradeScheduleResult =
  | "scheduled"
  | "already_scheduled"
  | "in_progress"
  | "restore_reattempt_required"
  | "unregistered"
  | "superseded";

export interface UpgradeScheduleResponse {
  schedule_result: UpgradeScheduleResult;
  upgrade_id: number | null;
  upgrade_state: string | null;
  superseded_count: number;
}

interface UpgradeSchedulingView {
  state: string;
  backup_path: string | null;
  recovery_parked_at: string | null;
}

export type UpgradeScheduleAction = "rpc" | "install" | "none";

export function isParkedUpgrade(upgrade: UpgradeSchedulingView): boolean {
  return upgrade.state === "in_progress" && upgrade.recovery_parked_at !== null;
}

export function upgradeScheduleAction(
  upgrade: UpgradeSchedulingView
): UpgradeScheduleAction {
  if (upgrade.state === "available" || isParkedUpgrade(upgrade)) {
    return "rpc";
  }
  if (upgrade.state === "rolled_back") {
    return "rpc";
  }
  if (upgrade.state === "failed") {
    return upgrade.backup_path === null ? "rpc" : "install";
  }
  return "none";
}

export function upgradeStateLabel(
  upgrade: UpgradeSchedulingView,
  displayState: string
): string {
  return isParkedUpgrade(upgrade) ? "Parked" : displayState;
}

export function shouldRedirectAfterSchedule(
  result: UpgradeScheduleResult
): boolean {
  return result === "scheduled" || result === "already_scheduled";
}

export function parseUpgradeScheduleResponse(
  value: unknown
): UpgradeScheduleResponse {
  if (!Array.isArray(value) || value.length !== 1) {
    throw new Error("upgrade_schedule returned an unexpected row count");
  }

  const row = value[0] as Record<string, unknown>;
  switch (row.schedule_result) {
    case "scheduled":
    case "already_scheduled":
    case "in_progress":
    case "restore_reattempt_required":
    case "unregistered":
    case "superseded":
      return row as unknown as UpgradeScheduleResponse;
    default:
      throw new Error(
        `upgrade_schedule returned unknown result ${String(row.schedule_result)}`
      );
  }
}

export async function scheduleUpgrade(
  commitSHA: string
): Promise<UpgradeScheduleResponse> {
  const resp = await fetch("/rest/rpc/upgrade_schedule", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    credentials: "include",
    body: JSON.stringify({ p_commit_sha: commitSHA, p_recreate: false }),
  });
  if (!resp.ok) {
    const text = await resp.text();
    throw new Error(`POST upgrade_schedule failed: ${text}`);
  }
  return parseUpgradeScheduleResponse(await resp.json());
}

export function scheduleRefusalMessage(result: UpgradeScheduleResult): string {
  switch (result) {
    case "in_progress":
      return "An upgrade is already in progress. This candidate was not queued.";
    case "restore_reattempt_required":
      return "This failed upgrade has a retained backup. Retry it on the server with ./sb install.";
    case "unregistered":
      return "This candidate is not registered. Run ./sb upgrade check or ./sb upgrade register <version> first.";
    case "superseded":
      return "This candidate is older than an installed completed candidate. It was not queued.";
    case "scheduled":
    case "already_scheduled":
      throw new Error(`${result} is not a scheduling refusal`);
  }
}
