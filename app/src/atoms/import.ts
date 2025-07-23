"use client";

/**
 * Data Import Atoms and Hooks
 *
 * This file contains atoms and hooks related to the data import process,
 * including tracking import state, unit counts, and pending jobs.
 */

import { atom, useAtomValue, useSetAtom } from 'jotai'
import { useMemo, useCallback, useEffect } from 'react'

import type { Database, Enums, Tables, TablesInsert } from '@/lib/database.types'
import { restClientAtom } from './app'
import { timeContextsAtom, defaultTimeContextAtom } from './base-data'
import { isAuthenticatedAtom } from './auth'

// ============================================================================
// TYPES
// ============================================================================

export type ImportMode = Enums<'import_mode'>;

// ============================================================================
// IMPORT UNITS ATOMS - Replace ImportUnitsContext
// ============================================================================

export interface ImportState {
  isImporting: boolean
  progress: number
  currentFile: string | null
  errors: string[]
  completed: boolean
  useExplicitDates: boolean;
  selectedImportTimeContextIdent: string | null;
}

export const importStateAtom = atom<ImportState>({
  isImporting: false,
  progress: 0,
  currentFile: null,
  errors: [],
  completed: false,
  useExplicitDates: false,
  selectedImportTimeContextIdent: null,
})

// ============================================================================
// UNIT COUNTS ATOMS (for Import feature)
// ============================================================================

export interface UnitCounts {
  legalUnits: number | null;
  establishmentsWithLegalUnit: number | null;
  establishmentsWithoutLegalUnit: number | null;
}

export const unitCountsAtom = atom<UnitCounts>({
  legalUnits: null,
  establishmentsWithLegalUnit: null,
  establishmentsWithoutLegalUnit: null,
});

// Pending Import Jobs (Generalized)
export type ImportJobWithDefinition = Tables<'import_job'> & {
  import_definition: Tables<'import_definition'>;
};

export interface PendingJobsData {
  jobs: ImportJobWithDefinition[];
  loading: boolean;
  error: string | null;
  lastFetched: number | null;
}

export interface AllPendingJobsState {
  [mode: string]: PendingJobsData | undefined;
}

// Atom to store all pending jobs, keyed by their import_mode
export const allPendingJobsByModeStateAtom = atom<AllPendingJobsState>({});

// ============================================================================
// ASYNC ACTION ATOMS (Import)
// ============================================================================

export const refreshUnitCountAtom = atom(
  null,
  async (get, set, unitType: keyof UnitCounts) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error(`refreshUnitCountAtom: No client for ${unitType}`);
      return;
    }
    try {
      let query;
      switch (unitType) {
        case 'legalUnits':
          query = client.from("legal_unit").select("*", { count: "exact", head: true });
          break;
        case 'establishmentsWithLegalUnit':
          query = client.from("establishment").select("*", { count: "exact", head: true })
            .not("legal_unit_id", "is", null);
          break;
        case 'establishmentsWithoutLegalUnit':
          query = client.from("establishment").select("*", { count: "exact", head: true })
            .is("legal_unit_id", null);
          break;
        default:
          console.error(`refreshUnitCountAtom: Unknown unitType ${unitType}`);
          return;
      }
      const { count, error } = await query;
      if (error) throw error;
      set(unitCountsAtom, (prev) => ({ ...prev, [unitType]: count }));
    } catch (error) {
      console.error(`Failed to refresh ${unitType}:`, error);
    }
  }
);

export const refreshAllUnitCountsAtom = atom(
  null,
  async (get, set) => {
    await set(refreshUnitCountAtom, 'legalUnits');
    await set(refreshUnitCountAtom, 'establishmentsWithLegalUnit');
    await set(refreshUnitCountAtom, 'establishmentsWithoutLegalUnit');
  }
);

export const refreshPendingJobsByModeAtom = atom(
  null,
  async (get, set, mode: ImportMode) => {
    const isAuthenticated = get(isAuthenticatedAtom);
    const client = get(restClientAtom);

    if (!isAuthenticated) {
      set(allPendingJobsByModeStateAtom, (prev) => ({
        ...prev,
        [mode]: { ...(prev[mode] || { jobs: [], error: null, lastFetched: null }), loading: false, error: "Not authenticated" },
      }));
      return;
    }

    if (!client) {
      console.error(`refreshPendingJobsByModeAtom (${mode}): No client available.`);
      set(allPendingJobsByModeStateAtom, (prev) => ({
        ...prev,
        [mode]: { ...(prev[mode] || { jobs: [], error: null, lastFetched: null }), loading: false, error: "Client not available" },
      }));
      return;
    }

    set(allPendingJobsByModeStateAtom, (prev) => ({
      ...prev,
      [mode]: { ...(prev[mode] || { jobs: [], error: null, lastFetched: null }), loading: true, error: null },
    }));

    try {
      const { data, error } = await client
        .from("import_job")
        .select("*, import_definition!inner(*)")
        .eq("state", "waiting_for_upload")
        .eq("import_definition.mode", mode)
        .order("created_at", { ascending: false });

      if (error) throw error;

      set(allPendingJobsByModeStateAtom, (prev) => ({
        ...prev,
        [mode]: {
          jobs: data || [],
          loading: false,
          error: null,
          lastFetched: Date.now(),
        },
      }));
    } catch (error: any) {
      console.error(`Failed to refresh pending jobs for mode ${mode}:`, error);
      set(allPendingJobsByModeStateAtom, (prev) => ({
        ...prev,
        [mode]: {
          ...(prev[mode] || { jobs: [], loading: false, lastFetched: null }),
          loading: false,
          error: error.message || `Failed to fetch pending jobs for ${mode}`,
        },
      }));
    }
  }
);

export const setImportSelectedTimeContextAtom = atom(
  null,
  (get, set, timeContextIdent: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, selectedImportTimeContextIdent: timeContextIdent }));
  }
);

export const setImportUseExplicitDatesAtom = atom(
  null,
  (get, set, useExplicitDates: boolean) => {
    set(importStateAtom, (prev) => ({ ...prev, useExplicitDates }));
  }
);

export const createImportJobAtom = atom<null, [ImportMode], Promise<Tables<'import_job'> | null>>(
  null,
  async (get, set, mode: ImportMode): Promise<Tables<'import_job'> | null> => {
    const client = get(restClientAtom);
    if (!client) {
      console.error("createImportJobAtom: No client available");
      throw new Error("Client not initialized");
    }

    const importState = get(importStateAtom);
    const allTimeContexts = get(timeContextsAtom);

    let selectedFullTimeContext: Tables<'time_context'> | null = null;
    if (importState.selectedImportTimeContextIdent) {
      selectedFullTimeContext = allTimeContexts.find(tc => tc.ident === importState.selectedImportTimeContextIdent) || null;
    }

    if (!selectedFullTimeContext && !importState.useExplicitDates) {
      console.error("createImportJobAtom: Either a selected time context (via ident) must be found or useExplicitDates must be true.");
      throw new Error("Time context for import not properly specified.");
    }

    // Find the import definition that matches the mode and has no time context ident.
    // This ensures we use the `..._explicit_dates` definition, which allows either
    // user-selected time context or explicit dates from the CSV to be used.
    const { data: definitionData, error: definitionError } = await client
      .from("import_definition")
      .select("id, name, time_context_ident")
      .eq("mode", mode)
      .eq("custom", false)
      .is("time_context_ident", null)
      .maybeSingle();

    if (definitionError) {
      console.error(`createImportJobAtom: Error fetching import definition for mode ${mode}: ${definitionError.message}`);
      throw definitionError;
    }
    if (!definitionData) {
      console.error(`createImportJobAtom: Import definition not found for mode: ${mode} with no time context.`);
      throw new Error(`Import definition not found for mode: ${mode}`);
    }

    const insertJobData: TablesInsert<'import_job'> = {
        description: definitionData.name,
        definition_id: definitionData.id,
        data_table_name: null!,
        expires_at: null!,
        slug: null!,
        upload_table_name: null!
    };

    if (!definitionData.time_context_ident && !importState.useExplicitDates && selectedFullTimeContext) {
      insertJobData.default_valid_from = selectedFullTimeContext.valid_from;
      insertJobData.default_valid_to = selectedFullTimeContext.valid_to;
    }

    const { data, error: insertError } = await client
      .from("import_job")
      .insert(insertJobData)
      .select("*")
      .limit(1);

    if (insertError) {
      console.error(`createImportJobAtom: Error creating import job: ${insertError.message}`);
      throw insertError;
    }

    if (!data || data.length === 0) {
      console.error("createImportJobAtom: No data returned after creating import job");
      throw new Error("Import job creation did not return data");
    }

    return data[0] as Tables<'import_job'>;
  }
);

// ============================================================================
// IMPORT HOOKS
// ============================================================================

export const useImportManager = () => {
  const currentImportState = useAtomValue(importStateAtom);
  const currentUnitCounts = useAtomValue(unitCountsAtom);
  const allTimeContextsFromBase = useAtomValue(timeContextsAtom);
  const defaultTimeContextFromBase = useAtomValue(defaultTimeContextAtom);

  const doRefreshUnitCount = useSetAtom(refreshUnitCountAtom);
  const doRefreshAllUnitCounts = useSetAtom(refreshAllUnitCountsAtom);
  const doSetSelectedTimeContextIdent = useSetAtom(setImportSelectedTimeContextAtom);
  const doSetUseExplicitDates = useSetAtom(setImportUseExplicitDatesAtom);
  const doCreateJob = useSetAtom(createImportJobAtom);

  const availableImportTimeContexts = useMemo<Tables<'time_context'>[]>(() => {
    if (!allTimeContextsFromBase) return []; 
    return allTimeContextsFromBase.filter(
      tc => tc.scope === "input" || tc.scope === "input_and_query"
    );
  }, [allTimeContextsFromBase]);

  useEffect(() => {
    if (currentImportState.selectedImportTimeContextIdent === null && availableImportTimeContexts.length > 0) {
      let newDefaultIdent: string | null = null;

      if (defaultTimeContextFromBase) {
        const globalDefaultIsAvailableForImport = availableImportTimeContexts.find(
          (tc) => tc.ident === defaultTimeContextFromBase.ident
        );
        if (globalDefaultIsAvailableForImport) {
          newDefaultIdent = globalDefaultIsAvailableForImport.ident;
        }
      }

      if (!newDefaultIdent && availableImportTimeContexts.length > 0) {
        newDefaultIdent = availableImportTimeContexts[0].ident;
      }
      
      if (newDefaultIdent) {
        doSetSelectedTimeContextIdent(newDefaultIdent);
      }
    }
  }, [
    availableImportTimeContexts, 
    currentImportState.selectedImportTimeContextIdent, 
    doSetSelectedTimeContextIdent,
    defaultTimeContextFromBase
  ]);

  const selectedImportTimeContextObject = useMemo<Tables<'time_context'> | null>(() => {
    if (!currentImportState.selectedImportTimeContextIdent || !availableImportTimeContexts) return null;
    return availableImportTimeContexts.find(tc => tc.ident === currentImportState.selectedImportTimeContextIdent) || null;
  }, [currentImportState.selectedImportTimeContextIdent, availableImportTimeContexts]);

  const importTimeContextData = useMemo(() => ({
    availableContexts: availableImportTimeContexts,
    selectedContext: selectedImportTimeContextObject,
    useExplicitDates: currentImportState.useExplicitDates,
  }), [availableImportTimeContexts, selectedImportTimeContextObject, currentImportState.useExplicitDates]);

  const setSelectedImportTimeContext = useCallback((timeContextIdent: string | null) => {
    doSetSelectedTimeContextIdent(timeContextIdent);
  }, [doSetSelectedTimeContextIdent]);

  const setImportUseExplicitDates = useCallback((useExplicitDates: boolean) => {
    doSetUseExplicitDates(useExplicitDates);
  }, [doSetUseExplicitDates]);

  const refreshUnitCount = useCallback(async (unitType: keyof UnitCounts) => {
    await doRefreshUnitCount(unitType);
  }, [doRefreshUnitCount]);

  const refreshAllCounts = useCallback(async () => {
    await doRefreshAllUnitCounts();
  }, [doRefreshAllUnitCounts]);
  
  const createImportJob = useCallback(async (mode: ImportMode): Promise<Tables<'import_job'> | null> => {
    return await doCreateJob(mode);
  }, [doCreateJob]);

  return {
    counts: currentUnitCounts,
    refreshUnitCount,
    refreshCounts: refreshAllCounts,
    timeContext: importTimeContextData,
    setSelectedTimeContext: setSelectedImportTimeContext,
    setUseExplicitDates: setImportUseExplicitDates,
    createImportJob,
    importState: currentImportState,
  };
};

export const usePendingJobsByMode = (mode: ImportMode) => {
  const allJobsState = useAtomValue(allPendingJobsByModeStateAtom);
  const refreshJobsForMode = useSetAtom(refreshPendingJobsByModeAtom);
  const isAuthenticated = useAtomValue(isAuthenticatedAtom);

  const state: PendingJobsData = useMemo(() => {
    return allJobsState[mode] || { jobs: [], loading: false, error: null, lastFetched: null };
  }, [allJobsState, mode]);

  const refreshJobs = useCallback(() => {
    refreshJobsForMode(mode);
  }, [refreshJobsForMode, mode]);

  useEffect(() => {
    if (isAuthenticated && state.jobs.length === 0 && !state.loading && state.lastFetched === null) {
      refreshJobs();
    }
  }, [isAuthenticated, state.jobs.length, state.loading, state.lastFetched, refreshJobs, mode]);

  return {
    ...state,
    refreshJobs,
  };
};
