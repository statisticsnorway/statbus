"use client";

import {
  useState,
  useCallback,
  useRef,
  useSyncExternalStore,
  MouseEvent,
} from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
import { getBrowserRestClient } from "@/context/RestClientStore";
import {
  Popover,
  PopoverContent,
  PopoverTrigger,
} from "@/components/ui/popover";
import { Button } from "@/components/ui/button";
import { Info, Loader2 } from "lucide-react";

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
 * The current data version, or null until known. A card adds it to the
 * dependencies of its estimate fetch, so a data change refetches the estimate
 * as well as dropping the saved exact count.
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
 * EstimatedCount, so colour and number come from one value (rwavxg).
 */
export function useSavedExactCount(cacheKey: string): number | null {
  return useSyncExternalStore(
    subscribeSavedCounts,
    () => getCachedExactCount(cacheKey),
    () => null
  );
}

/** The number a count card shows: the saved exact count, else the estimate. */
export function useShownCount(
  cacheKey: string,
  estimatedCount: number | null
): number | null {
  return useSavedExactCount(cacheKey) ?? estimatedCount;
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
// ESTIMATED COUNT COMPONENT
// ============================================================================

interface EstimatedCountProps {
  readonly estimatedCount: number | null;
  readonly onGetExact?: () => Promise<number | null>;
  readonly cacheKey: string; // Unique key for the saved exact count (e.g., "enterprise-2026-11-23"); see useSavedExactCount
  readonly autoFetchDelay?: number; // Max random delay in ms before auto-fetching (default: 10000)
  readonly className?: string;
}

/**
 * Displays an estimated count with a ~ prefix and auto-fetches the exact count
 * after a random delay. Shows a spinner while loading. The info button opens
 * a popover with countdown/status and manual "Get Exact Count" button.
 */
export function EstimatedCount({
  estimatedCount,
  onGetExact,
  cacheKey,
  autoFetchDelay = 10000,
  className,
}: EstimatedCountProps) {
  // The exact count is the saved one; fetching saves it, clearing drops it.
  const exactCount = useSavedExactCount(cacheKey);
  const [isLoading, setIsLoading] = useState(false);
  const [isOpen, setIsOpen] = useState(false);
  const [countdown, setCountdown] = useState<number | null>(null);

  // Refs for cleanup
  const abortControllerRef = useRef<AbortController | null>(null);
  const countdownIntervalRef = useRef<NodeJS.Timeout | null>(null);
  const fetchTimeoutRef = useRef<NodeJS.Timeout | null>(null);

  const handleGetExact = useCallback(async () => {
    if (!onGetExact || isLoading) return;

    // Clear any pending auto-fetch
    if (fetchTimeoutRef.current) {
      clearTimeout(fetchTimeoutRef.current);
      fetchTimeoutRef.current = null;
    }
    if (countdownIntervalRef.current) {
      clearInterval(countdownIntervalRef.current);
      countdownIntervalRef.current = null;
    }
    setCountdown(null);

    // Create abort controller for this request
    abortControllerRef.current = new AbortController();

    setIsLoading(true);
    try {
      // Stamp with the version known before counting: if the data changes
      // while counting, the count is stamped with the old version and dropped.
      if (currentDataVersion === undefined) await refreshDataVersion();
      const version = currentDataVersion;
      const count = await onGetExact();
      if (count !== null && version !== undefined) {
        setCachedExactCount(cacheKey, count, version);
      }
    } catch (error) {
      // Ignore abort errors
      if (error instanceof Error && error.name !== "AbortError") {
        console.error("Failed to fetch exact count:", error);
      }
    } finally {
      setIsLoading(false);
      abortControllerRef.current = null;
    }
  }, [onGetExact, isLoading, cacheKey]);

  // Auto-fetch exact count after random delay
  useGuardedEffect(
    () => {
      // Don't auto-fetch if:
      // - No callback provided
      // - Already have exact count (from cache or previous fetch)
      // - No estimated count to improve upon
      // - Already loading
      if (
        !onGetExact ||
        exactCount !== null ||
        estimatedCount === null ||
        isLoading
      ) {
        return;
      }

      // Random delay between 0 and autoFetchDelay ms
      const delay = Math.floor(Math.random() * autoFetchDelay);
      const delaySeconds = Math.ceil(delay / 1000);

      const countdownStartTimeout = setTimeout(() => {
        setCountdown(delaySeconds);

        // Countdown timer (updates every second)
        countdownIntervalRef.current = setInterval(() => {
          setCountdown((prev) => {
            if (prev === null || prev <= 1) {
              if (countdownIntervalRef.current) {
                clearInterval(countdownIntervalRef.current);
                countdownIntervalRef.current = null;
              }
              return null;
            }
            return prev - 1;
          });
        }, 1000);
      }, 0);

      // Schedule the fetch
      fetchTimeoutRef.current = setTimeout(() => {
        handleGetExact();
      }, delay);

      // Cleanup on unmount or when dependencies change
      return () => {
        clearTimeout(countdownStartTimeout);
        if (fetchTimeoutRef.current) {
          clearTimeout(fetchTimeoutRef.current);
          fetchTimeoutRef.current = null;
        }
        if (countdownIntervalRef.current) {
          clearInterval(countdownIntervalRef.current);
          countdownIntervalRef.current = null;
        }
        if (abortControllerRef.current) {
          abortControllerRef.current.abort();
          abortControllerRef.current = null;
        }
      };
    },
    [
      onGetExact,
      exactCount,
      estimatedCount,
      isLoading,
      autoFetchDelay,
      handleGetExact,
    ],
    "EstimatedCount:autoFetchExact"
  );

  // Stop propagation to prevent parent link from capturing the click
  const handleTriggerClick = useCallback((e: MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setIsOpen((prev) => !prev);
  }, []);

  // Stop propagation for the "Get Exact Count" button too
  const handleGetExactClick = useCallback(
    async (e: MouseEvent) => {
      e.preventDefault();
      e.stopPropagation();
      await handleGetExact();
    },
    [handleGetExact]
  );

  // If we have the exact count, show it without the ~ prefix
  if (exactCount !== null) {
    return <span className={className}>{exactCount.toLocaleString()}</span>;
  }

  // Show estimated count with ~ prefix and info popover
  if (estimatedCount === null) {
    return <span className={className}>-</span>;
  }

  return (
    <span className={className}>
      <span className="inline-flex items-center gap-1">
        <Popover open={isOpen} onOpenChange={setIsOpen}>
          <PopoverTrigger asChild>
            <button
              type="button"
              onClick={handleTriggerClick}
              className="inline-flex items-center hover:text-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 rounded"
              aria-label={
                isLoading
                  ? "Loading exact count"
                  : "Estimated count - click for details"
              }
            >
              {isLoading ? (
                <Loader2 className="h-3 w-3 text-blue-500 animate-spin" />
              ) : (
                <Info className="h-3 w-3 text-gray-400" />
              )}
            </button>
          </PopoverTrigger>
          <PopoverContent className="w-80">
            <div className="space-y-3">
              <h4 className="font-medium">Estimated Count</h4>
              <p className="text-sm text-gray-600">
                This count is estimated from database statistics for faster
                loading. The actual count may differ slightly.
              </p>

              {isLoading ? (
                <div className="flex items-center justify-center py-2">
                  <Loader2 className="mr-2 h-4 w-4 animate-spin text-blue-500" />
                  <span className="text-sm text-gray-600">
                    Loading exact count...
                  </span>
                </div>
              ) : countdown !== null ? (
                <div className="text-center py-2">
                  <p className="text-sm text-gray-600">
                    Auto-loading exact count in {countdown}s...
                  </p>
                  {onGetExact && (
                    <Button
                      onClick={handleGetExactClick}
                      variant="outline"
                      size="sm"
                      className="mt-2 w-full"
                    >
                      Get Exact Count Now
                    </Button>
                  )}
                </div>
              ) : onGetExact ? (
                <Button
                  onClick={handleGetExactClick}
                  variant="outline"
                  size="sm"
                  className="w-full"
                >
                  Get Exact Count
                </Button>
              ) : null}
            </div>
          </PopoverContent>
        </Popover>
        <span>~{estimatedCount.toLocaleString()}</span>
      </span>
    </span>
  );
}
