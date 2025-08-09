"use client";

/**
 * ARCHITECTURAL OVERVIEW: Import Job and Time Context Handling
 *
 * This file implements the frontend logic for the data import process. The
 * design is centered on providing a flexible, user-driven experience for
 * creating import jobs based on predefined templates (`import_definition`).
 *
 * ### Core Concepts
 *
 * 1.  **Multiple Definitions per Mode:** The system supports multiple
 *     `import_definition` records for a single import `mode` (e.g.,
 *     'legal_unit', 'establishment_informal'). This allows a single type of
 *     import, like "Import Establishments," to be configured in different ways.
 *
 * 2.  **Declarative Validity Handling:** The key differentiator between
 *     definitions of the same mode is the `valid_time_from` column. This ENUM
 *     declaratively tells the UI how the validity period for imported records
 *     will be determined:
 *
 *     -   `'job_provided'`: The user must either select a predefined time period
 *         (a `time_context`) or enter explicit start and end dates when creating
 *         the import job.
 *
 *     -   `'source_columns'`: The import file itself must contain `valid_from`
 *         and `valid_to` columns. The UI does not prompt for date information.
 *
 * 3.  **Dynamic UI:** The frontend fetches all available definitions for the
 *     chosen import `mode`. It then presents these to the user as a set of
 *     choices (e.g., "Import with dates from file" vs. "Import using a time
 *     period"). Based on the user's selection, the UI dynamically displays the
 *     appropriate controls (e.g., a time context dropdown, date pickers, or
 *     nothing at all).
 *
 * 4.  **State Management:** Jotai atoms manage the list of available
 *     definitions for the current mode, the user's selected definition, and any
 *     additional parameters like explicit dates. This ensures a clean data flow
 *     from user selection to the final API call that creates the `import_job`.
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

export const initialImportState: ImportState = {
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
};

export const importStateAtom = atom<ImportState>(initialImportState)

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
