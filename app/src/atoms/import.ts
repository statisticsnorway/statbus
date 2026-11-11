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
 *     -   `'job_provided'`: The user must either select a time frame
 *         (public.time_frame) or enter explicit start and end dates when creating
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
import { useMemo, useCallback } from 'react'
import { useGuardedEffect } from '@/hooks/use-guarded-effect'

import type { Database, Enums, Tables, TablesInsert } from '@/lib/database.types'
import { restClientAtom } from './rest-client'
import { useBaseData } from './base-data'
import { selectedTimeFrameAtom } from './app'
import type { TimeFramePanelMode } from '@/components/time-frame-panel'
import { isAuthenticatedStrictAtom, authStateForDataFetchingAtom } from './auth'

// ============================================================================
// TYPES
// ============================================================================

export type ImportMode = Enums<'import_mode'>;

export type ImportStep = {
  code: string;
  analyse_procedure: string | null;
};

export type DefinitionSnapshot = {
  import_step_list: ImportStep[];
  import_source_column_list: Array<{
    column_name: string;
    priority: number;
  }>;
  import_mapping_list: Array<{
    source_column: { column_name: string } | null;
    target_data_column: { column_name: string; purpose: string; column_type?: string };
  }>;
};

export type ImportJobWithDetails = Tables<"import_job"> & {
  import_definition: Pick<Tables<'import_definition'>, 'slug' | 'name' | 'mode' | 'custom'> | null;
  definition_snapshot?: DefinitionSnapshot | null;
};

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
  selectedImportTimeFrameIdent: string | null;
  selectedDefinition: Tables<'import_definition'> | null;
  availableDefinitions: Tables<'import_definition'>[];
  explicitStartDate: string | null; // YYYY-MM-DD
  explicitEndDate: string | null;   // YYYY-MM-DD
  review: boolean | null;
  /** data_source.code for rows without their own source; null keeps the definition's (import_job.default_data_source_code). */
  dataSourceCode: string | null;
  /** Written to every row the job changes, like an edit comment (import_job.edit_comment). */
  editComment: string | null;
}

export const initialImportState: ImportState = {
  isImporting: false,
  progress: 0,
  currentFile: null,
  errors: [],
  completed: false,
  useExplicitDates: false,
  selectedImportTimeFrameIdent: null,
  selectedDefinition: null,
  availableDefinitions: [],
  explicitStartDate: null,
  explicitEndDate: null,
  review: null,
  dataSourceCode: null,
  editComment: null,
};

export const importStateAtom = atom<ImportState>(initialImportState)

/**
 * Simple shows only the Time frame; Advanced offers Frame, Dates or Source
 * dates (components/time-frame-panel.tsx). Kept apart from the import state
 * because the import pages' demo-file table follows it too: Simple offers only
 * the file for a time frame, so users download the matching example.
 */
export const importValidityModeAtom = atom<TimeFramePanelMode>("simple");

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
    const authState = get(authStateForDataFetchingAtom);
    const client = get(restClientAtom);

    if (authState !== 'authenticated') {
      if (authState === 'unauthenticated') {
        set(allPendingJobsByModeStateAtom, (prev) => ({
          ...prev,
          [mode]: { ...(prev[mode] || { jobs: [], error: null, lastFetched: null }), loading: false, error: "Not authenticated" },
        }));
      }
      // If checking or refreshing, we just wait and do nothing. The atom will be re-evaluated
      // by Jotai once the auth state changes to 'authenticated' or 'unauthenticated'.
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
    } catch (error: unknown) {
      console.error(`Failed to refresh pending jobs for mode ${mode}:`, error);
      set(allPendingJobsByModeStateAtom, (prev) => ({
        ...prev,
        [mode]: {
          ...(prev[mode] || { jobs: [], loading: false, lastFetched: null }),
          loading: false,
          error: (error instanceof Error ? error.message : String(error)) || `Failed to fetch pending jobs for ${mode}`,
        },
      }));
    }
  }
);

export const setImportSelectedTimeFrameAtom = atom(
  null,
  (get, set, timeFrameIdent: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, selectedImportTimeFrameIdent: timeFrameIdent }));
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

export const setImportReviewAtom = atom(
  null,
  (get, set, review: boolean | null) => {
    set(importStateAtom, (prev) => ({ ...prev, review }));
  }
);

export const setImportDataSourceCodeAtom = atom(
  null,
  (get, set, dataSourceCode: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, dataSourceCode }));
  }
);

export const setImportEditCommentAtom = atom(
  null,
  (get, set, editComment: string | null) => {
    set(importStateAtom, (prev) => ({ ...prev, editComment }));
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

    // Reset previous definitions and user selections to avoid showing stale data from another import page.
    set(importStateAtom, (prev) => ({
      ...prev,
      selectedDefinition: initialImportState.selectedDefinition,
      availableDefinitions: initialImportState.availableDefinitions,
      useExplicitDates: initialImportState.useExplicitDates,
      selectedImportTimeFrameIdent: initialImportState.selectedImportTimeFrameIdent,
      explicitStartDate: initialImportState.explicitStartDate,
      explicitEndDate: initialImportState.explicitEndDate,
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
      const defaultSelection = data.find((d: Tables<'import_definition'>) => d.valid_time_from === 'job_provided') || data[0];
      if (defaultSelection) {
        set(importStateAtom, (prev) => ({ ...prev, selectedDefinition: defaultSelection }));
      }
      
    } catch (error: unknown) {
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
      description: definition.name,
      time_frame_ident: null,
      default_valid_from: null,
      default_valid_to: null,
      data_table_name: null!,
      expires_at: null!,
      slug: null!,
      upload_table_name: null!,
      review: importState.review,
      default_data_source_code: importState.dataSourceCode,
      edit_comment: importState.editComment || null,
    };

    if (definition.valid_time_from === 'job_provided') {
      if (importState.useExplicitDates) {
        if (!importState.explicitStartDate || !importState.explicitEndDate) {
          throw new Error("Explicit start and end dates must be provided.");
        }
        insertJobData.default_valid_from = importState.explicitStartDate;
        insertJobData.default_valid_to = importState.explicitEndDate;
      } else {
        if (!importState.selectedImportTimeFrameIdent) {
          throw new Error("A time frame must be selected.");
        }
        insertJobData.time_frame_ident = importState.selectedImportTimeFrameIdent;
      }
    }
    // If valid_time_from is 'source_columns', the job carries no time frame and no dates.

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
  const {
    timeFrames,
    refreshBaseData,
  } = useBaseData();
  const selectedViewTimeFrame = useAtomValue(selectedTimeFrameAtom);

  const doRefreshUnitCount = useSetAtom(refreshUnitCountAtom);
  const doRefreshAllUnitCounts = useSetAtom(refreshAllUnitCountsAtom);
  const doSetSelectedTimeFrameIdent = useSetAtom(setImportSelectedTimeFrameAtom);
  const doSetUseExplicitDates = useSetAtom(setImportUseExplicitDatesAtom);
  const doSetExplicitStartDate = useSetAtom(setImportExplicitStartDateAtom);
  const doSetExplicitEndDate = useSetAtom(setImportExplicitEndDateAtom);
  const doLoadDefinitions = useSetAtom(loadImportDefinitionsAtom);
  const doSetSelectedDefinition = useSetAtom(setSelectedImportDefinitionAtom);
  const doSetReview = useSetAtom(setImportReviewAtom);
  const setDataSourceCode = useSetAtom(setImportDataSourceCodeAtom);
  const setEditComment = useSetAtom(setImportEditCommentAtom);
  const doCreateJob = useSetAtom(createImportJobAtom);

  // An import job may name any time frame (lib/time-frame.ts lists them all,
  // grouped). Until the user picks one, the job takes the frame selected in the
  // menu, which is the live frame unless the user is looking at another one.
  useGuardedEffect(() => {
    if (currentImportState.selectedImportTimeFrameIdent === null && timeFrames.length > 0) {
      const viewIdent = selectedViewTimeFrame?.ident;
      const initial = timeFrames.find((tf) => tf.ident === viewIdent) ?? timeFrames[0];
      if (initial.ident) doSetSelectedTimeFrameIdent(initial.ident);
    }
  }, [
    timeFrames,
    currentImportState.selectedImportTimeFrameIdent,
    doSetSelectedTimeFrameIdent,
    selectedViewTimeFrame?.ident,
  ], 'import.ts:useImportManager:selectInitialTimeFrame');

  const selectedImportTimeFrame = useMemo<Tables<'time_frame'> | null>(() => {
    if (!currentImportState.selectedImportTimeFrameIdent) return null;
    return timeFrames.find(tf => tf.ident === currentImportState.selectedImportTimeFrameIdent) || null;
  }, [currentImportState.selectedImportTimeFrameIdent, timeFrames]);

  const importTimeFrameData = useMemo(() => ({
    availableTimeFrames: timeFrames,
    selectedTimeFrame: selectedImportTimeFrame,
  }), [timeFrames, selectedImportTimeFrame]);

  const setSelectedImportTimeFrame = useCallback((timeFrameIdent: string | null) => {
    doSetSelectedTimeFrameIdent(timeFrameIdent);
  }, [doSetSelectedTimeFrameIdent]);

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

  const setReview = useCallback((review: boolean | null) => {
    doSetReview(review);
  }, [doSetReview]);

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
    timeFrame: importTimeFrameData,
    setSelectedTimeFrame: setSelectedImportTimeFrame,
    setUseExplicitDates: setImportUseExplicitDates,
    setExplicitStartDate,
    setExplicitEndDate,
    loadDefinitions,
    setSelectedDefinition,
    setReview,
    setDataSourceCode,
    setEditComment,
    createImportJob,
    importState: currentImportState,
    refreshBaseData,
  };
};

export const loadAllImportDefinitionsAtom = atom(
  null,
  async (get): Promise<Tables<'import_definition'>[]> => {
    const client = get(restClientAtom);
    if (!client) throw new Error("Client not initialized");
    const { data, error } = await client
      .from("import_definition").select("*")
      .eq("enabled", true).eq("valid", true)
      .order("mode").order("name");
    if (error) throw error;
    return data ?? [];
  }
);

export const createImportJobFromDefinitionAtom = atom(
  null,
  async (get, _set, params: {
    definitionId: number;
    description: string;
    timeFrameIdent: string | null;
    defaultValidFrom: string | null;
    defaultValidTo: string | null;
    review: boolean | null;
  }): Promise<Tables<'import_job'>> => {
    const client = get(restClientAtom);
    if (!client) throw new Error("Client not initialized");
    const { data, error } = await client.from("import_job")
      .insert({
        definition_id: params.definitionId,
        description: params.description,
        time_frame_ident: params.timeFrameIdent,
        default_valid_from: params.defaultValidFrom,
        default_valid_to: params.defaultValidTo,
        review: params.review,
        // These NOT NULL columns are populated by the BEFORE INSERT trigger (import_job_derive)
        data_table_name: null!, slug: null!, upload_table_name: null!, expires_at: null!,
      }).select("*").single();
    if (error) throw error;
    if (!data) throw new Error("No data returned");
    return data;
  }
);

export const usePendingJobsByMode = (mode: ImportMode) => {
  const allJobsState = useAtomValue(allPendingJobsByModeStateAtom);
  const refreshJobsForMode = useSetAtom(refreshPendingJobsByModeAtom);
  const isAuthenticated = useAtomValue(isAuthenticatedStrictAtom);

  const state: PendingJobsData = useMemo(() => {
    return allJobsState[mode] || { jobs: [], loading: false, error: null, lastFetched: null };
  }, [allJobsState, mode]);

  const refreshJobs = useCallback(() => {
    refreshJobsForMode(mode);
  }, [refreshJobsForMode, mode]);

  useGuardedEffect(() => {
    if (isAuthenticated && state.jobs.length === 0 && !state.loading && state.lastFetched === null) {
      refreshJobs();
    }
  }, [isAuthenticated, state.jobs.length, state.loading, state.lastFetched, refreshJobs, mode], 'import.ts:usePendingJobsByMode:initialFetch');

  return {
    ...state,
    refreshJobs,
  };
};
