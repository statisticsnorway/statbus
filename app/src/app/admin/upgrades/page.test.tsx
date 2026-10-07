/**
 * Render tests for the admin Upgrades page (STATBUS-455).
 *
 * The app's Jest environment is node (no jsdom/testing-library), so these
 * render the page with renderToStaticMarkup: SWR is fed through fallback
 * data (effects never run, nothing fetches) and the jotai atoms are seeded
 * into an isolated store. Radix Collapsible unmounts closed content, so the
 * assertions target what is actually visible: the Running card's header,
 * meta, disclosures and open-by-default log, plus the History header pills.
 * Pill filtering and running-row exclusion are pinned by
 * upgrade-history.test.ts.
 */
import { renderToStaticMarkup } from "react-dom/server";
import { Provider, createStore } from "jotai";
import { SWRConfig } from "swr";
import UpgradesPage, { type Upgrade } from "./page";
import { artifactSHAAtom, runningIdentityAtom } from "@/atoms/running-identity";
import type { RunningIdentity } from "@/lib/running-identity";
import type { SystemInfoRow } from "./install-failure-banner";

const RUNNING_SHA = "bce5bf39b73fcb87ee55900fab927c36872e23c0";

const LIST_KEY =
  "/rest/upgrade?select=*,display_name,display_state&order=committed_at.desc&limit=100";
const SYSTEM_INFO_KEY = "/rest/system_info";
const currentKey = (sha: string) =>
  `/rest/upgrade?select=*,display_name,display_state&commit_sha=eq.${sha}`;

function makeUpgrade(overrides: Partial<Upgrade>): Upgrade {
  return {
    id: 1,
    commit_sha: "0".repeat(40),
    committed_at: "2026-10-01T00:00:00Z",
    commit_tags: [],
    release_status: "commit",
    display_name: "edge commit",
    display_state: "Available",
    state: "available",
    summary: "",
    changes: null,
    release_url: null,
    has_migrations: false,
    from_commit_version: null,
    scheduled_at: null,
    started_at: null,
    completed_at: null,
    error: null,
    log_relative_file_path: null,
    rolled_back_at: null,
    docker_images_status: "ready",
    release_builds_status: "ready",
    skipped_at: null,
    dismissed_at: null,
    superseded_at: null,
    docker_images_downloaded: false,
    backup_path: null,
    recovery_attempts: 0,
    recovery_parked_at: null,
    recovery_parked_reason: null,
    ...overrides,
  };
}

const runningRow = makeUpgrade({
  id: 227495,
  commit_sha: RUNNING_SHA,
  state: "completed",
  display_name: "v2026.10.0-rc.20",
  display_state: "Completed",
  release_status: "prerelease",
  commit_tags: ["v2026.10.0-rc.20"],
  committed_at: "2026-10-07T09:00:00Z",
  scheduled_at: "2026-10-07T09:50:28Z",
  started_at: "2026-10-07T09:50:40Z",
  completed_at: "2026-10-07T09:51:32Z",
  log_relative_file_path: "v2026.10.0-rc.20-20261007T095040Z.log",
  changes: "Some changelog text",
});

const olderCompleted = makeUpgrade({
  id: 227400,
  state: "completed",
  display_name: "v2026.09.0",
  display_state: "Completed",
  release_status: "release",
  completed_at: "2026-09-01T10:00:00Z",
  started_at: "2026-09-01T09:00:00Z",
});
const supersededRow = makeUpgrade({
  id: 227300,
  state: "superseded",
  display_name: "v2026.08.0",
  display_state: "Superseded",
});
const skippedRow = makeUpgrade({
  id: 227200,
  state: "skipped",
  display_name: "v2026.07.0",
  display_state: "Skipped",
});

const runningIdentity: RunningIdentity = {
  commit_sha: RUNNING_SHA,
  resolved_name: "v2026.10.0-rc.20",
  release_status: "prerelease",
  build_name: null,
};

const systemInfoRows: SystemInfoRow[] = [
  { key: "upgrade_channel", value: "prerelease", updated_at: "2026-10-07" },
  {
    key: "install_last_at",
    value: "2026-10-06T08:30:49Z",
    updated_at: "2026-10-06",
  },
  {
    key: "install_last_log_relative_file_path",
    value: "v2026.10.0-rc.16-20261006T083000Z.log",
    updated_at: "2026-10-06",
  },
];

function renderPage({
  artifactSHA = RUNNING_SHA as string | null,
  identity = null as RunningIdentity | null,
  currentRows,
  rows,
}: {
  artifactSHA?: string | null;
  identity?: RunningIdentity | null;
  currentRows?: Upgrade[];
  rows: Upgrade[];
}): string {
  const store = createStore();
  store.set(artifactSHAAtom, artifactSHA);
  if (identity) store.set(runningIdentityAtom, identity);
  const fallback: Record<string, unknown> = {
    [LIST_KEY]: rows,
    [SYSTEM_INFO_KEY]: { rows: systemInfoRows, observedAt: 0 },
  };
  if (artifactSHA && currentRows !== undefined) {
    fallback[currentKey(artifactSHA)] = currentRows;
  }
  return renderToStaticMarkup(
    <SWRConfig value={{ fallback, provider: () => new Map() }}>
      <Provider store={store}>
        <UpgradesPage />
      </Provider>
    </SWRConfig>
  );
}

test("serving release renders as one Running card with id, meta, disclosures and open log", () => {
  const html = renderPage({
    currentRows: [runningRow],
    rows: [runningRow, olderCompleted, supersededRow, skippedRow],
  });

  // Card header: name, short SHA, real state badge.
  expect(html).toContain("v2026.10.0-rc.20");
  expect(html).toContain("(bce5bf39)");
  expect(html).toContain("pre-release");
  expect(html).toContain(">Running<");

  // Serving line + id + Committed/Scheduled/Completed.
  expect(html).toContain("Serving now");
  expect(html).toContain("227495");
  expect(html).toContain("Committed:");
  expect(html).toContain("Scheduled:");
  expect(html).toContain("Completed:");

  // Disclosures present; the full SHA and the install invocation are behind
  // them, not loose on the page.
  expect(html).toContain("Details");
  expect(html).toContain("Installs");
  expect(html).not.toContain("Currently responding app");
  expect(html).not.toContain("Last install invocation:");

  // Log open by default: the content area rendered, fetch pending.
  expect(html).toContain("Loading...");

  // Changelog collapsed.
  expect(html).toContain("Changelog");
  expect(html).not.toContain("Some changelog text");

  // History header: exactly "History", pills, no counts.
  expect(html).toContain(">History<");
  expect(html).toContain(">Applied<");
  expect(html).toContain(">Superseded<");
  expect(html).toContain(">Skipped<");
  expect(html).not.toContain("applied ·");

  // History is collapsed by default: its rows are not in the markup.
  expect(html).not.toContain("v2026.09.0");
});

test("no unique exact-SHA row still renders the card with an honest gap note", () => {
  const html = renderPage({
    identity: runningIdentity,
    currentRows: [],
    rows: [olderCompleted],
  });
  expect(html).toContain("no matching install record");
  // The artifact provably serves, so the card is still the Running card and
  // falls back to the identity-proven name.
  expect(html).toContain(">Running<");
  expect(html).toContain("v2026.10.0-rc.20");
});

test("a matched but non-completed row shows its true state, never Running", () => {
  const failedRow = makeUpgrade({
    id: 227495,
    commit_sha: RUNNING_SHA,
    state: "failed",
    display_name: "v2026.10.0-rc.20",
    display_state: "Failed",
    release_status: "prerelease",
    started_at: "2026-10-07T09:50:40Z",
    error: "boom",
  });
  const html = renderPage({ currentRows: [failedRow], rows: [failedRow] });
  expect(html).toContain(">Failed<");
  expect(html).not.toContain(">Running<");
});

test("the card shows a loading state while the exact-SHA query is in flight", () => {
  const html = renderPage({ rows: [olderCompleted] });
  expect(html).toContain("Loading");
  expect(html).toContain("Resolving the install record");
  expect(html).not.toContain(">Running<");
});

test("without a proven artifact the card says unknown instead of disappearing", () => {
  const html = renderPage({ artifactSHA: null, rows: [olderCompleted] });
  expect(html).toContain(">Unknown<");
  expect(html).toContain("responding artifact unknown");
});

test("the running row is lifted out of History entirely", () => {
  // With the running row as the only history-state row, exclusion leaves
  // History empty and the section disappears — the row appears only in the
  // Running card.
  const html = renderPage({ currentRows: [runningRow], rows: [runningRow] });
  expect(html).toContain(">Running<");
  expect(html).not.toContain(">History<");
  expect(html).not.toContain(">Applied<");
});
