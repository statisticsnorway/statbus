"use client";

import {
  useState,
  useCallback,
  useRef,
  useSyncExternalStore,
  MouseEvent,
} from "react";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";
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
const STORAGE_KEY_PREFIX = "statbus:exactCount:";
const savedCountListeners = new Set<() => void>();
const notifySavedCountListeners = () =>
  savedCountListeners.forEach((listener) => listener());

function subscribeSavedCounts(listener: () => void): () => void {
  savedCountListeners.add(listener);
  window.addEventListener("storage", listener);
  return () => {
    savedCountListeners.delete(listener);
    window.removeEventListener("storage", listener);
  };
}

function getCachedExactCount(cacheKey: string): number | null {
  if (typeof window === "undefined") return null;
  try {
    const cached = localStorage.getItem(STORAGE_KEY_PREFIX + cacheKey);
    if (cached !== null) {
      const parsed = parseInt(cached, 10);
      if (!isNaN(parsed)) return parsed;
    }
    return null;
  } catch {
    return null;
  }
}

function setCachedExactCount(cacheKey: string, value: number): void {
  if (typeof window === "undefined") return;
  try {
    localStorage.setItem(STORAGE_KEY_PREFIX + cacheKey, value.toString());
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
      const count = await onGetExact();
      if (count !== null) {
        setCachedExactCount(cacheKey, count);
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
