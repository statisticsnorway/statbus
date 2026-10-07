// History bucketing and pill filtering for the admin Upgrades page
// (STATBUS-455). Pure functions so the page's render tests can pin the exact
// filtering contract without a DOM.

export type HistoryPill =
  | "completed"
  | "superseded"
  | "skipped"
  | "dismissed";

// One pill per word that actually appears on a card's state badge
// (public.display_state(): Completed, Superseded, Skipped, Dismissed). The
// filter is never a compound the user cannot point at on screen — the earlier
// "Applied" pill and the skipped+dismissed union both asked the reader to
// translate between the pill and the badge.
export const HISTORY_PILLS: { id: HistoryPill; label: string }[] = [
  { id: "completed", label: "Completed" },
  { id: "superseded", label: "Superseded" },
  { id: "skipped", label: "Skipped" },
  { id: "dismissed", label: "Dismissed" },
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

// Each pill selects exactly the rows whose card carries that word, so
// "Completed" is completed only — never skipped, dismissed or superseded. (The
// old header counted every non-superseded row as "applied", mislabeling
// skipped/dismissed rows.)
export function historyRowsForPill<T extends { state: string }>(
  rows: T[],
  pill: HistoryPill
): T[] {
  return rows.filter((r) => r.state === pill);
}
