"use client";

/**
 * Worker Status Atoms and Hooks
 *
 * This file contains atoms for monitoring the status of background worker processes.
 * The state is initialized via an RPC call and then kept in sync via Server-Sent Events.
 */

import { atom } from 'jotai';
import { useAtomValue } from 'jotai';
import { restClientAtom } from './app';
import { isAuthenticatedAtom } from './auth';

// ============================================================================
// WORKER STATUS ATOMS
// ============================================================================

export type WorkerStatusType = "is_importing" | "is_deriving_statistical_units" | "is_deriving_reports";

export interface WorkerStatus {
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
  loading: boolean;
  error: string | null;
}

const initialWorkerStatus: WorkerStatus = {
  isImporting: null,
  isDerivingUnits: null,
  isDerivingReports: null,
  loading: true,
  error: null,
};

// A single atom to hold the entire worker status state.
export const workerStatusAtom = atom<WorkerStatus>(initialWorkerStatus);

/**
 * Write-only atom to update a specific worker status field.
 * This is intended to be used by the SSE handler.
 */
export const setWorkerStatusAtom = atom(
  null,
  (get, set, { type, status }: { type: WorkerStatusType, status: boolean }) => {
    const currentStatus = get(workerStatusAtom);
    let updatedStatus: Partial<WorkerStatus> = {};
    if (type === 'is_importing') {
      updatedStatus.isImporting = status;
    } else if (type === 'is_deriving_statistical_units') {
      updatedStatus.isDerivingUnits = status;
    } else if (type === 'is_deriving_reports') {
      updatedStatus.isDerivingReports = status;
    }
    // Set loading to false as this is a direct update, not a fetch.
    set(workerStatusAtom, { ...currentStatus, ...updatedStatus, loading: false, error: null });
  }
);

/**
 * Write-only atom to fetch the initial state of all worker statuses.
 * This should be called once during application initialization.
 */
export const refreshWorkerStatusAtom = atom(
  null,
  async (get, set) => {
    const isAuthenticated = get(isAuthenticatedAtom);
    const client = get(restClientAtom);
    
    // Set loading state
    set(workerStatusAtom, (prev) => ({ ...prev, loading: true, error: null }));

    if (!isAuthenticated || !client) {
      // Not ready to fetch, set to initial (but not loading) state to stop spinners.
      set(workerStatusAtom, { ...initialWorkerStatus, loading: false });
      return;
    }

    try {
      // Fetch all three statuses concurrently for efficiency
      const [importingRes, derivingUnitsRes, derivingReportsRes] = await Promise.all([
        client.rpc('is_importing', {}, { get: true }),
        client.rpc('is_deriving_statistical_units', {}, { get: true }),
        client.rpc('is_deriving_reports', {}, { get: true }),
      ]);

      const error = importingRes.error || derivingUnitsRes.error || derivingReportsRes.error;
      if (error) {
        console.error("Error fetching initial worker statuses", {
          importingError: importingRes.error,
          derivingUnitsError: derivingUnitsRes.error,
          derivingReportsError: derivingReportsRes.error,
        });
        set(workerStatusAtom, (prev) => ({ ...prev, loading: false, error: "Failed to fetch status" }));
        return;
      }

      // On successful fetch, update the state atom
      set(workerStatusAtom, {
        isImporting: importingRes.data,
        isDerivingUnits: derivingUnitsRes.data,
        isDerivingReports: derivingReportsRes.data,
        loading: false,
        error: null,
      });

    } catch (e) {
      console.error("Exception fetching initial worker statuses:", e);
      set(workerStatusAtom, (prev) => ({ ...prev, loading: false, error: "Exception during fetch" }));
    }
  }
);

// ============================================================================
// WORKER STATUS HOOKS
// ============================================================================

/**
 * Hook to consume the current worker status.
 */
export const useWorkerStatus = (): WorkerStatus => {
  return useAtomValue(workerStatusAtom); 
};
