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
import { invalidateExactCountsCache, exactCountCacheGenerationAtom } from '@/components/estimated-count';
import { searchPageDataReadyAtom } from './search';
import { restClientAtom } from './rest-client';
import { isAuthenticatedStrictAtom } from './auth';

// ============================================================================
// TYPES
// ============================================================================

export type WorkerStatusType = "is_importing" | "is_deriving_statistical_units" | "is_deriving_reports";

export type PipelinePhase = 'is_deriving_statistical_units' | 'is_deriving_reports';

export interface PhaseProgress {
  phase: PipelinePhase;
  step: string | null;
  total: number;
  completed: number;
  affected_establishment_count: number | null;
  affected_legal_unit_count: number | null;
  affected_enterprise_count: number | null;
  affected_power_group_count: number | null;
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
  step: string | null;
  total: number;
  completed: number;
  affected_establishment_count: number | null;
  affected_legal_unit_count: number | null;
  affected_enterprise_count: number | null;
  affected_power_group_count: number | null;
}

export interface PipelineStepWeight {
  phase: string;
  step: string;
  weight: number;
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
export type ImportJobProgressSSE = {
  type: 'import_job_progress';
  job_id: number;
  state: string;
  total_rows: number | null;
  analysis_completed_pct: number;
  imported_rows: number;
  import_completed_pct: number;
};

export type WorkerStatusSSEPayload =
  | { type: WorkerStatusType; status: boolean }
  | { type: 'pipeline_progress'; phases: PhaseProgress[] }
  | ImportJobProgressSSE;

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

// Pipeline step weights from the database (static configuration, fetched once).
export const pipelineStepWeightsAtom = atom<PipelineStepWeight[]>([]);

/**
 * Write-only atom to update a specific worker status field.
 * Handles both boolean status events and pipeline_progress events from SSE.
 */
export const setWorkerStatusAtom = atom(
  null,
  (get, set, payload: WorkerStatusSSEPayload) => {
    const prevStatus = get(workerStatusAtom);

    if (payload.type === 'import_job_progress') {
      // Real-time import job progress from import_job_progress pg_notify
      const { job_id, state, total_rows, analysis_completed_pct, imported_rows, import_completed_pct } = payload;
      const currentJobs = prevStatus.importing?.jobs ?? [];
      const updatedJob: ImportJobProgress = {
        id: job_id,
        state,
        total_rows,
        imported_rows,
        analysis_completed_pct,
        import_completed_pct,
      };

      const newJobs = [...currentJobs];
      const existingIdx = newJobs.findIndex(j => j.id === job_id);
      if (existingIdx >= 0) {
        newJobs[existingIdx] = updatedJob;
      } else {
        newJobs.push(updatedJob);
      }

      // Only keep actively importing jobs
      const activeJobs = newJobs.filter(j => j.state === 'analysing_data' || j.state === 'processing_data');

      set(workerStatusAtom, {
        ...prevStatus,
        loading: false,
        error: null,
        isImporting: activeJobs.length > 0 ? true : prevStatus.isImporting,
        importing: { active: activeJobs.length > 0, jobs: activeJobs },
      });
      return;
    }

    if (payload.type === 'pipeline_progress') {
      // Phase-based progress data from pg_notify
      const phases = payload.phases;
      const phase1 = phases.find(p => p.phase === 'is_deriving_statistical_units');
      const phase2 = phases.find(p => p.phase === 'is_deriving_reports');

      const toPhaseStatus = (p: PhaseProgress | undefined): PhaseStatus | null => {
        if (!p) return null;
        return {
          active: true,
          step: p.step,
          total: p.total,
          completed: p.completed,
          affected_establishment_count: p.affected_establishment_count,
          affected_legal_unit_count: p.affected_legal_unit_count,
          affected_enterprise_count: p.affected_enterprise_count,
          affected_power_group_count: p.affected_power_group_count,
        };
      };

      const newStatus: WorkerStatus = {
        ...prevStatus,
        loading: false,
        error: null,
        derivingUnits: phase1 ? toPhaseStatus(phase1) : prevStatus.derivingUnits,
        derivingReports: phase2 ? toPhaseStatus(phase2) : prevStatus.derivingReports,
        // Keep boolean fields in sync
        isDerivingUnits: phase1 ? true : prevStatus.isDerivingUnits,
        isDerivingReports: phase2 ? true : prevStatus.isDerivingReports,
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
        // Import completed — clear jobs
        updatedStatus.importing = { active: false, jobs: [] };
      } else if (!prevStatus.importing?.active) {
        // New import starting — mark active, keep any jobs from initial RPC
        updatedStatus.importing = { active: true, jobs: prevStatus.importing?.jobs ?? [] };
      }
    } else if (type === 'is_deriving_statistical_units') {
      updatedStatus.isDerivingUnits = status;
      if (!status) {
        updatedStatus.derivingUnits = null;
      }
    } else if (type === 'is_deriving_reports') {
      updatedStatus.isDerivingReports = status;
      if (!status) {
        updatedStatus.derivingReports = null;
      }
    }

    const newStatusState = { ...prevStatus, ...updatedStatus, loading: false, error: null };
    set(workerStatusAtom, newStatusState);

    // Key condition: Check if the unit derivation process has just completed.
    // statistical_unit counts are only final after derivation, so invalidate
    // exact count caches here (not just on import completion).
    if (
      type === 'is_deriving_statistical_units' &&
      prevStatus.isDerivingUnits === true &&
      status === false
    ) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("setWorkerStatusAtom: Detected completion of 'isDerivingUnits'. Refreshing base data and invalidating caches.");
      }
      invalidateExactCountsCache();
      set(exactCountCacheGenerationAtom, (n) => n + 1);
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
      set(exactCountCacheGenerationAtom, (n) => n + 1);
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
      // Fetch all statuses and step weights concurrently
      const [importingRes, derivingUnitsRes, derivingReportsRes, weightsRes] = await Promise.all([
        client.rpc('is_importing', undefined, { get: true }),
        client.rpc('is_deriving_statistical_units', undefined, { get: true }),
        client.rpc('is_deriving_reports', undefined, { get: true }),
        client.from('pipeline_step_weight').select('phase,step,weight'),
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

      // Parse JSONB responses — now single objects per phase, not arrays
      const importData = importingRes.data as unknown as ImportStatus | null;
      const unitsData = derivingUnitsRes.data as unknown as PhaseStatus | null;
      const reportsData = derivingReportsRes.data as unknown as PhaseStatus | null;

      // Store step weights (static configuration, only fetched once)
      if (weightsRes.data && !weightsRes.error) {
        set(pipelineStepWeightsAtom, weightsRes.data as PipelineStepWeight[]);
      }

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

/**
 * Hook to get pipeline step weights from the database.
 */
export const usePipelineStepWeights = (): PipelineStepWeight[] => {
  return useAtomValue(pipelineStepWeightsAtom);
};

// ============================================================================
// COMMAND LABEL MAPPING
// ============================================================================

export const COMMAND_LABELS: Record<string, string> = {
  'derive_statistical_unit': 'Refreshing statistical units',
  'derive_statistical_unit_continue': 'Refreshing statistical units',
  'statistical_unit_flush_staging': 'Flushing staging data',
  'derive_power_groups': 'Deriving power groups',
  'derive_reports': 'Computing reports',
  'derive_statistical_history': 'Computing statistical history',
  'derive_statistical_unit_facet': 'Computing search facets',
  'derive_statistical_history_facet': 'Computing history facets',
  'statistical_unit_facet_reduce': 'Merging search facets',
  'statistical_history_facet_reduce': 'Merging history facets',
};
