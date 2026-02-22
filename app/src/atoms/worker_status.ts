"use client";

/**
 * Worker Status Atoms and Hooks
 *
 * This file contains atoms for monitoring the status of background worker processes.
 * The state is initialized via an RPC call and then kept in sync via Server-Sent Events.
 */

import { atom } from 'jotai';
import { useAtomValue } from 'jotai';
import { refreshBaseDataAtom, invalidateHasStatisticalUnitsCache } from './base-data';
import { invalidateExactCountsCache } from '@/components/estimated-count';
import { searchPageDataReadyAtom } from './search';
import { restClientAtom } from './rest-client';
import { isAuthenticatedStrictAtom } from './auth';

// ============================================================================
// TYPES
// ============================================================================

export type WorkerStatusType = "is_importing" | "is_deriving_statistical_units" | "is_deriving_reports";

export interface PipelineStep {
  step: string;
  total: number;
  completed: number;
}

export interface ImportJobProgress {
  id: number;
  state: string;
  total_rows: number | null;
  imported_rows: number;
  analysis_completed_pct: number;
  import_completed_pct: number;
}

export interface ImportStatus {
  active: boolean;
  jobs: ImportJobProgress[];
}

export interface PhaseStatus {
  active: boolean;
  progress: PipelineStep[];
}

export interface WorkerStatus {
  // Backward-compatible boolean fields (derived from structured data)
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
  // Structured progress data from JSONB RPC responses
  importing: ImportStatus | null;
  derivingUnits: PhaseStatus | null;
  derivingReports: PhaseStatus | null;
  loading: boolean;
  error: string | null;
}

// SSE payload types
export type WorkerStatusSSEPayload =
  | { type: WorkerStatusType; status: boolean }
  | { type: 'pipeline_progress'; steps: PipelineStep[] };

// ============================================================================
// WORKER STATUS ATOMS
// ============================================================================

const initialWorkerStatus: WorkerStatus = {
  isImporting: null,
  isDerivingUnits: null,
  isDerivingReports: null,
  importing: null,
  derivingUnits: null,
  derivingReports: null,
  loading: true,
  error: null,
};

// A single atom to hold the entire worker status state.
export const workerStatusAtom = atom<WorkerStatus>(initialWorkerStatus);

/**
 * Categorize pipeline steps into Phase 1 (units) vs Phase 2 (reports).
 */
const PHASE1_STEPS = new Set([
  'derive_statistical_unit',
  'derive_statistical_unit_continue',
  'statistical_unit_refresh_batch',
  'statistical_unit_flush_staging',
]);

const PHASE2_STEPS = new Set([
  'derive_reports',
  'derive_statistical_history',
  'derive_statistical_history_period',
  'statistical_history_reduce',
  'derive_statistical_unit_facet',
  'derive_statistical_unit_facet_partition',
  'statistical_unit_facet_reduce',
  'derive_statistical_history_facet',
  'derive_statistical_history_facet_period',
  'statistical_history_facet_reduce',
]);

/**
 * Write-only atom to update a specific worker status field.
 * Handles both boolean status events and pipeline_progress events from SSE.
 */
export const setWorkerStatusAtom = atom(
  null,
  (get, set, payload: WorkerStatusSSEPayload) => {
    const prevStatus = get(workerStatusAtom);

    if (payload.type === 'pipeline_progress') {
      // Update progress data from pipeline_progress notification
      const steps = payload.steps;
      const phase1Steps = steps.filter(s => PHASE1_STEPS.has(s.step));
      const phase2Steps = steps.filter(s => PHASE2_STEPS.has(s.step));

      const newStatus: WorkerStatus = {
        ...prevStatus,
        loading: false,
        error: null,
        derivingUnits: phase1Steps.length > 0
          ? { active: true, progress: phase1Steps.filter(s => s.total > 1) }
          : prevStatus.derivingUnits,
        derivingReports: phase2Steps.length > 0
          ? { active: true, progress: phase2Steps.filter(s => s.total > 1) }
          : prevStatus.derivingReports,
        // Keep boolean fields in sync
        isDerivingUnits: phase1Steps.length > 0 ? true : prevStatus.isDerivingUnits,
        isDerivingReports: phase2Steps.length > 0 ? true : prevStatus.isDerivingReports,
      };
      set(workerStatusAtom, newStatus);
      return;
    }

    // Boolean status events (from notify_*_stop procedures)
    const { type, status } = payload;
    const updatedStatus: Partial<WorkerStatus> = {};

    if (type === 'is_importing') {
      updatedStatus.isImporting = status;
      if (!status) {
        updatedStatus.importing = { active: false, jobs: [] };
      }
    } else if (type === 'is_deriving_statistical_units') {
      updatedStatus.isDerivingUnits = status;
      if (!status) {
        updatedStatus.derivingUnits = { active: false, progress: [] };
      }
    } else if (type === 'is_deriving_reports') {
      updatedStatus.isDerivingReports = status;
      if (!status) {
        updatedStatus.derivingReports = { active: false, progress: [] };
      }
    }

    const newStatusState = { ...prevStatus, ...updatedStatus, loading: false, error: null };
    set(workerStatusAtom, newStatusState);

    // Key condition: Check if the unit derivation process has just completed.
    if (
      type === 'is_deriving_statistical_units' &&
      prevStatus.isDerivingUnits === true &&
      status === false
    ) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("setWorkerStatusAtom: Detected completion of 'isDerivingUnits'. Refreshing base data and invalidating search page data.");
      }
      set(refreshBaseDataAtom);
      set(searchPageDataReadyAtom, false);
    }

    // When import completes, invalidate all caches.
    if (
      type === 'is_importing' &&
      prevStatus.isImporting === true &&
      status === false
    ) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("setWorkerStatusAtom: Detected completion of 'isImporting'. Invalidating caches.");
      }
      invalidateHasStatisticalUnitsCache();
      invalidateExactCountsCache();
      set(refreshBaseDataAtom);
    }
  }
);

/**
 * Write-only atom to fetch the initial state of all worker statuses.
 * This should be called once during application initialization.
 */
export const refreshWorkerStatusAtom = atom(
  null,
  async (get, set) => {
    const isAuthenticated = get(isAuthenticatedStrictAtom);
    const client = get(restClientAtom);

    // Set loading state
    set(workerStatusAtom, (prev) => ({ ...prev, loading: true, error: null }));

    if (!isAuthenticated || !client) {
      set(workerStatusAtom, { ...initialWorkerStatus, loading: false });
      return;
    }

    try {
      // Fetch all three statuses concurrently for efficiency
      const [importingRes, derivingUnitsRes, derivingReportsRes] = await Promise.all([
        client.rpc('is_importing', undefined, { get: true }),
        client.rpc('is_deriving_statistical_units', undefined, { get: true }),
        client.rpc('is_deriving_reports', undefined, { get: true }),
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

      // Parse JSONB responses - PostgREST types still say boolean but DB returns jsonb objects
      const importData = importingRes.data as unknown as ImportStatus | null;
      const unitsData = derivingUnitsRes.data as unknown as PhaseStatus | null;
      const reportsData = derivingReportsRes.data as unknown as PhaseStatus | null;

      set(workerStatusAtom, {
        isImporting: importData?.active ?? null,
        isDerivingUnits: unitsData?.active ?? null,
        isDerivingReports: reportsData?.active ?? null,
        importing: importData,
        derivingUnits: unitsData,
        derivingReports: reportsData,
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

// ============================================================================
// COMMAND LABEL MAPPING
// ============================================================================

export const COMMAND_LABELS: Record<string, string> = {
  'derive_statistical_unit': 'Refreshing statistical units',
  'derive_statistical_unit_continue': 'Refreshing statistical units',
  'derive_statistical_history': 'Computing statistical history',
  'derive_statistical_unit_facet': 'Computing search facets',
  'derive_statistical_history_facet': 'Computing history facets',
};
