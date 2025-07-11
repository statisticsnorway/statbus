"use client";

/**
 * Reports Atoms and Hooks
 *
 * This file contains atoms and hooks related to generating and displaying reports.
 */

import { atom } from 'jotai'

import { workerStatusAtom } from './worker-status'
import { hasStatisticalUnitsAtom } from './base-data'

// ============================================================================
// DERIVED UI STATE ATOMS (for Reports/Analysis)
// ============================================================================

export interface AnalysisPageVisualState {
  state: "checking_status" | "in_progress" | "finished" | "failed";
  message: string | null;
  // Include worker status details for direct use in UI if needed
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
}

export const analysisPageVisualStateAtom = atom<AnalysisPageVisualState>((get) => {
  const workerStatus = get(workerStatusAtom); // Reads the WorkerStatus interface
  const hasStatisticalUnits = get(hasStatisticalUnitsAtom);

  const { isImporting, isDerivingUnits, isDerivingReports, loading, error } = workerStatus;

  if (loading) {
    return { 
      state: "checking_status", 
      message: "Checking status of data analysis...",
      isImporting, isDerivingUnits, isDerivingReports 
    };
  }

  if (error) {
    return { 
      state: "failed", 
      message: `Error checking derivation status: ${error}`,
      isImporting, isDerivingUnits, isDerivingReports
    };
  }

  if (isImporting || isDerivingUnits || isDerivingReports) {
    return { 
      state: "in_progress", 
      message: null,
      isImporting, isDerivingUnits, isDerivingReports
    };
  }

  // At this point, all worker processes are false and there's no error
  if (hasStatisticalUnits) {
    return { 
      state: "finished", 
      message: "All processes completed successfully.",
      isImporting, isDerivingUnits, isDerivingReports
    };
  } else {
    return { 
      state: "failed", 
      message: "Data analysis completed, but no statistical units were found.",
      isImporting, isDerivingUnits, isDerivingReports
    };
  }
});
