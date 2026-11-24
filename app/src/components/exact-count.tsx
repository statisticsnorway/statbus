"use client";

import { useSyncExternalStore } from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { getBrowserRestClient } from "@/context/RestClientStore";
import { Loader2 } from "lucide-react";

// ============================================================================
// LOCALSTORAGE CACHING FOR EXACT COUNTS
// ============================================================================

// Saved exact counts live in localStorage, keyed by cacheKey. They are read
// through useSavedExactCount, an external store, so every reader (the number
// and a card's colour) sees the same value in the same render, from the first
// client render on, and re-renders when a count is saved or cleared.
//
// A saved count belongs to one state of the data: it is stored with the data
// version it was counted at ({"v": version, "n": count}) and shown only while
// that is still the current data version (dwt9kd). A saved count from before
// the last change, or saved before the version is known, is never shown.
const STORAGE_KEY_PREFIX = "statbus:exactCount:";
const savedCountListeners = new Set<() => void>();
const notifySavedCountListeners = () =>
  savedCountListeners.forEach((listener) => listener());

// ============================================================================
// DATA VERSION
// ============================================================================

/**
 * The data version: when the latest derivation of statistical units or
 * reports completed, as an ISO timestamp. Every change to the data a count
 * reads ends in such a derivation, so a new version means counts may differ.
 * "none" when no completed derivation is recorded (completed tasks are purged
 * after a week, so the data has not changed since). undefined until known.
 */
type DataVersion = string;
let currentDataVersion: DataVersion | undefined = undefined;
let dataVersionRequest: Promise<void> | null = null;
let dataVersionRequestAgain = false;
const DATA_VERSION_RETRY_MS = 5000;

async function fetchDataVersion(): Promise<DataVersion | undefined> {
  const client = await getBrowserRestClient();
  const { data, error } = await client
    .from("worker_task")
    .select("completed_at")
    .in("command", ["derive_units_phase", "derive_reports_phase"])
    .eq("state", "completed")
    .order("completed_at", { ascending: false })
    .limit(1);
  if (error) return undefined;
  return data?.[0]?.completed_at ?? "none";
}

/**
 * Reads the data version again; readers re-render when it changed. Called on
 * load and whenever the worker reports a derivation or import has stopped.
 * The stop events arrive coalesced (db-listener relays the newest status per
 * type), so this reads the version on every stop rather than on a start/stop
 * edge. A call made while a read is running reads once more after it.
 */
export function refreshDataVersion(): Promise<void> {
  if (typeof window === "undefined") return Promise.resolve();
  if (dataVersionRequest) {
    dataVersionRequestAgain = true;
    return dataVersionRequest;
  }
  dataVersionRequest = (async () => {
    do {
      dataVersionRequestAgain = false;
      let version: DataVersion | undefined;
      try {
        version = await fetchDataVersion();
      } catch {
        version = undefined;
      }
      if (version !== undefined && version !== currentDataVersion) {
        currentDataVersion = version;
        pruneSavedCounts();
        notifySavedCountListeners();
      }
    } while (dataVersionRequestAgain);
    dataVersionRequest = null;
    // Counts wait for the version (useExactCount), so a failed first read is
    // retried rather than leaving every count card waiting.
    if (currentDataVersion === undefined) {
      setTimeout(() => void refreshDataVersion(), DATA_VERSION_RETRY_MS);
    }
  })();
  return dataVersionRequest;
}

function subscribeSavedCounts(listener: () => void): () => void {
  savedCountListeners.add(listener);
  window.addEventListener("storage", listener);
  if (currentDataVersion === undefined) void refreshDataVersion();
  return () => {
    savedCountListeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}

/**
 * The current data version, or null until known. A count is stamped with it
 * and counted again when it changes (useExactCount).
 */
export function useDataVersion(): string | null {
  return useSyncExternalStore(
    subscribeSavedCounts,
    () => currentDataVersion ?? null,
    () => null
  );
}

interface SavedCount {
  v: DataVersion;
  n: number;
}

function readSavedCount(raw: string | null): SavedCount | null {
  if (raw === null) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<SavedCount> | null;
    if (
      parsed &&
      typeof parsed === "object" &&
      typeof parsed.v === "string" &&
      typeof parsed.n === "number"
    ) {
      return { v: parsed.v, n: parsed.n };
    }
  } catch {
    // Not a stamped count: it belongs to no known data version.
  }
  return null;
}

/** Removes saved counts that belong to another data version than the current. */
function pruneSavedCounts(): void {
  try {
    const keysToRemove: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key?.startsWith(STORAGE_KEY_PREFIX)) continue;
      const saved = readSavedCount(localStorage.getItem(key));
      if (saved?.v !== currentDataVersion) keysToRemove.push(key);
    }
    keysToRemove.forEach((key) => localStorage.removeItem(key));
  } catch {
    // Ignore storage errors
  }
}

function getCachedExactCount(cacheKey: string): number | null {
  if (typeof window === "undefined" || currentDataVersion === undefined)
    return null;
  try {
    const saved = readSavedCount(
      localStorage.getItem(STORAGE_KEY_PREFIX + cacheKey)
    );
    return saved && saved.v === currentDataVersion ? saved.n : null;
  } catch {
    return null;
  }
}

/** Saves a count counted while version was the data version. */
function setCachedExactCount(
  cacheKey: string,
  value: number,
  version: DataVersion
): void {
  if (typeof window === "undefined") return;
  try {
    const saved: SavedCount = { v: version, n: value };
    localStorage.setItem(STORAGE_KEY_PREFIX + cacheKey, JSON.stringify(saved));
  } catch {
    // Ignore storage errors
  }
  notifySavedCountListeners();
}

/**
 * The saved exact count for cacheKey, or null when none is saved. A card that
 * colours itself by its count reads this with the same cacheKey it gives
 * useExactCount, so colour and number come from one value (rwavxg).
 */
export function useSavedExactCount(cacheKey: string): number | null {
  return useSyncExternalStore(
    subscribeSavedCounts,
    () => getCachedExactCount(cacheKey),
    () => null
  );
}

/**
 * Clear all cached exact counts.
 * Called when is_importing completes to force fresh fetches.
 */
export function invalidateExactCountsCache(): void {
  if (typeof window === "undefined") return;
  try {
    const keysToRemove: string[] = [];
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (key?.startsWith(STORAGE_KEY_PREFIX)) {
        keysToRemove.push(key);
      }
    }
    keysToRemove.forEach((key) => localStorage.removeItem(key));
  } catch {
    // Ignore storage errors
  }
  notifySavedCountListeners();
}

// ============================================================================
// COUNTING
// ============================================================================

// A count card asks PostgREST for one exact count and shows a spinner until it
// arrives (fc9xbd). PostgREST's count=estimated runs the same exact count unless
// db-max-rows is set, and setting it would truncate every list response, so an
// estimate step only doubled the load. Counting through countSlots keeps the
// dashboard's counts from filling PostgREST's connection pool: other requests
// (base data, worker status) keep a free connection while the cards count.
const MAX_CONCURRENT_COUNTS = 3;
let runningCounts = 0;
const waitingCounts: (() => void)[] = [];

async function inCountSlot<T>(run: () => Promise<T>): Promise<T> {
  if (runningCounts >= MAX_CONCURRENT_COUNTS) {
    await new Promise<void>((resolve) => waitingCounts.push(resolve));
  }
  runningCounts++;
  try {
    return await run();
  } finally {
    runningCounts--;
    waitingCounts.shift()?.();
  }
}

// One request per cacheKey and data version, shared by every reader and by a
// remount (React StrictMode runs effects twice in development).
const countsInFlight = new Map<string, Promise<void>>();
const failedCountListeners = new Set<() => void>();
const failedCounts = new Set<string>();

function subscribeFailedCounts(listener: () => void): () => void {
  failedCountListeners.add(listener);
  return () => failedCountListeners.delete(listener);
}

/**
 * Counts the rows of a query; error is set when the count could not be made.
 * Memoise it (useCallback) on what the query reads, as for an effect.
 */
export type CountRows = () => Promise<{ count: number | null; error: unknown }>;

/**
 * The exact count for cacheKey: the saved count of the current data version,
 * counted with countRows when none is saved. null while counting or when no
 * cacheKey is given; failed when the count could not be made. Every reader of
 * one cacheKey gets the same value (see useSavedExactCount).
 */
export function useExactCount(
  cacheKey: string | null,
  countRows: CountRows
): { count: number | null; failed: boolean } {
  const saved = useSavedExactCount(cacheKey ?? "");
  const dataVersion = useDataVersion();
  const flightKey = cacheKey && dataVersion ? `${cacheKey}@${dataVersion}` : null;
  const failed = useSyncExternalStore(
    subscribeFailedCounts,
    () => (flightKey ? failedCounts.has(flightKey) : false),
    () => false
  );
  const needsCount = cacheKey !== null && saved === null && !failed;

  // A card shown again tries a failed count once more.
  useGuardedEffect(
    () => {
      if (flightKey && failedCounts.delete(flightKey)) {
        failedCountListeners.forEach((listener) => listener());
      }
    },
    [flightKey],
    "useExactCount:retryFailed"
  );

  useGuardedEffect(
    () => {
      if (!needsCount || !cacheKey || !dataVersion || !flightKey) return;
      if (countsInFlight.has(flightKey)) return;
      const request = inCountSlot(async () => {
        // Stamped with the version known before counting: a count that spans a
        // data change carries the old version and is dropped.
        const { count, error } = await countRows();
        if (error || count === null) {
          failedCounts.add(flightKey);
          failedCountListeners.forEach((listener) => listener());
          console.error(`Count failed for ${cacheKey}:`, error);
          return;
        }
        setCachedExactCount(cacheKey, count, dataVersion);
      }).finally(() => countsInFlight.delete(flightKey));
      countsInFlight.set(flightKey, request);
    },
    [needsCount, cacheKey, dataVersion, flightKey, countRows],
    "useExactCount:count"
  );

  return { count: cacheKey === null ? null : saved, failed };
}

/** A count card's number: a spinner while counting, "-" when the count failed. */
export function ExactCount({
  count,
  failed,
  className,
}: {
  readonly count: number | null;
  readonly failed: boolean;
  readonly className?: string;
}) {
  if (count !== null) {
    return <span className={className}>{count.toLocaleString()}</span>;
  }
  if (failed) {
    return (
      <span className={className} title="The count could not be made">
        -
      </span>
    );
  }
  return (
    <span className={className} role="status" aria-label="Counting">
      <Loader2 className="inline h-5 w-5 animate-spin text-gray-400" />
    </span>
  );
}
