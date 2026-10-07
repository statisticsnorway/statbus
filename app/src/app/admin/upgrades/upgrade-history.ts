// History bucketing and pill filtering for the admin Upgrades page
// (STATBUS-455). Pure functions so the page's render tests can pin the exact
// filtering contract without a DOM.

export type HistoryPill = "applied" | "superseded" | "skipped";

export const HISTORY_PILLS: { id: HistoryPill; label: string }[] = [
  { id: "applied", label: "Applied" },
  { id: "superseded", label: "Superseded" },
  { id: "skipped", label: "Skipped" },
];

export interface PartitionedUpgrades<T> {
  history: T[];
  available: T[];
  actionable: T[];
}

// The row matching the responding artifact appears once, in the Running card
// at the top of the page — it is excluded from every bucket here so it can
// never show up twice (e.g. both in the card and in History).
export function partitionUpgradeRows<T extends { id: number; state: string }>(
  rows: T[],
  runningId: number | null
): PartitionedUpgrades<T> {
  const partitioned: PartitionedUpgrades<T> = {
    history: [],
    available: [],
    actionable: [],
  };
  for (const u of rows) {
    if (runningId !== null && u.id === runningId) continue;
    const s = u.state;
    if (
      s === "completed" ||
      s === "skipped" ||
      s === "dismissed" ||
      s === "superseded"
    ) {
      partitioned.history.push(u);
    } else if (s === "available") {
      partitioned.available.push(u);
    } else {
      // in_progress, scheduled, failed, rolled_back — all stay actionable.
      // Failed/rolled_back remain visible on the main page so operators see
      // what went wrong without expanding history; clicking Dismiss sets
      // state='dismissed' and moves them to history.
      partitioned.actionable.push(u);
    }
  }
  return partitioned;
}

// "Applied" means actually applied: completed only. (The old header counted
// every non-superseded row as "applied", mislabeling skipped/dismissed rows.)
export function historyRowsForPill<T extends { state: string }>(
  rows: T[],
  pill: HistoryPill
): T[] {
  switch (pill) {
    case "applied":
      return rows.filter((r) => r.state === "completed");
    case "superseded":
      return rows.filter((r) => r.state === "superseded");
    case "skipped":
      return rows.filter(
        (r) => r.state === "skipped" || r.state === "dismissed"
      );
  }
}
