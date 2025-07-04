"use client";

/**
 * Worker Status Atoms and Hooks
 *
 * This file contains atoms and hooks for monitoring the status of background
 * worker processes, such as data imports and derivations.
 */

import { atom } from 'jotai'
import { atomWithRefresh, loadable } from 'jotai/utils'
import { useAtomValue } from 'jotai'

import type { PostgrestClient } from '@supabase/postgrest-js'
import type { Database } from '@/lib/database.types'
import { restClientAtom } from './app'
import { isAuthenticatedAtom } from './auth'

// ============================================================================
// WORKER STATUS ATOMS - Replace BaseDataStore worker status
// ============================================================================

export type ValidWorkerFunctionName = "is_importing" | "is_deriving_statistical_units" | "is_deriving_reports";

export interface WorkerStatusData {
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
}

const initialWorkerStatusData: WorkerStatusData = {
  isImporting: null,
  isDerivingUnits: null,
  isDerivingReports: null,
};

// Individual core async atoms for each worker status
const makeWorkerStatusFetcherAtom = (rpcName: ValidWorkerFunctionName) => {
  // Explicitly type the return of the async function for atomWithRefresh
  return atomWithRefresh<Promise<boolean | null>>(async (get): Promise<boolean | null> => {
    const isAuthenticated = get(isAuthenticatedAtom);
    const client = get(restClientAtom);

    if (!isAuthenticated) return null;

    if (!client) {
      if (typeof window !== 'undefined') {
        // Client-side, authenticated, but client is not ready. Return a promise that never resolves.
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log(`WorkerStatusFetcher (${rpcName}): Client-side, REST client not yet initialized. Holding in loading state.`);
        }
        return new Promise<boolean | null>(() => {}); // Cast to expected Promise type
      }
      // Server-side, client not ready, or unauthenticated.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`WorkerStatusFetcher (${rpcName}): Server-side or pre-client-init, REST client not available. Returning null.`);
      }
      return null;
    }

    try {
      // For GET requests with PostgREST RPC, use the 'get: true' option.
      const { data, error } = await client.rpc(rpcName, {}, { get: true });
      if (error) {
        console.error(`Error fetching ${rpcName}:`, error);
        return null;
      }
      return data ?? null;
    } catch (e) {
      console.error(`Exception fetching ${rpcName}:`, e);
      return null;
    }
  });
};

export const isImportingCoreAtom = makeWorkerStatusFetcherAtom("is_importing");
export const isDerivingUnitsCoreAtom = makeWorkerStatusFetcherAtom("is_deriving_statistical_units");
export const isDerivingReportsCoreAtom = makeWorkerStatusFetcherAtom("is_deriving_reports");

// Loadable versions of the individual core atoms
export const isImportingLoadableAtom = loadable(isImportingCoreAtom);
export const isDerivingUnitsLoadableAtom = loadable(isDerivingUnitsCoreAtom);
export const isDerivingReportsLoadableAtom = loadable(isDerivingReportsCoreAtom);

// Interface for the synchronous view of worker status, including loading/error states
export interface WorkerStatus {
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
  loading: boolean;
  error: string | null;
}

// Combined workerStatusAtom (synchronous view)
export const workerStatusAtom = atom<WorkerStatus>((get) => {
  const impLoadable = get(isImportingLoadableAtom);
  const unitsLoadable = get(isDerivingUnitsLoadableAtom);
  const reportsLoadable = get(isDerivingReportsLoadableAtom);

  const isLoading = impLoadable.state === 'loading' || 
                    unitsLoadable.state === 'loading' || 
                    reportsLoadable.state === 'loading';
  
  let combinedError: string | null = null;
  if (impLoadable.state === 'hasError') {
    combinedError = `Import status error: ${impLoadable.error instanceof Error ? impLoadable.error.message : String(impLoadable.error)}`;
  } else if (unitsLoadable.state === 'hasError') {
    combinedError = `Deriving units status error: ${unitsLoadable.error instanceof Error ? unitsLoadable.error.message : String(unitsLoadable.error)}`;
  } else if (reportsLoadable.state === 'hasError') {
    combinedError = `Deriving reports status error: ${reportsLoadable.error instanceof Error ? reportsLoadable.error.message : String(reportsLoadable.error)}`;
  }
  // Note: This only captures the first error. A more complex error aggregation could be implemented if needed.

  return {
    isImporting: impLoadable.state === 'hasData' ? impLoadable.data : initialWorkerStatusData.isImporting,
    isDerivingUnits: unitsLoadable.state === 'hasData' ? unitsLoadable.data : initialWorkerStatusData.isDerivingUnits,
    isDerivingReports: reportsLoadable.state === 'hasData' ? reportsLoadable.data : initialWorkerStatusData.isDerivingReports,
    loading: isLoading,
    error: combinedError,
  };
});

// The refreshWorkerStatusAtom now accepts an optional function name to refresh a specific status,
// or refreshes all if no name is provided.
export const refreshWorkerStatusAtom = atom(
  null, 
  (get, set, functionName?: ValidWorkerFunctionName) => {
    if (functionName === "is_importing") {
      set(isImportingCoreAtom);
    } else if (functionName === "is_deriving_statistical_units") {
      set(isDerivingUnitsCoreAtom);
    } else if (functionName === "is_deriving_reports") {
      set(isDerivingReportsCoreAtom);
    } else { // undefined or any other case, refresh all
      set(isImportingCoreAtom);
      set(isDerivingUnitsCoreAtom);
      set(isDerivingReportsCoreAtom);
    }
  }
);

// ============================================================================
// WORKER STATUS HOOKS
// ============================================================================

export const useWorkerStatus = (): WorkerStatus => {
  // workerStatusAtom (the synchronous wrapper) is explicitly typed as returning WorkerStatus
  return useAtomValue(workerStatusAtom); 
}
