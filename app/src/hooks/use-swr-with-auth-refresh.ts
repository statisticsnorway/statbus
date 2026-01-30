"use client";

import React from "react";
import useSWR, { SWRConfiguration, SWRResponse, KeyedMutator, Key, Fetcher } from "swr";
import { useAtomValue, useSetAtom } from "jotai";
import { clientSideRefreshAtom, isAuthStableAtom } from "@/atoms/auth";
import { useGuardedEffect } from "@/hooks/use-guarded-effect";

/**
 * Custom error class to identify JWT expiration errors.
 * This can be thrown by fetchers to signal that the JWT has expired.
 */
export class JwtExpiredError extends Error {
  constructor(message: string = "JWT expired") {
    super(message);
    this.name = "JwtExpiredError";
  }
}

/**
 * Check if an error is a JWT expired error.
 * This handles:
 * - JwtExpiredError instances
 * - PostgREST errors with code "PGRST301"
 * - Errors with message "JWT expired"
 */
export const isJwtExpiredError = (error: unknown): boolean => {
  if (error instanceof JwtExpiredError) return true;
  if (error && typeof error === "object") {
    const e = error as Record<string, unknown>;
    if (e.message === "JWT expired") return true;
    if (e.code === "PGRST301") return true;
  }
  return false;
};

/**
 * Extended SWR response that includes auth refresh state.
 */
export interface SWRWithAuthRefreshResponse<Data, Error>
  extends Omit<SWRResponse<Data, Error>, "isLoading"> {
  /** True if SWR is loading OR if we're awaiting auth refresh */
  isLoading: boolean;
  /** True if we're currently waiting for auth refresh after JWT expiration */
  isAwaitingAuthRefresh: boolean;
  /** True if the current error is a JWT expired error (useful for custom UI) */
  isJwtExpiredError: boolean;
}

/**
 * A wrapper around useSWR that automatically handles JWT expiration.
 *
 * When a JWT expires, this hook:
 * 1. Detects the PGRST301 error from PostgREST
 * 2. Triggers the auth refresh mechanism
 * 3. Waits for auth to become stable again
 * 4. Automatically revalidates the SWR cache
 *
 * Usage:
 * ```typescript
 * const fetcher = async (key: string) => {
 *   const client = await getBrowserRestClient();
 *   const { data, error } = await client.from("my_table").select("*");
 *   if (error) throw wrapJwtError(error); // Important: wrap the error
 *   return data;
 * };
 *
 * const { data, error, isLoading, isAwaitingAuthRefresh } = useSWRWithAuthRefresh(
 *   "my-key",
 *   fetcher,
 *   { revalidateOnFocus: false },
 *   "MyComponent:myFetcher"
 * );
 * ```
 *
 * @param key - SWR key (same as useSWR - can be string, array, object, or null)
 * @param fetcher - Fetcher function (should throw JwtExpiredError or PGRST301 error on JWT expiration)
 * @param config - SWR configuration options
 * @param effectId - Unique identifier for the guarded effects (used for debugging loops)
 */
export function useSWRWithAuthRefresh<Data = unknown, SWRError = unknown, SWRKey extends Key = Key>(
  key: SWRKey,
  fetcher: Fetcher<Data, SWRKey> | null,
  config?: SWRConfiguration<Data, SWRError, Fetcher<Data, SWRKey>>,
  effectId?: string
): SWRWithAuthRefreshResponse<Data, SWRError> {
  const triggerRefresh = useSetAtom(clientSideRefreshAtom);
  const isAuthStable = useAtomValue(isAuthStableAtom);

  // Track if we're waiting for auth refresh after a JWT expiration
  const [awaitingAuthRefresh, setAwaitingAuthRefresh] = React.useState(false);
  // Track the previous isAuthStable value to detect when refresh completes
  const prevIsAuthStableRef = React.useRef(isAuthStable);

  const swrResponse = useSWR<Data, SWRError, SWRKey>(key, fetcher, config);
  const { error, mutate } = swrResponse;

  // Generate effect IDs based on the provided effectId or a fallback
  const baseEffectId = effectId || "useSWRWithAuthRefresh";

  // Effect to handle JWT expiration: trigger auth refresh when JWT expired error occurs
  useGuardedEffect(
    () => {
      if (error && isJwtExpiredError(error) && !awaitingAuthRefresh) {
        if (process.env.NODE_ENV === "development") {
          console.log(`[${baseEffectId}] JWT expired, triggering auth refresh`);
        }
        setAwaitingAuthRefresh(true);
        triggerRefresh();
      }
    },
    [error, awaitingAuthRefresh, triggerRefresh, baseEffectId],
    `${baseEffectId}:jwtExpiredHandler`
  );

  // Effect to revalidate SWR after auth refresh completes
  useGuardedEffect(
    () => {
      // Detect transition from unstable to stable (refresh completed)
      const wasUnstable = !prevIsAuthStableRef.current;
      const isNowStable = isAuthStable;
      prevIsAuthStableRef.current = isAuthStable;

      if (awaitingAuthRefresh && wasUnstable && isNowStable) {
        if (process.env.NODE_ENV === "development") {
          console.log(`[${baseEffectId}] Auth refresh completed, revalidating data`);
        }
        setAwaitingAuthRefresh(false);
        mutate();
      }
    },
    [isAuthStable, awaitingAuthRefresh, mutate, baseEffectId],
    `${baseEffectId}:authRefreshComplete`
  );

  // Timeout to prevent getting stuck in awaitingAuthRefresh state if refresh fails
  useGuardedEffect(
    () => {
      if (!awaitingAuthRefresh) return;

      const REFRESH_TIMEOUT_MS = 30000; // 30 seconds
      const timeoutId = setTimeout(() => {
        console.error(`[${baseEffectId}] Auth refresh timed out after ${REFRESH_TIMEOUT_MS}ms`);
        setAwaitingAuthRefresh(false);
      }, REFRESH_TIMEOUT_MS);

      return () => clearTimeout(timeoutId);
    },
    [awaitingAuthRefresh, baseEffectId],
    `${baseEffectId}:refreshTimeout`
  );

  // Consider loading if SWR is loading OR if we're waiting for auth refresh
  const isLoading = swrResponse.isLoading || awaitingAuthRefresh;

  // Don't expose JWT expired error while refreshing
  const exposedError =
    awaitingAuthRefresh && error && isJwtExpiredError(error)
      ? undefined
      : swrResponse.error;

  return {
    ...swrResponse,
    error: exposedError,
    isLoading,
    isAwaitingAuthRefresh: awaitingAuthRefresh,
    isJwtExpiredError: error ? isJwtExpiredError(error) : false,
  };
}

/**
 * Hook that manages JWT refresh state for multiple SWR hooks.
 *
 * Use this when you have multiple SWR hooks in a component and want
 * to coordinate their JWT refresh handling.
 *
 * Usage:
 * ```typescript
 * const { isAwaitingAuthRefresh, handleJwtError, revalidateAll } = useJwtRefreshCoordinator(
 *   [mutateJob, mutateTableData],
 *   "MyComponent"
 * );
 *
 * // In your effects, check errors and call handleJwtError if needed
 * useGuardedEffect(() => {
 *   if (isJwtExpiredError(jobError) || isJwtExpiredError(tableError)) {
 *     handleJwtError();
 *   }
 * }, [jobError, tableError], 'MyComponent:checkErrors');
 * ```
 */
export function useJwtRefreshCoordinator(
  mutators: Array<KeyedMutator<unknown>>,
  componentName: string
): {
  isAwaitingAuthRefresh: boolean;
  handleJwtError: () => void;
  revalidateAll: () => void;
} {
  const triggerRefresh = useSetAtom(clientSideRefreshAtom);
  const isAuthStable = useAtomValue(isAuthStableAtom);

  const [awaitingAuthRefresh, setAwaitingAuthRefresh] = React.useState(false);
  const prevIsAuthStableRef = React.useRef(isAuthStable);

  const handleJwtError = React.useCallback(() => {
    if (!awaitingAuthRefresh) {
      if (process.env.NODE_ENV === "development") {
        console.log(`[${componentName}] JWT expired, triggering auth refresh`);
      }
      setAwaitingAuthRefresh(true);
      triggerRefresh();
    }
  }, [awaitingAuthRefresh, triggerRefresh, componentName]);

  const revalidateAll = React.useCallback(() => {
    mutators.forEach((mutate) => mutate());
  }, [mutators]);

  // Effect to revalidate all SWR caches after auth refresh completes
  useGuardedEffect(
    () => {
      const wasUnstable = !prevIsAuthStableRef.current;
      const isNowStable = isAuthStable;
      prevIsAuthStableRef.current = isAuthStable;

      if (awaitingAuthRefresh && wasUnstable && isNowStable) {
        if (process.env.NODE_ENV === "development") {
          console.log(`[${componentName}] Auth refresh completed, revalidating all data`);
        }
        setAwaitingAuthRefresh(false);
        revalidateAll();
      }
    },
    [isAuthStable, awaitingAuthRefresh, revalidateAll, componentName],
    `${componentName}:authRefreshComplete`
  );

  // Timeout to prevent getting stuck in awaitingAuthRefresh state if refresh fails
  useGuardedEffect(
    () => {
      if (!awaitingAuthRefresh) return;

      const REFRESH_TIMEOUT_MS = 30000; // 30 seconds
      const timeoutId = setTimeout(() => {
        console.error(`[${componentName}] Auth refresh timed out after ${REFRESH_TIMEOUT_MS}ms`);
        setAwaitingAuthRefresh(false);
      }, REFRESH_TIMEOUT_MS);

      return () => clearTimeout(timeoutId);
    },
    [awaitingAuthRefresh, componentName],
    `${componentName}:refreshTimeout`
  );

  return {
    isAwaitingAuthRefresh: awaitingAuthRefresh,
    handleJwtError,
    revalidateAll,
  };
}
