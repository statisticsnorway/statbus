/**
 * Core Jotai Atoms - Replacing Context Providers
 * 
 * This file contains the main atoms that replace the complex Context + useEffect patterns.
 * Atoms are globally accessible and only trigger re-renders for components that use them.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable } from 'jotai/utils'
import type { Database, Tables, TablesInsert } from '@/lib/database.types' // Added TablesInsert
import type { PostgrestClient } from '@supabase/postgrest-js'
import type { TableColumn, AdaptableTableColumn, ColumnProfile } from '../app/search/search.d'; // Added for new table column types

// ============================================================================
// AUTH ATOMS - Replace AuthStore + AuthContext
// ============================================================================

export interface User {
  uid: number
  sub: string
  email: string
  role: string
  statbus_role: string
  last_sign_in_at: string
  created_at: string
}

export interface AuthStatus {
  isAuthenticated: boolean
  tokenExpiring: boolean
  user: User | null
}

// Base auth atom - starts unauthenticated
export const authStatusAtom = atom<AuthStatus>({
  isAuthenticated: false,
  tokenExpiring: false,
  user: null,
})

// Derived atoms for easier access
export const isAuthenticatedAtom = atom((get) => get(authStatusAtom).isAuthenticated)
export const currentUserAtom = atom((get) => get(authStatusAtom).user)
export const tokenExpiringAtom = atom((get) => get(authStatusAtom).tokenExpiring)

// ============================================================================
// BASE DATA ATOMS - Replace BaseDataStore + BaseDataContext
// ============================================================================

export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[]
  externalIdentTypes: Tables<"external_ident_type_active">[]
  statbusUsers: Tables<"user">[]
  timeContexts: Tables<"time_context">[]
  defaultTimeContext: Tables<"time_context"> | null
  hasStatisticalUnits: boolean
}

// Base data atom
export const baseDataAtom = atom<BaseData>({
  statDefinitions: [],
  externalIdentTypes: [],
  statbusUsers: [],
  timeContexts: [],
  defaultTimeContext: null,
  hasStatisticalUnits: false,
})

// Derived atoms for individual data pieces
export const statDefinitionsAtom = atom((get) => get(baseDataAtom).statDefinitions)
export const externalIdentTypesAtom = atom((get) => get(baseDataAtom).externalIdentTypes)
export const statbusUsersAtom = atom((get) => get(baseDataAtom).statbusUsers)
export const timeContextsAtom = atom((get) => get(baseDataAtom).timeContexts)
export const defaultTimeContextAtom = atom((get) => get(baseDataAtom).defaultTimeContext)
export const hasStatisticalUnitsAtom = atom((get) => get(baseDataAtom).hasStatisticalUnits)

// ============================================================================
// WORKER STATUS ATOMS - Replace BaseDataStore worker status
// ============================================================================

export interface WorkerStatus {
  isImporting: boolean | null
  isDerivingUnits: boolean | null
  isDerivingReports: boolean | null
  loading: boolean
  error: string | null
}

export const workerStatusAtom = atom<WorkerStatus>({
  isImporting: null,
  isDerivingUnits: null,
  isDerivingReports: null,
  loading: false,
  error: null,
})

// ============================================================================
// REST CLIENT ATOM - Replace RestClientStore
// ============================================================================

export const restClientAtom = atom<PostgrestClient<Database> | null>(null)

// ============================================================================
// TIME CONTEXT ATOMS - Replace TimeContext
// ============================================================================

// Persistent selected time context
export const selectedTimeContextAtom = atomWithStorage<Tables<"time_context"> | null>(
  'selectedTimeContext',
  null
)

// ============================================================================
// SEARCH ATOMS - Replace SearchContext
// ============================================================================

// Define initial values for the search state
export const initialSearchStateValues: SearchState = {
  query: '',
  filters: {},
  pagination: { page: 1, pageSize: 25 },
  sorting: { field: 'name', direction: 'asc' },
};

export type SearchDirection = 'asc' | 'desc' | 'desc.nullslast'

export interface SearchState {
  query: string
  filters: Record<string, any>
  pagination: {
    page: number
    pageSize: number
  }
  sorting: {
    field: string
    direction: SearchDirection
  }
}

export const searchStateAtom = atom<SearchState>(initialSearchStateValues);

export interface SearchResult {
  data: any[]
  total: number
  loading: boolean
  error: string | null
}

export const searchResultAtom = atom<SearchResult>({
  data: [],
  total: 0,
  loading: false,
  error: null,
})

// Data typically fetched once for the search page (e.g., dropdown options)
export interface SearchPageData {
  allRegions: Tables<"region_used">[];
  allActivityCategories: Tables<"activity_category_used">[];
  allStatuses: Tables<"status">[];
  allUnitSizes: Tables<"unit_size">[];
  allDataSources: Tables<"data_source">[];
}

export const searchPageDataAtom = atom<SearchPageData>({
  allRegions: [],
  allActivityCategories: [],
  allStatuses: [],
  allUnitSizes: [],
  allDataSources: [],
});

// Action atom to set the search page data
export const setSearchPageDataAtom = atom(
  null,
  (get, set, data: SearchPageData) => {
    set(searchPageDataAtom, data);
  }
);

// ============================================================================
// SELECTION ATOMS - Replace SelectionContext
// ============================================================================

/*
// Example stats_summary value from "test/expected/004_jsonb_stats_to_summary.out"
{
    "arr": {
        "type": "array",
        "counts": {
            "1": 1,
            "2": 1,
            "3": 2,
            "4": 2,
            "5": 3
        }
    },
    "num": {
        "max": 400,
        "min": 0,
        "sum": 1000,
        "mean": 200.00,
        "type": "number",
        "count": 5,
        "stddev": 158.11,
        "variance": 25000.00,
        "sum_sq_diff": 100000.00,
        "coefficient_of_variation_pct": 79.06
    },
    "str": {
        "type": "string",
        "counts": {
            "a": 1,
            "b": 2,
            "c": 2
        }
    },
    "bool": {
        "type": "boolean",
        "counts": {
            "true": 3,
            "false": 2
        }
    }
}
*/

interface ExternalIdents {
  [key: string]: string;
}

// Define the structure for metrics within stats_summary
interface BaseStatMetric {
  type: "array" | "number" | "string" | "boolean";
}

export interface NumberStatMetric extends BaseStatMetric {
  type: "number";
  max?: number;
  min?: number;
  sum?: number; // If present, this is always a number
  mean?: number;
  count?: number;
  stddev?: number;
  variance?: number;
  sum_sq_diff?: number;
  coefficient_of_variation_pct?: number;
}

export interface CountsStatMetric extends BaseStatMetric {
  type: "array" | "string" | "boolean";
  counts: { [key: string]: number };
}

export type StatMetric = NumberStatMetric | CountsStatMetric;

// Refined StatsSummary: Each key is a stat_code, value is its metric object or undefined
interface StatsSummary {
  [statCode: string]: StatMetric | undefined;
}

export type StatisticalUnit = Omit<Tables<"statistical_unit">, 'external_idents' | 'stats_summary'> & {
  external_idents: ExternalIdents;
  stats_summary: StatsSummary;
};

export const selectedUnitsAtom = atom<StatisticalUnit[]>([])

// Derived atoms for selection operations
// Returns a Set of composite IDs for efficient lookup (e.g., "enterprise:123")
export const selectedUnitIdsAtom = atom((get) =>
  new Set(get(selectedUnitsAtom).map(unit => `${unit.unit_type}:${unit.unit_id}`))
)

export const selectionCountAtom = atom((get) => get(selectedUnitsAtom).length)

// ============================================================================
// TABLE COLUMNS ATOMS - Replace TableColumnsContext
// ============================================================================

// ColumnConfig interface removed as it's replaced by TableColumn from search.d.ts

export const tableColumnsAtom = atomWithStorage<TableColumn[]>(
  'search-columns-state', // Matches COLUMN_LOCALSTORAGE_NAME from original provider
  [] // Initialized as empty; will be populated by an initializer atom/effect
)

// ============================================================================
// GETTING STARTED ATOMS - Replace GettingStartedContext
// ============================================================================

// UI State for the Getting Started Wizard
export interface GettingStartedUIState {
  currentStep: number
  completedSteps: number[]
  isVisible: boolean
}

export const gettingStartedUIStateAtom = atomWithStorage<GettingStartedUIState>(
  'gettingStarted',
  {
    currentStep: 0,
    completedSteps: [],
    isVisible: true,
  }
)

// Data State fetched for Getting Started steps
export interface GettingStartedDataState {
  activity_category_standard: { id: number, name: string } | null;
  numberOfRegions: number | null;
  numberOfCustomActivityCategoryCodes: number | null;
  numberOfCustomSectors: number | null;
  numberOfCustomLegalForms: number | null;
}

export const gettingStartedDataAtom = atom<GettingStartedDataState>({
  activity_category_standard: null,
  numberOfRegions: null,
  numberOfCustomActivityCategoryCodes: null,
  numberOfCustomSectors: null,
  numberOfCustomLegalForms: null,
});

// ============================================================================
// IMPORT UNITS ATOMS - Replace ImportUnitsContext
// ============================================================================

export interface ImportState {
  isImporting: boolean
  progress: number
  currentFile: string | null
  errors: string[]
  completed: boolean
  useExplicitDates: boolean; // Added
  selectedImportTimeContextIdent: string | null; // Added
}

export const importStateAtom = atom<ImportState>({
  isImporting: false,
  progress: 0,
  currentFile: null,
  errors: [],
  completed: false,
  useExplicitDates: false, // Added default
  selectedImportTimeContextIdent: null, // Added default
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
export interface PendingJobsData { // Renamed for clarity
  jobs: Tables<'import_job'>[];
  loading: boolean;
  error: string | null;
  lastFetched: number | null;
}

export interface AllPendingJobsState {
  [slugPattern: string]: PendingJobsData | undefined; // Store data per slug pattern
}

// Atom to store all pending jobs, keyed by their definition slug pattern
export const allPendingJobsStateAtom = atom<AllPendingJobsState>({});

// ============================================================================
// APP INITIALIZATION STATE ATOMS
// ============================================================================

// Atom to track if the initial auth status check has been performed
export const authStatusInitiallyCheckedAtom = atom(false);

// Atom to track if search state has been initialized from URL params
export const searchStateInitializedAtom = atom(false);

// ============================================================================
// ASYNC ACTION ATOMS - For handling side effects
// ============================================================================

// Import Units Actions
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
    const currentUnitCounts = get(unitCountsAtom);
    // Example check: if counts are already populated, maybe don't refetch all.
    // if (currentUnitCounts.legalUnits !== null && currentUnitCounts.establishmentsWithLegalUnit !== null) {
    //   // console.log("refreshAllUnitCountsAtom: Unit counts seem to be present, consider if refetch is needed.");
    //   // return; // Or proceed to refresh
    // }
    await set(refreshUnitCountAtom, 'legalUnits');
    await set(refreshUnitCountAtom, 'establishmentsWithLegalUnit');
    await set(refreshUnitCountAtom, 'establishmentsWithoutLegalUnit');
  }
);

// Action atom to fetch pending import jobs by slug pattern
export const refreshPendingJobsByPatternAtom = atom(
  null,
  async (get, set, slugPattern: string) => {
    const isAuthenticated = get(isAuthenticatedAtom);
    const client = get(restClientAtom);

    if (!isAuthenticated) {
      // console.log(`refreshPendingJobsByPatternAtom (${slugPattern}): User not authenticated. Skipping fetch.`);
      set(allPendingJobsStateAtom, (prev) => ({
        ...prev,
        [slugPattern]: { ...(prev[slugPattern] || { jobs: [], error: null, lastFetched: null }), loading: false, error: "Not authenticated" },
      }));
      return;
    }

    if (!client) {
      console.error(`refreshPendingJobsByPatternAtom (${slugPattern}): No client available.`);
      set(allPendingJobsStateAtom, (prev) => ({
        ...prev,
        [slugPattern]: { ...(prev[slugPattern] || { jobs: [], error: null, lastFetched: null }), loading: false, error: "Client not available" },
      }));
      return;
    }

    // Set loading state for the specific slugPattern
    set(allPendingJobsStateAtom, (prev) => ({
      ...prev,
      [slugPattern]: { ...(prev[slugPattern] || { jobs: [], error: null, lastFetched: null }), loading: true, error: null },
    }));

    try {
      const { data, error } = await client
        .from("import_job")
        .select("*, import_definition!inner(*)")
        .eq("state", "waiting_for_upload")
        .like("import_definition.slug", slugPattern) // Use the provided pattern
        .order("created_at", { ascending: false });

      if (error) throw error;

      // Update state for the specific slugPattern
      set(allPendingJobsStateAtom, (prev) => ({
        ...prev,
        [slugPattern]: {
          jobs: data || [],
          loading: false,
          error: null,
          lastFetched: Date.now(),
        },
      }));
    } catch (error: any) {
      console.error(`Failed to refresh pending jobs for pattern ${slugPattern}:`, error);
      set(allPendingJobsStateAtom, (prev) => ({
        ...prev,
        [slugPattern]: {
          ...(prev[slugPattern] || { jobs: [], loading: false, lastFetched: null }),
          loading: false,
          error: error.message || `Failed to fetch pending jobs for ${slugPattern}`,
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

export const createImportJobAtom = atom<null, [string], Promise<Tables<'import_job'> | null>>(
  null,
  async (get, set, definitionSlug: string): Promise<Tables<'import_job'> | null> => {
    const client = get(restClientAtom);
    if (!client) {
      console.error("createImportJobAtom: No client available");
      throw new Error("Client not initialized");
    }

    const importState = get(importStateAtom);
    const allTimeContexts = get(timeContextsAtom); // From baseDataAtom, these are Tables<'time_context'>[]

    let selectedFullTimeContext: Tables<'time_context'> | null = null;
    if (importState.selectedImportTimeContextIdent) {
      selectedFullTimeContext = allTimeContexts.find(tc => tc.ident === importState.selectedImportTimeContextIdent) || null;
    }

    if (!selectedFullTimeContext && !importState.useExplicitDates) {
      console.error("createImportJobAtom: Either a selected time context (via ident) must be found or useExplicitDates must be true.");
      throw new Error("Time context for import not properly specified.");
    }

    // Get definition ID and time_context_ident
    const { data: definitionData, error: definitionError } = await client
      .from("import_definition")
      .select("id, time_context_ident") // Also fetch time_context_ident
      .eq("slug", definitionSlug)
      .maybeSingle();

    if (definitionError) {
      console.error(`createImportJobAtom: Error fetching import definition: ${definitionError.message}`);
      throw definitionError;
    }
    if (!definitionData) {
      console.error(`createImportJobAtom: Import definition not found for slug: ${definitionSlug}`);
      throw new Error(`Import definition not found for slug: ${definitionSlug}`);
    }

    const insertJobData: TablesInsert<'import_job'> = {
        description: `Import job for ${definitionSlug}`,
        definition_id: definitionData.id,
        // id and created_at will be auto-generated by DB
        // The following will be auto generated by a before trigger, but are NOT NULL in the database.
        data_table_name: null!,
        expires_at: null!,
        slug: null!,
        upload_table_name: null!
    };

    // Only set default_valid_from/to if the definition doesn't have its own time_context_ident,
    // and explicit dates are not being used, and a time context is selected.
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

// Getting Started Data Actions
export const refreshActivityCategoryStandardAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error('GettingStarted: No client for activity_category_standard');
      // Optionally throw or handle error state
      return;
    }
    try {
      const { data: settings, error } = await client
        .from("settings")
        .select("activity_category_standard(id,name)")
        .limit(1);
      if (error) throw error;
      const activity_category_standard = settings?.[0]?.activity_category_standard as { id: number, name: string } ?? null;
      set(gettingStartedDataAtom, (prev) => ({
        ...prev,
        activity_category_standard,
      }));
    } catch (error) {
      console.error('Failed to refresh activity_category_standard:', error);
    }
  }
);

export const refreshNumberOfRegionsAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error('GettingStarted: No client for numberOfRegions');
      return;
    }
    try {
      const { count, error } = await client.from("region").select("*", { count: "exact", head: true });
      if (error) throw error;
      set(gettingStartedDataAtom, (prev) => ({
        ...prev,
        numberOfRegions: count,
      }));
    } catch (error) {
      console.error('Failed to refresh numberOfRegions:', error);
    }
  }
);

export const refreshNumberOfCustomActivityCategoryCodesAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error('GettingStarted: No client for numberOfCustomActivityCategoryCodes');
      return;
    }
    try {
      const { count, error } = await client.from("activity_category_available_custom").select("*", { count: "exact", head: true });
      if (error) throw error;
      set(gettingStartedDataAtom, (prev) => ({
        ...prev,
        numberOfCustomActivityCategoryCodes: count,
      }));
    } catch (error) {
      console.error('Failed to refresh numberOfCustomActivityCategoryCodes:', error);
    }
  }
);

export const refreshNumberOfCustomSectorsAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error('GettingStarted: No client for numberOfCustomSectors');
      return;
    }
    try {
      const { count, error } = await client.from("sector_custom").select("*", { count: "exact", head: true });
      if (error) throw error;
      set(gettingStartedDataAtom, (prev) => ({
        ...prev,
        numberOfCustomSectors: count,
      }));
    } catch (error) {
      console.error('Failed to refresh numberOfCustomSectors:', error);
    }
  }
);

export const refreshNumberOfCustomLegalFormsAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error('GettingStarted: No client for numberOfCustomLegalForms');
      return;
    }
    try {
      const { count, error } = await client.from("legal_form_custom").select("*", { count: "exact", head: true });
      if (error) throw error;
      set(gettingStartedDataAtom, (prev) => ({
        ...prev,
        numberOfCustomLegalForms: count,
      }));
    } catch (error) {
      console.error('Failed to refresh numberOfCustomLegalForms:', error);
    }
  }
);

export const refreshAllGettingStartedDataAtom = atom(
  null,
  async (get, set) => {
    const currentGettingStartedData = get(gettingStartedDataAtom);
    // Example check: if a key piece of this data is already present, maybe don't refetch all.
    // This depends on whether this data is expected to change during a session or only on initial load.
    // For now, let's assume it's okay to refetch if called, but individual atoms could be smarter.
    // Alternatively, add a more specific check like:
    // if (currentGettingStartedData.numberOfRegions !== null && currentGettingStartedData.activity_category_standard !== null) {
    //   console.log("refreshAllGettingStartedDataAtom: Data seems to be present, consider if refetch is needed.");
    //   // return; // Or proceed to refresh if that's desired behavior
    // }

    // Trigger all individual refresh actions
    // The `set` function in a write-only atom can accept another atom (or a value).
    // If it's an action atom, it executes it.
    await set(refreshActivityCategoryStandardAtom);
    await set(refreshNumberOfRegionsAtom);
    await set(refreshNumberOfCustomActivityCategoryCodesAtom);
    await set(refreshNumberOfCustomSectorsAtom);
    await set(refreshNumberOfCustomLegalFormsAtom);
  }
);

// ============================================================================
// ASYNC ACTION ATOMS - For handling side effects
// ============================================================================

// Auth actions

// Helper to fetch and set auth status
export const fetchAndSetAuthStatusAtom = atom(null, async (get, set) => {
  const client = get(restClientAtom);
  if (!client) {
    console.error("fetchAndSetAuthStatusAtom: No client available to fetch auth status.");
    set(authStatusAtom, { isAuthenticated: false, user: null, tokenExpiring: false });
    // Even if client is not available, we mark the check as attempted to avoid loops if client init fails.
    set(authStatusInitiallyCheckedAtom, true); 
    return;
  }
  try {
    const { data, error } = await client.rpc("auth_status");
    if (error) {
      console.error("Auth status check failed after action:", error);
      set(authStatusAtom, { isAuthenticated: false, user: null, tokenExpiring: false });
      return;
    }
    const authData = data as any; // Type cast based on expected RPC response
    const newStatus: AuthStatus = authData === null || !authData.is_authenticated
      ? {
          isAuthenticated: false,
          user: null,
          tokenExpiring: false,
        }
      : {
          isAuthenticated: authData.is_authenticated,
          tokenExpiring: authData.token_expiring === true,
          user: authData.uid ? {
            uid: authData.uid,
            sub: authData.sub,
            email: authData.email,
            role: authData.role,
            statbus_role: authData.statbus_role,
            last_sign_in_at: authData.last_sign_in_at,
            created_at: authData.created_at,
          } : null,
        };
    set(authStatusAtom, newStatus);

    // If authenticated, trigger refresh of other dependent data
    // This is now handled by AppInitializer effect based on isAuthenticated and initialAuthCheckDone
    // if (newStatus.isAuthenticated) {
    //   set(refreshBaseDataAtom);
    //   set(refreshWorkerStatusAtom);
    //   set(initializeTableColumnsAtom); 
    //   set(refreshAllGettingStartedDataAtom);
    //   set(refreshAllUnitCountsAtom);
    // }

  } catch (e) {
    console.error("Error fetching auth status after action:", e);
    set(authStatusAtom, { isAuthenticated: false, user: null, tokenExpiring: false });
  } finally {
    set(authStatusInitiallyCheckedAtom, true);
  }
});

export const loginAtom = atom(
  null,
  async (get, set, credentials: { email: string; password: string }) => {
    // Determine API URL (relative for client-side)
    const apiUrl = ''; // The /rest API is transparently proxied from the same url as the frontend, so use a relative path for API calls from browser

    try {
      const response = await fetch(`${apiUrl}/rest/rpc/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ email: credentials.email, password: credentials.password }),
        credentials: 'include' // Essential for cookie-based auth
      });

      if (!response.ok) {
        let errorData = { message: `Login failed with status: ${response.status}` };
        try {
          errorData = await response.json();
        } catch (e) {
          // Ignore if response is not JSON
        }
        throw new Error(errorData.message || `Login failed with status: ${response.status}`);
      }
      
      // Login call was successful, cookies should be set by the server.
      // Now, fetch the new auth status to update user details and app state.
      await set(fetchAndSetAuthStatusAtom);

      // Note: The original AuthContext used authStore.clearAllCaches().
      // With Jotai, setting authStatusAtom triggers re-evaluation.
      // The hard redirect in LoginForm.tsx (`window.location.href = "/";`)
      // will cause a full app re-initialization, including RestClientStore,
      // which is generally a good approach after login/logout.

    } catch (error) {
      console.error('Login failed:', error);
      // Ensure authStatusAtom reflects unauthenticated state on error
      set(authStatusAtom, { isAuthenticated: false, user: null, tokenExpiring: false });
      throw error; // Re-throw for the UI to handle
    }
  }
)

export const logoutAtom = atom(
  null,
  async (get, set) => {
    const apiUrl = ''; // The /rest API is transparently proxied from the same url as the frontend, so use a relative path for API calls from browser

    try {
      const response = await fetch(`${apiUrl}/rest/rpc/logout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        credentials: 'include'
      });

      if (!response.ok) {
        let errorData = { message: `Logout failed with status: ${response.status}` };
        try {
          errorData = await response.json();
        } catch (e) {
          // Ignore if response is not JSON
        }
        // Don't throw for logout, just log and proceed to clear state
        console.error(errorData.message || `Logout failed with status: ${response.status}`);
      }
    } catch (error) {
      console.error('Error during logout API call:', error);
      // Proceed to clear client-side state even if API call fails
    }
    
    // Clear client-side auth state
    set(authStatusAtom, {
      isAuthenticated: false,
      user: null,
      tokenExpiring: false,
    });
    
    // Clear other sensitive data
    set(baseDataAtom, {
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null,
      hasStatisticalUnits: false,
    });
    // Reset other relevant atoms to their initial/empty state
    set(workerStatusAtom, { isImporting: null, isDerivingUnits: null, isDerivingReports: null, loading: false, error: null });
    set(searchStateAtom, initialSearchStateValues);
    set(searchResultAtom, { data: [], total: 0, loading: false, error: null });
    set(selectedUnitsAtom, []);
    set(tableColumnsAtom, []); // This will be re-initialized on next load if needed
    set(gettingStartedUIStateAtom, { currentStep: 0, completedSteps: [], isVisible: true });
    set(gettingStartedDataAtom, { activity_category_standard: null, numberOfRegions: null, numberOfCustomActivityCategoryCodes: null, numberOfCustomSectors: null, numberOfCustomLegalForms: null });
    set(importStateAtom, { isImporting: false, progress: 0, currentFile: null, errors: [], completed: false, useExplicitDates: false, selectedImportTimeContextIdent: null });
    set(unitCountsAtom, { legalUnits: null, establishmentsWithLegalUnit: null, establishmentsWithoutLegalUnit: null });


    // Note: Similar to login, a hard redirect (`window.location.href = "/login";`
    // in LogoutForm.tsx) will ensure a full app re-initialization.
  }
)

// Base data actions
export const refreshBaseDataAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      console.error("refreshBaseDataAtom: No client available, skipping fetch.");
      // Optionally set an error state or specific loading state for baseDataAtom if desired
      // For now, just log and return, preventing an attempt to fetch without a client.
      return;
    }
    
    try {
      // Import BaseDataStore for the actual data fetching logic.
      // The baseDataStore.getBaseData() method contains its own caching and
      // request deduplication logic.
      const { baseDataStore } = await import('@/context/BaseDataStore');
      const freshData = await baseDataStore.getBaseData(client);
      
      set(baseDataAtom, freshData);
    } catch (error) {
      console.error('Failed to refresh base data:', error);
      // Optionally set an error state in an atom
      throw error; // Or handle more gracefully
    }
  }
)

export const refreshHasStatisticalUnitsAtomAction = atom<null, [], Promise<boolean>>(
  null,
  async (get, set) => {
    const client = get(restClientAtom)
    if (!client) {
      console.error('No REST client available for refreshing statistical units status.')
      throw new Error('No REST client available')
    }
    
    try {
      // Import BaseDataStore for the actual data fetching logic
      const { baseDataStore } = await import('@/context/BaseDataStore')
      const hasUnits = await baseDataStore.refreshHasStatisticalUnits(client)
      
      // Update the baseDataAtom with the new hasStatisticalUnits status
      set(baseDataAtom, (prevData) => ({
        ...prevData,
        hasStatisticalUnits: hasUnits,
      }))
      
      return hasUnits
    } catch (error) {
      console.error('Failed to refresh hasStatisticalUnits:', error)
      throw error
    }
  }
)

export const refreshWorkerStatusAtom = atom(
  null,
  async (get, set, functionName?: string) => {
    const client = get(restClientAtom)
    if (!client) throw new Error('No client available')
    
    try {
      set(workerStatusAtom, prev => ({ ...prev, loading: true, error: null }))
      
      // Import BaseDataStore for worker status logic
      const { baseDataStore } = await import('@/context/BaseDataStore');
      if (typeof functionName === 'string' && functionName.length > 0) {
        await baseDataStore.refreshWorkerStatus(functionName);
      } else {
        // Assumes calling refreshWorkerStatus without a specific functionName
        // (or with undefined/null) refreshes all relevant statuses.
        await baseDataStore.refreshWorkerStatus();
      }
      
      // Get updated status and set it
      const status = baseDataStore.getWorkerStatus()
      set(workerStatusAtom, {
        isImporting: status.isImporting,
        isDerivingUnits: status.isDerivingUnits,
        isDerivingReports: status.isDerivingReports,
        loading: false,
        error: status.error,
      })
    } catch (error) {
      set(workerStatusAtom, prev => ({
        ...prev,
        loading: false,
        error: error instanceof Error ? error.message : 'Unknown error'
      }))
    }
  }
)

// Selection actions
export const toggleSelectionAtom = atom(
  null,
  (get, set, unit: StatisticalUnit) => {
    const currentSelection = get(selectedUnitsAtom)
    const isSelected = currentSelection.some(
      selected => selected.unit_id === unit.unit_id && selected.unit_type === unit.unit_type
    )
    
    if (isSelected) {
      set(selectedUnitsAtom, currentSelection.filter(
        selected => !(selected.unit_id === unit.unit_id && selected.unit_type === unit.unit_type)
      ))
    } else {
      set(selectedUnitsAtom, [...currentSelection, unit])
    }
  }
)

export const clearSelectionAtom = atom(
  null,
  (get, set) => {
    set(selectedUnitsAtom, [])
  }
)

// Search actions
// Import getStatisticalUnits - adjust path if necessary, assuming it's in app/search/
import { getStatisticalUnits } from '../app/search/search-requests'; 
// The SearchResult type from search.d.ts, used by getStatisticalUnits
import type { SearchResult as ApiSearchResultType } from '../app/search/search.d';

export const performSearchAtom = atom(
  null,
  async (get, set) => {
    const postgrestClient = get(restClientAtom);
    const derivedApiParams = get(derivedApiSearchParamsAtom);

    if (!postgrestClient) {
      console.error("performSearchAtom: REST client not available.");
      set(searchResultAtom, { 
        data: [], 
        total: 0, 
        loading: false, 
        error: 'Search client not initialized.' 
      });
      return;
    }
    
    // Keep previous data while loading to avoid UI flickering if desired,
    // or set to empty/defaults. For now, clear old results.
    set(searchResultAtom, prev => ({ 
        ...prev, // Keep existing data if any, or define default structure
        loading: true, 
        error: null 
    }));
    
    try {
      const response: ApiSearchResultType = await getStatisticalUnits(postgrestClient, derivedApiParams);
      
      set(searchResultAtom, { 
        data: response.statisticalUnits, 
        total: response.count, 
        loading: false, 
        error: null 
      });
    } catch (error) {
      console.error("Search failed in performSearchAtom:", error);
      set(searchResultAtom, prev => ({
        ...prev, // Keep existing data on error if desired
        loading: false,
        error: error instanceof Error ? error.message : 'Search operation failed'
      }));
    }
  }
)

// Atom to reset the search state to its initial values
export const resetSearchStateAtom = atom(
  null,
  (get, set) => {
    set(searchStateAtom, initialSearchStateValues);
    // Optionally, reset search results as well
    set(searchResultAtom, {
      data: [],
      total: 0,
      loading: false,
      error: null,
    });
  }
);

// ============================================================================
// LOADABLE ATOMS - For async data with loading states
// ============================================================================

// Loadable versions of async atoms that don't require Suspense
export const baseDataLoadableAtom = loadable(baseDataAtom)
export const authStatusLoadableAtom = loadable(authStatusAtom)
export const workerStatusLoadableAtom = loadable(workerStatusAtom)

// ============================================================================
// COMPUTED/DERIVED ATOMS (Including Table Column Logic)
// ============================================================================

// Atom to generate the list of all available table columns, including dynamic ones
export const availableTableColumnsAtom = atom<TableColumn[]>((get) => {
  const statDefinitions = get(statDefinitionsAtom);

  const statisticColumns: AdaptableTableColumn[] = statDefinitions.map(
    (statDefinition) =>
      ({
        type: "Adaptable",
        code: "statistic",
        stat_code: statDefinition.code!,
        label: statDefinition.name!,
        visible: statDefinition.priority! <= 1, // Default visibility based on priority
        profiles:
          statDefinition.priority === 1
            ? ["Brief", "Regular", "All"]
            : statDefinition.priority === 2
              ? ["Regular", "All"]
              : ["All"],
      } as AdaptableTableColumn)
  );

  // Ensure statDefinitions is not undefined before proceeding.
  // If statDefinitionsAtom has not resolved or is empty, return a basic set or empty array.
  if (!statDefinitions || statDefinitions.length === 0) {
     // Return a minimal set of columns or empty array if statDefinitions are not ready
     // This prevents errors if this atom is read before statDefinitions are available.
     // Alternatively, this could throw or return a specific "loading" state if preferred.
    return [ { type: "Always", code: "name", label: "Name" } ];
  }

  return [
    { type: "Always", code: "name", label: "Name" },
    {
      type: "Adaptable",
      code: "activity_section",
      label: "Activity Section",
      visible: true,
      stat_code: null,
      profiles: ["Brief", "All"],
    },
    {
      type: "Adaptable",
      code: "activity",
      label: "Activity",
      visible: false,
      stat_code: null,
      profiles: ["Regular", "All"],
    },
    {
      type: "Adaptable",
      code: "secondary_activity",
      label: "Secondary Activity",
      visible: false,
      stat_code: null,
      profiles: ["Regular", "All"],
    },
    {
      type: "Adaptable",
      code: "top_region",
      label: "Top Region",
      visible: true,
      stat_code: null,
      profiles: ["Brief", "All"],
    },
    {
      type: "Adaptable",
      code: "region",
      label: "Region",
      visible: false,
      stat_code: null,
      profiles: ["Regular", "All"],
    },
    ...statisticColumns,
    {
      type: "Adaptable",
      code: "unit_counts",
      label: "Unit Counts",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "sector",
      label: "Sector",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "legal_form",
      label: "Legal Form",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "physical_address",
      label: "Address",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "birth_date",
      label: "Birth Date",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "death_date",
      label: "Death Date",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "status",
      label: "Status",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "unit_size",
      label: "Unit Size",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "data_sources",
      label: "Data Source",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "last_edit",
      label: "Last Edit",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
  ];
});

// Atom to initialize table columns by merging available columns with stored preferences
export const initializeTableColumnsAtom = atom(null, (get, set) => {
  const availableColumns = get(availableTableColumnsAtom);
  const storedColumns = get(tableColumnsAtom); // Preferences from localStorage

  if (availableColumns.length === 0 && storedColumns.length === 0) {
    // If no stat definitions yet, and no stored columns, do nothing or set to a minimal default
    // This might occur on initial load before baseData is ready.
    // availableTableColumnsAtom returns a minimal Name column in this case.
    set(tableColumnsAtom, availableColumns);
    return;
  }
  
  const mergedColumns = availableColumns.map(availCol => {
    const storedCol = storedColumns.find(sc =>
      sc.code === availCol.code &&
      (sc.type === 'Always' || (sc.type === 'Adaptable' && availCol.type === 'Adaptable' && sc.stat_code === availCol.stat_code))
    );
    if (availCol.type === 'Adaptable') {
      return {
        ...availCol,
        visible: storedCol && storedCol.type === 'Adaptable' ? storedCol.visible : availCol.visible,
      };
    }
    return availCol; // For 'Always' type columns
  });

  // Check if the merged columns are different from what's already stored
  // to avoid unnecessary writes to localStorage by atomWithStorage.
  // This is a shallow check; a deep check might be needed if structures are complex.
  // However, atomWithStorage itself might do a deep check or only write on reference change.
  // For simplicity, we set it. If performance issues arise, add a deep equality check here.
  set(tableColumnsAtom, mergedColumns);
});

// Atom to get only the visible columns
export const visibleTableColumnsAtom = atom<TableColumn[]>((get) => {
  const allColumns = get(tableColumnsAtom);
  return allColumns.filter(col => col.type === 'Always' || (col.type === 'Adaptable' && col.visible));
});

// Action atom to toggle a column's visibility
export const toggleTableColumnAtom = atom(null, (get, set, columnToToggle: TableColumn) => {
  const currentColumns = get(tableColumnsAtom);
  const newColumns = currentColumns.map(col => {
    if (col.type === 'Adaptable' && columnToToggle.type === 'Adaptable' &&
        col.code === columnToToggle.code && col.stat_code === columnToToggle.stat_code) {
      return { ...col, visible: !col.visible };
    }
    return col;
  });
  set(tableColumnsAtom, newColumns);
});

// Atom representing the column profiles based on current columns
export const columnProfilesAtom = atom((get) => {
  const currentColumns = get(tableColumnsAtom);
  const profiles: Record<ColumnProfile, TableColumn[]> = {
    Brief: [],
    Regular: [],
    All: [],
  };

  (Object.keys(profiles) as ColumnProfile[]).forEach(profileName => {
    profiles[profileName] = currentColumns.map(col => {
      if (col.type === 'Adaptable' && col.profiles) {
        return { ...col, visible: col.profiles.includes(profileName) };
      }
      return col; // 'Always' visible columns are part of all profiles as-is
    });
  });
  return profiles;
});

// Action atom to set column visibility based on a profile
export const setTableColumnProfileAtom = atom(null, (get, set, profile: ColumnProfile) => {
  const availableColumns = get(availableTableColumnsAtom); // Use defaults to reset structure
  const newColumns = availableColumns.map(col => {
    if (col.type === 'Adaptable' && col.profiles) {
      return { ...col, visible: col.profiles.includes(profile) };
    }
    return col;
  });
  set(tableColumnsAtom, newColumns);
});


// Import transformation functions and constants from url-search-params
import {
  fullTextSearchDeriveStateUpdateFromValue,
  unitTypeDeriveStateUpdateFromValues,
  invalidCodesDeriveStateUpdateFromValues,
  legalFormDeriveStateUpdateFromValues,
  regionDeriveStateUpdateFromValues,
  sectorDeriveStateUpdateFromValues,
  activityCategoryDeriveStateUpdateFromValues,
  statusDeriveStateUpdateFromValues,
  unitSizeDeriveStateUpdateFromValues,
  dataSourceDeriveStateUpdateFromValues,
  externalIdentDeriveStateUpdateFromValues,
  statisticalVariableDeriveStateUpdateFromValue,
  // statisticalVariableParse, // Not directly needed here if we parse "op:val" manually
  SEARCH, // FTS app param name
  UNIT_TYPE,
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SECTOR,
  ACTIVITY_CATEGORY_PATH,
  STATUS,
  UNIT_SIZE,
  DATA_SOURCE,
} from '../app/search/filters/url-search-params';
import { SearchAction } from '@/app/search/search';


// Atom to derive API search parameters
export const derivedApiSearchParamsAtom = atom((get) => {
  const searchState = get(searchStateAtom);
  const selectedTimeContext = get(selectedTimeContextAtom);
  const externalIdentTypes = get(externalIdentTypesAtom); // from baseDataAtom
  const statDefinitions = get(statDefinitionsAtom); // from baseDataAtom
  const { allDataSources } = get(searchPageDataAtom); // for dataSourceDeriveStateUpdateFromValues

  const params = new URLSearchParams();

  // 1. Full-text search query
  if (searchState.query && searchState.query.trim().length > 0) {
    // The SEARCH constant from url-search-params.ts is the app_param_name for FTS.
    // fullTextSearchDeriveStateUpdateFromValue handles generating the api_param_name and api_param_value.
    const ftsAction = fullTextSearchDeriveStateUpdateFromValue(searchState.query.trim());
    if (ftsAction.payload.api_param_name && ftsAction.payload.api_param_value) {
      params.set(ftsAction.payload.api_param_name, ftsAction.payload.api_param_value);
    }
  }

  // 2. Filters from searchState.filters
  Object.entries(searchState.filters).forEach(([appParamName, appParamValue]) => {
    let actionPayload: SearchAction['payload'] | null = null;

    switch (appParamName) {
      case UNIT_TYPE:
        let unitTypeValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          unitTypeValues = appParamValue as (string | null)[];
        } else if (typeof appParamValue === 'string' && appParamValue.trim().length > 0) {
          unitTypeValues = [appParamValue.trim()];
        }
        // If appParamValue is null, undefined, or an empty string, unitTypeValues remains [].
        // unitTypeDeriveStateUpdateFromValues will correctly handle an empty array by setting api_param_value to null.
        actionPayload = unitTypeDeriveStateUpdateFromValues(unitTypeValues).payload;
        break;
      case INVALID_CODES:
        // appParamValue is ["yes"] or [] from searchState.filters
        // invalidCodesDeriveStateUpdateFromValues expects "yes" or null.
        const invalidCodesValue = Array.isArray(appParamValue) && appParamValue.length > 0 && appParamValue[0] === "yes" 
                                  ? "yes" 
                                  : null;
        actionPayload = invalidCodesDeriveStateUpdateFromValues(invalidCodesValue).payload;
        break;
      case LEGAL_FORM:
        actionPayload = legalFormDeriveStateUpdateFromValues(appParamValue as (string | null)[]).payload;
        break;
      case REGION:
        let regionValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          regionValues = appParamValue as (string | null)[];
        } else if (typeof appParamValue === 'string' && appParamValue.trim().length > 0) {
          regionValues = [appParamValue.trim()];
        } else if (appParamValue === null) { // Handle explicit null for "Missing"
          regionValues = [null];
        }
        actionPayload = regionDeriveStateUpdateFromValues(regionValues).payload;
        break;
      case SECTOR:
        let sectorValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          sectorValues = appParamValue as (string | null)[];
        } else if (typeof appParamValue === 'string' && appParamValue.trim().length > 0) {
          sectorValues = [appParamValue.trim()];
        } else if (appParamValue === null) { // Handle explicit null for "Missing"
          sectorValues = [null];
        }
        actionPayload = sectorDeriveStateUpdateFromValues(sectorValues).payload;
        break;
      case ACTIVITY_CATEGORY_PATH:
        let activityCategoryValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          activityCategoryValues = appParamValue as (string | null)[];
        } else if (typeof appParamValue === 'string' && appParamValue.trim().length > 0) {
          activityCategoryValues = [appParamValue.trim()];
        } else if (appParamValue === null) { // Handle explicit null for "Missing"
          activityCategoryValues = [null];
        }
        actionPayload = activityCategoryDeriveStateUpdateFromValues(activityCategoryValues).payload;
        break;
      case STATUS:
        actionPayload = statusDeriveStateUpdateFromValues(appParamValue as (string | null)[]).payload;
        break;
      case UNIT_SIZE:
        actionPayload = unitSizeDeriveStateUpdateFromValues(appParamValue as (string | null)[]).payload;
        break;
      case DATA_SOURCE:
        actionPayload = dataSourceDeriveStateUpdateFromValues(appParamValue as (string | null)[], allDataSources).payload;
        break;
      default:
        const extIdentType = externalIdentTypes.find(type => type.code === appParamName);
        if (extIdentType) {
          actionPayload = externalIdentDeriveStateUpdateFromValues(extIdentType, appParamValue as string | null).payload;
          break;
        }
        const statDef = statDefinitions.find(def => def.code === appParamName);
        if (statDef) {
          let parsedStatVarValue: { operator: string; operand: string } | null = null;
          if (typeof appParamValue === 'string' && appParamValue.includes(':')) {
            const [op, val] = appParamValue.split(':', 2);
            parsedStatVarValue = { operator: op, operand: val };
          } else if (appParamValue === null) {
            // This case means the filter was cleared
            parsedStatVarValue = null;
          }
          // If appParamValue is not a string "op:val" or null, it's an invalid state for stat var,
          // statisticalVariableDeriveStateUpdateFromValue will handle `null` by not setting the param.
          actionPayload = statisticalVariableDeriveStateUpdateFromValue(statDef, parsedStatVarValue).payload;
          break;
        }
    }

    if (actionPayload && actionPayload.api_param_name && actionPayload.api_param_value) {
      params.set(actionPayload.api_param_name, actionPayload.api_param_value);
    }
    // If api_param_value is null, the parameter is intentionally not added.
  });

  // 3. Time context
  if (selectedTimeContext && selectedTimeContext.valid_on) {
    params.set("valid_from", `lte.${selectedTimeContext.valid_on}`);
    params.set("valid_to", `gte.${selectedTimeContext.valid_on}`);
  }

  // 4. Sorting
  if (searchState.sorting.field) {
    const orderName = searchState.sorting.field;
    const orderDirection = searchState.sorting.direction;
    const externalIdentType = externalIdentTypes.find(type => type.code === orderName);
    const statDefinition = statDefinitions.find(def => def.code === orderName);

    if (externalIdentType) {
      params.set("order", `external_idents->>${orderName}.${orderDirection}`);
    } else if (statDefinition) {
      params.set("order", `stats_summary->${orderName}->sum.${orderDirection}`);
    } else {
      params.set("order", `${orderName}.${orderDirection}`);
    }
  }

  // 5. Pagination
  if (searchState.pagination.page && searchState.pagination.pageSize) {
    const offset = (searchState.pagination.page - 1) * searchState.pagination.pageSize;
    params.set("limit", `${searchState.pagination.pageSize}`);
    params.set("offset", `${offset}`);
  }
  return params;
});

// Combined authentication and base data status
export const appReadyAtom = atom((get) => {
  const auth = get(authStatusAtom)
  const baseData = get(baseDataAtom)
  
  return {
    isReady: auth.isAuthenticated && baseData.statDefinitions.length > 0,
    isAuthenticated: auth.isAuthenticated,
    hasBaseData: baseData.statDefinitions.length > 0,
    user: auth.user,
  }
})

// Search with filters applied
export const filteredSearchResultsAtom = atom((get) => {
  const results = get(searchResultAtom)
  const searchState = get(searchStateAtom)
  
  // Apply any additional client-side filtering here
  return results
})

// Export all atoms for easy importing
export const atoms = {
  // Auth
  authStatusAtom,
  isAuthenticatedAtom,
  currentUserAtom,
  tokenExpiringAtom,
  loginAtom,
  logoutAtom,
  
  // Base Data
  baseDataAtom,
  statDefinitionsAtom,
  externalIdentTypesAtom,
  statbusUsersAtom,
  timeContextsAtom,
  defaultTimeContextAtom,
  hasStatisticalUnitsAtom,
  refreshBaseDataAtom,
  refreshHasStatisticalUnitsAtomAction,
  
  // Worker Status
  workerStatusAtom,
  refreshWorkerStatusAtom,
  
  // Rest Client
  restClientAtom,
  
  // Time Context
  selectedTimeContextAtom,
  
  // Search
  searchStateAtom,
  searchResultAtom,
  performSearchAtom,
  filteredSearchResultsAtom,
  resetSearchStateAtom, // Export the reset action
  initialSearchStateValues, // Export the initial values
  derivedApiSearchParamsAtom, // Export derived search params
  searchPageDataAtom, // Export search page static data
  setSearchPageDataAtom, // Export action to set search page data
  
  // Selection
  selectedUnitsAtom,
  selectedUnitIdsAtom,
  selectionCountAtom,
  toggleSelectionAtom,
  clearSelectionAtom,
  
  // Table Columns
  tableColumnsAtom,
  availableTableColumnsAtom,
  initializeTableColumnsAtom,
  visibleTableColumnsAtom,
  toggleTableColumnAtom,
  columnProfilesAtom,
  setTableColumnProfileAtom,
  
  // Getting Started
  gettingStartedUIStateAtom,
  gettingStartedDataAtom,
  refreshActivityCategoryStandardAtom,
  refreshNumberOfRegionsAtom,
  refreshNumberOfCustomActivityCategoryCodesAtom,
  refreshNumberOfCustomSectorsAtom,
  refreshNumberOfCustomLegalFormsAtom,
  refreshAllGettingStartedDataAtom,
  
  // Import
  importStateAtom,
  unitCountsAtom,
  refreshUnitCountAtom,
  refreshAllUnitCountsAtom,
  setImportSelectedTimeContextAtom,
  setImportUseExplicitDatesAtom,
  createImportJobAtom,
  allPendingJobsStateAtom, // Renamed
  refreshPendingJobsByPatternAtom, // Renamed
  
  // Computed
  appReadyAtom,

  // App Initialization State
  authStatusInitiallyCheckedAtom,
  fetchAndSetAuthStatusAtom, // Added for explicit export
  searchStateInitializedAtom, // Export the new atom
  
  // Loadable
  baseDataLoadableAtom,
  authStatusLoadableAtom,
  workerStatusLoadableAtom,
}
