"use client";

/**
 * ARCHITECTURAL OVERVIEW: Import Job and Time Context Handling
 *
 * This file implements the frontend logic for a simplified and robust import
 * process. The design centers on decoupling the 'what' of an import (the
 * definition) from the 'when' (the time context).
 *
 * ### Why This Is an Improvement
 *
 * The previous system required a unique `import_definition` for every
 * combination of import type (e.g., Legal Units) and time context (e.g.,
 * "Current Year"). This was brittle and difficult to maintain.
 *
 * The new architecture provides several key advantages:
 *
 * 1.  **Decoupling and Flexibility:** There is now only one generic
 *     `import_definition` per import `mode`. This definition describes the data
 *     shape and processing steps. The validity period is specified separately
 *     on a per-job basis via the `import_job.time_context_ident` field. This
 *     is a much cleaner separation of concerns.
 *
 * 2.  **Reduced Configuration:** Adding a new time period (e.g., "Last Quarter")
 *     only requires adding a row to the `time_context` table. It becomes
 *     instantly available for all import types without needing to create
 *     multiple new `import_definition` records in the database. The system is
 *     now truly data-driven.
 *
 * 3.  **Simplified Frontend Logic:** The UI no longer needs complex logic to
 *     filter time contexts based on which definitions exist. It can simply
 *     present all available `input`-scoped time contexts to the user,
 *     eliminating a major source of bugs and complexity. Job creation is
 *     simplified to finding the single definition for the mode and attaching
 *     the chosen `time_context_ident`.
 *
 * ### Potential Future Enhancements
 *
 * This robust new foundation was an excellent architectural refactoring by the
 * other agent. It opens the door for further enhancements, such as:
 *
 * -   **UI-Driven Column Mapping:** Allowing users to visually map columns from
 *     their uploaded CSV to target fields, creating per-job import definitions
 *     dynamically.
 * -   **Validation & Preview Step:** Processing the first N rows of a file to
 *     provide an interactive preview and validation feedback before committing
 *     to a full import.
 */

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
  selectedDefinition: Tables<'import_definition'> | null;
  availableDefinitions: Tables<'import_definition'>[];
  explicitStartDate: string | null; // YYYY-MM-DD
  explicitEndDate: string | null;   // YYYY-MM-DD
}

export const importStateAtom = atom<ImportState>({
  isImporting: false,
  progress: 0,
  currentFile: null,
  errors: [],
  completed: false,
  useExplicitDates: false,
  selectedImportTimeContextIdent: null,
  selectedDefinition: null,
  availableDefinitions: [],
  explicitStartDate: null,
  explicitEndDate: null,
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

export const setImportExplicitStartDateAtom = atom(
  null,
  (get, set, date: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, explicitStartDate: date }));
  }
);

export const setImportExplicitEndDateAtom = atom(
  null,
  (get, set, date: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, explicitEndDate: date }));
  }
);

export const setSelectedImportDefinitionAtom = atom(
  null,
  (get, set, definition: Tables<'import_definition'>) => {
    set(importStateAtom, (prev) => ({ ...prev, selectedDefinition: definition }));
  }
);

export const loadImportDefinitionsAtom = atom(
  null,
  async (get, set, mode: ImportMode) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error(`loadImportDefinitionsAtom: No client available for mode ${mode}`);
      return;
    }

    // Reset previous definitions to avoid showing stale data
    set(importStateAtom, (prev) => ({
      ...prev,
      selectedDefinition: null,
      availableDefinitions: [],
    }));

    try {
      const { data, error } = await client
        .from("import_definition")
        .select("*")
        .eq("mode", mode)
        .eq("custom", false);

      if (error) throw error;
      if (!data || data.length === 0) throw new Error(`Import definition not found for mode: ${mode}.`);
      
      set(importStateAtom, (prev) => ({ ...prev, availableDefinitions: data }));

      // Set a default selected definition. Prefer 'job_provided' if available.
      const defaultSelection = data.find(d => d.valid_time_from === 'job_provided') || data[0];
      if (defaultSelection) {
        set(importStateAtom, (prev) => ({ ...prev, selectedDefinition: defaultSelection }));
      }
      
    } catch (error: any) {
      console.error(`Failed to load import definitions for mode ${mode}:`, error);
      // Ensure definition is null on error
      set(importStateAtom, (prev) => ({ ...prev, selectedDefinition: null, availableDefinitions: [] }));
    }
  }
);

export const createImportJobAtom = atom<null, [], Promise<Tables<'import_job'> | null>>(
  null,
  async (get, set): Promise<Tables<'import_job'> | null> => {
    const client = get(restClientAtom);
    if (!client) {
      console.error("createImportJobAtom: No client available");
      throw new Error("Client not initialized");
    }

    const importState = get(importStateAtom);
    const definition = importState.selectedDefinition;

    if (!definition) {
      console.error("createImportJobAtom: No import definition selected.");
      throw new Error("Import definition not selected.");
    }

    const insertJobData: TablesInsert<'import_job'> = {
      definition_id: definition.id,
      time_context_ident: null,
      default_valid_from: null,
      default_valid_to: null,
      data_table_name: null!,
      expires_at: null!,
      slug: null!,
      upload_table_name: null!,
    };

    if (definition.valid_time_from === 'job_provided') {
      if (importState.useExplicitDates) {
        if (!importState.explicitStartDate || !importState.explicitEndDate) {
          throw new Error("Explicit start and end dates must be provided.");
        }
        insertJobData.default_valid_from = importState.explicitStartDate;
        insertJobData.default_valid_to = importState.explicitEndDate;
      } else {
        if (!importState.selectedImportTimeContextIdent) {
          throw new Error("A time context must be selected.");
        }
        insertJobData.time_context_ident = importState.selectedImportTimeContextIdent;
      }
    }
    // If valid_time_from is 'source_columns', we send no time context info, which is the default.

    const { data, error: insertError } = await client
      .from("import_job")
      .insert(insertJobData)
      .select("*")
      .single();

    if (insertError) {
      console.error(`createImportJobAtom: Error creating import job: ${insertError.message}`);
      throw insertError;
    }

    if (!data) {
      console.error("createImportJobAtom: No data returned after creating import job");
      throw new Error("Import job creation did not return data");
    }

    return data as Tables<'import_job'>;
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
  const doSetExplicitStartDate = useSetAtom(setImportExplicitStartDateAtom);
  const doSetExplicitEndDate = useSetAtom(setImportExplicitEndDateAtom);
  const doLoadDefinitions = useSetAtom(loadImportDefinitionsAtom);
  const doSetSelectedDefinition = useSetAtom(setSelectedImportDefinitionAtom);
  const doCreateJob = useSetAtom(createImportJobAtom);

  const availableImportTimeContexts = useMemo<Tables<'time_context'>[]>(() => {
    if (!allTimeContextsFromBase) return [];

    // Filter time contexts to only those suitable for any import.
    // These have a scope of 'input' or 'input_and_query'.
    return allTimeContextsFromBase.filter(
      (tc) => tc.scope === "input" || tc.scope === "input_and_query"
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

  const setExplicitStartDate = useCallback((date: string | null) => {
    doSetExplicitStartDate(date);
  }, [doSetExplicitStartDate]);

  const setExplicitEndDate = useCallback((date: string | null) => {
    doSetExplicitEndDate(date);
  }, [doSetExplicitEndDate]);

  const loadDefinitions = useCallback(async (mode: ImportMode) => {
    await doLoadDefinitions(mode);
  }, [doLoadDefinitions]);

  const setSelectedDefinition = useCallback((definition: Tables<'import_definition'>) => {
    doSetSelectedDefinition(definition);
  }, [doSetSelectedDefinition]);

  const refreshUnitCount = useCallback(async (unitType: keyof UnitCounts) => {
    await doRefreshUnitCount(unitType);
  }, [doRefreshUnitCount]);

  const refreshAllCounts = useCallback(async () => {
    await doRefreshAllUnitCounts();
  }, [doRefreshAllUnitCounts]);
  
  const createImportJob = useCallback(async (): Promise<Tables<'import_job'> | null> => {
    return await doCreateJob();
  }, [doCreateJob]);

  return {
    counts: currentUnitCounts,
    refreshUnitCount,
    refreshCounts: refreshAllCounts,
    timeContext: importTimeContextData,
    setSelectedTimeContext: setSelectedImportTimeContext,
    setUseExplicitDates: setImportUseExplicitDates,
    setExplicitStartDate,
    setExplicitEndDate,
    loadDefinitions,
    setSelectedDefinition,
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
