/**
 * Core Jotai Atoms - Replacing Context Providers
 * 
 * This file contains the main atoms that replace the complex Context + useEffect patterns.
 * Atoms are globally accessible and only trigger re-renders for components that use them.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable } from 'jotai/utils'
import type { Database, Tables, TablesInsert } from '@/lib/database.types'
import type { PostgrestClient } from '@supabase/postgrest-js'
import type { TableColumn, AdaptableTableColumn, ColumnProfile } from '../app/search/search.d';

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
  loading: boolean;
  isAuthenticated: boolean
  tokenExpiring: boolean
  user: User | null
  error_code: string | null;
}

// Base auth atom
export const authStatusCoreAtom = atomWithRefresh(async (get) => {
  const client = get(restClientAtom);
  // This atom should only attempt to fetch if the client is available.
  // Initial state before client is ready might be handled by AppInitializer or initial value of loadable.
  if (!client) {
    // Return a default unauthenticated state if client isn't ready
    // This helps avoid errors if this atom is read before client initialization.
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log("[authStatusCoreAtom] No client available, returning default unauthenticated state.");
    }
    return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: null };
  }
  try {
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log("[authStatusCoreAtom] Client available, calling client.rpc('auth_status', {}, { get: true }).");
    }
    // Using GET for auth_status
    const { data, error, status, statusText } = await client.rpc("auth_status", {}, { get: true });

    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log(`[authStatusCoreAtom] Response from client.rpc('auth_status', {}, { get: true }): status=${status}, statusText=${statusText}, data=${JSON.stringify(data)}, error=${JSON.stringify(error)}`);
    }

    if (error) {
      console.error("authStatusCoreAtom: Auth status check RPC failed:", { status, statusText, error });
      return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'RPC_ERROR' };
    }
    return _parseAuthStatusRpcResponseToAuthStatus(data);
  } catch (e) {
    console.error("authStatusCoreAtom: Exception during auth status fetch (outer catch):", e);
    return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'FETCH_ERROR' };
  }
});

export const authStatusLoadableAtom = loadable(authStatusCoreAtom);

import type { Loadable } from 'jotai/vanilla/utils/loadable';

// Derived atoms for easier access
export const authStatusAtom = atom<AuthStatus>(
  (get): AuthStatus => {
    const loadableState: Loadable<Omit<AuthStatus, 'loading'>> = get(authStatusLoadableAtom);
    if (loadableState.state === 'loading') {
      return { loading: true, isAuthenticated: false, user: null, tokenExpiring: false, error_code: null };
    }
    if (loadableState.state === 'hasError') {
      // Assuming the error in loadableState.error might be relevant, but AuthStatus needs a specific error_code field.
      // For simplicity, setting a generic error_code here.
      return { loading: false, isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'LOADABLE_ERROR' };
    }
    const data: Omit<AuthStatus, 'loading'> = loadableState.data; // No need for ?? if hasData implies data exists
    return { loading: false, ...data };
  }
);

export const isAuthenticatedAtom = atom((get) => {
  const loadableState: Loadable<Omit<AuthStatus, 'loading'>> = get(authStatusLoadableAtom);
  return loadableState.state === 'hasData' && loadableState.data.isAuthenticated;
});
export const currentUserAtom = atom((get) => {
  const loadableState: Loadable<Omit<AuthStatus, 'loading'>> = get(authStatusLoadableAtom);
  return loadableState.state === 'hasData' ? loadableState.data.user : null;
});
export const tokenExpiringAtom = atom((get) => {
  const loadableState: Loadable<Omit<AuthStatus, 'loading'>> = get(authStatusLoadableAtom);
  return loadableState.state === 'hasData' ? loadableState.data.tokenExpiring : false;
});

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

const initialBaseData: BaseData = {
  statDefinitions: [],
  externalIdentTypes: [],
  statbusUsers: [],
  timeContexts: [],
  defaultTimeContext: null,
  hasStatisticalUnits: false,
};

export const baseDataCoreAtom = atomWithRefresh(async (get): Promise<BaseData> => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return initialBaseData;

  const client = get(restClientAtom);
  if (!client) {
    console.error("baseDataCoreAtom: No client available.");
    return initialBaseData;
  }

  try {
    const [
      statDefinitionsResult,
      externalIdentTypesResult,
      statbusUsersResult,
      statisticalUnitResult,
      timeContextsResult
    ] = await Promise.all([
      client.from("stat_definition_active").select(),
      client.from("external_ident_type_active").select(),
      client.from("user").select(), // Consider if all users are needed or just current user's info
      client.from("statistical_unit").select("*", { count: "exact", head: true }), // Check existence efficiently
      client.from("time_context").select("*") // Fetches all, view is ordered by default
    ]);

    if (statDefinitionsResult.error) console.error('Error fetching stat definitions:', statDefinitionsResult.error);
    if (externalIdentTypesResult.error) console.error('Error fetching external ident types:', externalIdentTypesResult.error);
    if (statbusUsersResult.error) console.error('Error fetching statbus users:', statbusUsersResult.error);
    if (statisticalUnitResult.error) console.error('Error checking for statistical units:', statisticalUnitResult.error); // This error might still occur if other issues arise, but the query itself is fixed.
    if (timeContextsResult.error) console.error('Error fetching time contexts:', timeContextsResult.error);
    
    let defaultTimeContext: Tables<"time_context"> | null = null;
    if (timeContextsResult.data && timeContextsResult.data.length > 0) {
      // The time_context view is pre-ordered by priority, then valid_on descending.
      // The first one is the default.
      defaultTimeContext = timeContextsResult.data[0] as Tables<"time_context">;
    }

    return {
      statDefinitions: statDefinitionsResult.data || [],
      externalIdentTypes: externalIdentTypesResult.data || [],
      statbusUsers: statbusUsersResult.data || [],
      timeContexts: timeContextsResult.data || [],
      defaultTimeContext: defaultTimeContext,
      hasStatisticalUnits: !!statisticalUnitResult.count && statisticalUnitResult.count > 0,
    };
  } catch (error) {
    console.error("baseDataCoreAtom: Failed to fetch base data:", error);
    return initialBaseData;
  }
});

export const baseDataLoadableAtom = loadable(baseDataCoreAtom);

export const baseDataAtom = atom<BaseData & { loading: boolean; error: string | null }>(
  (get): BaseData & { loading: boolean; error: string | null } => {
    const loadableState = get(baseDataLoadableAtom);
    switch (loadableState.state) {
      case 'loading':
        return { ...initialBaseData, loading: true, error: null };
      case 'hasError':
        const error = loadableState.error;
        return { ...initialBaseData, loading: false, error: error instanceof Error ? error.message : String(error) };
      case 'hasData':
        return { ...loadableState.data, loading: false, error: null };
      default: // Should not happen with loadable
        return { ...initialBaseData, loading: false, error: 'Unknown loadable state' };
    }
  }
);

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

// Core async atom for worker status
export const workerStatusCoreAtom = atomWithRefresh(async (get): Promise<WorkerStatusData> => {
  const isAuthenticated = get(isAuthenticatedAtom);
  // Do not fetch if not authenticated, but also don't return error, just initial state.
  // Components consuming this should ideally also check auth if behavior needs to differ.
  if (!isAuthenticated) return initialWorkerStatusData;

  const client = get(restClientAtom);
  if (!client) {
    // console.error("workerStatusCoreAtom: No client available."); // Logged by restClientAtom if needed
    return initialWorkerStatusData;
  }

  try {
    const [importRes, unitsRes, reportsRes] = await Promise.all([
      client.rpc('is_importing'),
      client.rpc('is_deriving_statistical_units'),
      client.rpc('is_deriving_reports'),
    ]);

    // Errors are logged by the RPC calls themselves if they fail at client level.
    // Here we just process data or default to null if data isn't as expected.
    return {
      isImporting: importRes.data ?? null,
      isDerivingUnits: unitsRes.data ?? null,
      isDerivingReports: reportsRes.data ?? null,
    };
  } catch (error) {
    console.error("workerStatusCoreAtom: Failed to fetch worker statuses:", error);
    return initialWorkerStatusData; // Return initial state on error
  }
});

export const workerStatusLoadableAtom = loadable(workerStatusCoreAtom);

// Interface for the synchronous view of worker status, including loading/error states
export interface WorkerStatus {
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
  loading: boolean;
  error: string | null;
}

// Compatibility workerStatusAtom (synchronous view)
export const workerStatusAtom = atom<WorkerStatus>(
  (get): WorkerStatus => {
    const loadableState: Loadable<WorkerStatusData> = get(workerStatusLoadableAtom);
    switch (loadableState.state) {
      case 'loading':
        return { ...initialWorkerStatusData, loading: true, error: null };
      case 'hasError':
        const error = loadableState.error;
        return { ...initialWorkerStatusData, loading: false, error: error instanceof Error ? error.message : String(error) };
      case 'hasData':
        return { ...loadableState.data, loading: false, error: null };
      default: // Should not happen with loadable
        return { ...initialWorkerStatusData, loading: false, error: 'Unknown loadable state' };
    }
  }
);

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

// UI State for the Getting Started Wizard - This might still be useful for a wizard UI,
// but the data fetching part is being decentralized.
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

// NOTE: gettingStartedDataAtom and its related data fetching atoms are removed.
// Data previously fetched here (activity_category_standard, numberOfRegions, etc.)
// will now be fetched by individual dashboard cards or components as needed.

// --- Individual Async Atoms for "Getting Started" Metrics ---
import { RESET, atomWithRefresh } from 'jotai/utils';

// Activity Category Standard Setting
export const activityCategoryStandardSettingAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null; // Don't fetch if not authenticated

  const client = get(restClientAtom);
  if (!client) return null; // Or throw error / return specific "not loaded" state
  const { data: settings, error } = await client
    .from("settings")
    .select("activity_category_standard(id,name)")
    .limit(1);
  if (error) {
    console.error('Failed to fetch activity_category_standard setting:', error);
    return null; // Or throw error
  }
  return settings?.[0]?.activity_category_standard as { id: number, name: string } ?? null;
});

// Number of Regions
export const numberOfRegionsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("region").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of regions:', error);
    return null;
  }
  return count;
});

// Number of Custom Activity Category Codes
export const numberOfCustomActivityCodesAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("activity_category_available_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom activity codes:', error);
    return null;
  }
  return count;
});

// Number of Custom Sectors
export const numberOfCustomSectorsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("sector_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom sectors:', error);
    return null;
  }
  return count;
});

// Number of Custom Legal Forms
export const numberOfCustomLegalFormsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("legal_form_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom legal forms:', error);
    return null;
  }
  return count;
});

// Number of Total Activity Category Codes (available)
export const numberOfTotalActivityCodesAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("activity_category_available").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of total activity codes:', error);
    return null;
  }
  return count;
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
export interface PendingJobsData {
  jobs: Tables<'import_job'>[];
  loading: boolean;
  error: string | null;
  lastFetched: number | null;
}

export interface AllPendingJobsState {
  [slugPattern: string]: PendingJobsData | undefined;
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

// Effect atom using jotai-effect to update authStatusInitiallyCheckedAtom
// This will run when its dependencies (authStatusLoadableAtom, authStatusInitiallyCheckedAtom) change,
// or when the effect atom is mounted.
import { atomEffect } from 'jotai-effect';

export const initialAuthCheckDoneEffect = atomEffect((get, set) => {
  const authLoadable = get(authStatusLoadableAtom);
  const alreadyChecked = get(authStatusInitiallyCheckedAtom);

  // Check if not already marked as checked to avoid unnecessary sets
  if (authLoadable.state !== 'loading' && !alreadyChecked) {
    set(authStatusInitiallyCheckedAtom, true);
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log("initialAuthCheckDoneEffect (jotai-effect): authStatusInitiallyCheckedAtom set to true.");
    }
  }
});

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

// NOTE: Getting Started Data Action atoms (refreshActivityCategoryStandardAtom, etc.) are removed.
// Data fetching is now handled by individual components/cards.

// ============================================================================
// ASYNC ACTION ATOMS - For handling side effects
// ============================================================================

// Auth actions

// Helper to fetch and set auth status

/**
 * Parses the raw response from auth_status, login, or refresh RPCs into the AuthStatus interface.
 * @param rpcResponseData The raw data from the RPC call.
 * @returns AuthStatus object.
 */
export const _parseAuthStatusRpcResponseToAuthStatus = (rpcResponseData: any): Omit<AuthStatus, 'loading'> => {
  // This helper returns the core status fields; 'loading' is managed by the calling action atom.
  const baseStatus = {
    isAuthenticated: rpcResponseData?.is_authenticated ?? false,
    tokenExpiring: rpcResponseData?.token_expiring === true,
    error_code: rpcResponseData?.error_code ?? null,
  };

  if (!baseStatus.isAuthenticated) {
    if (baseStatus.error_code && process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.warn(`_parseAuthStatusRpcResponseToAuthStatus: Call resulted in unauthenticated state with error_code: ${baseStatus.error_code}`);
    }
    return {
      ...baseStatus,
      user: null,
    };
  }

  return {
        ...baseStatus,
        user: rpcResponseData.uid ? {
          uid: rpcResponseData.uid,
          sub: rpcResponseData.sub,
          email: rpcResponseData.email,
          role: rpcResponseData.role,
          statbus_role: rpcResponseData.statbus_role,
          last_sign_in_at: rpcResponseData.last_sign_in_at,
          created_at: rpcResponseData.created_at,
        } : null,
      };
};

export const fetchAndSetAuthStatusAtom = atom(null, async (get, set) => {
  // Now, this atom simply triggers a refresh of the core async atom.
  // The loadable atom will handle the loading state.
  set(authStatusCoreAtom); // Corrected: Refresh atomWithRefresh
  // Wait for the refresh to complete if needed, or let components react to loadable state.
  // For simplicity, we'll assume components will react to the loadable state.
  // The authStatusInitiallyCheckedAtom is still important.
  
  // We need a way to know when the async atom has finished.
  // A common pattern is to read it until it's not loading, but that can be complex here.
  // For now, let's assume the refresh is triggered and components will update.
  // The `authStatusInitiallyCheckedAtom` will be set after the first attempt.
  // This atom is being removed. The logic is now handled by initialAuthCheckEffectAtom
  // and authStatusCoreAtom fetching naturally.
});

// import { fetchWithAuth } from '@/context/RestClientStore'; // Reverted for login/logout

export const loginAtom = atom(
  null,
  async (get, set, credentials: { email: string; password: string }) => {
    // No need to manually set loading states on authStatusAtom now.
    // Components will observe authStatusLoadableAtom.
    const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
    const loginUrl = `${apiUrl}/rest/rpc/login`;

    try {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[loginAtom] Current document.cookie before calling ${loginUrl}:`, document.cookie);
      }
      const response = await fetch(loginUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ email: credentials.email, password: credentials.password }),
        credentials: 'include'
      });

      let responseData: any;
      try {
        responseData = await response.json();
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log('[loginAtom] Response data from /rpc/login:', JSON.stringify(responseData));
        }
      } catch (jsonError) {
        // Handle cases where response body is not JSON or empty
        if (!response.ok) {
          // If the request failed (e.g. 401) and body is not JSON
          const errorMsg = `Login failed: Server error ${response.status}. Non-JSON response.`;
          console.error(`[loginAtom] ${errorMsg}`);
          throw new Error(errorMsg, { cause: 'SERVER_NON_JSON_ERROR' });
        }
        // If response.ok but body is not JSON (unexpected for /rpc/login)
        const errorMsg = 'Login failed: Invalid non-JSON response from server despite OK status.';
        console.error('[loginAtom] Login response OK, but failed to parse JSON body:', jsonError, errorMsg);
        throw new Error(errorMsg, { cause: 'CLIENT_INVALID_JSON_RESPONSE' });
      }

      if (!response.ok) {
        // response.ok is false (e.g., 401). responseData should contain error_code.
        const serverMessage = responseData?.message; // Optional: if backend provides a human-readable message
        const errorCode = responseData?.error_code;
        // Use server message if available, otherwise a generic message.
        // LoginForm.tsx will use loginErrorMessages based on errorCode for user display.
        const displayMessage = serverMessage || `Login failed with status: ${response.status}`;

        console.error(`[loginAtom] Login fetch not OK: ${displayMessage}`, errorCode ? `Error Code: ${errorCode}` : '');
        throw new Error(displayMessage, { cause: errorCode || 'UNKNOWN_LOGIN_FAILURE' });
      }
      
      // If response.ok (HTTP 200)
      // According to docs, responseData should have is_authenticated: true and error_code: null.
      // This block handles a deviation: 200 OK but payload indicates failure.
      if (responseData && responseData.is_authenticated === false && responseData.error_code) {
        const errorCode = responseData.error_code;
        const serverMessage = responseData.message;
        // Use loginErrorMessages from LoginForm.tsx, or server message, or default.
        // This requires loginErrorMessages to be accessible here or duplicated.
        // For simplicity, we'll use a generic message and rely on the cause.
        const displayMessage = serverMessage || `Login indicated failure despite 200 OK. Error: ${errorCode}`;
        console.warn(`[loginAtom] Login response OK (200), but payload indicates failure. Error Code: ${errorCode}. Message: ${displayMessage}`);
        throw new Error(displayMessage, { cause: errorCode });
      }

      // Successfully authenticated (200 OK and is_authenticated: true implied or explicit from responseData)
      // After successful login, the backend sets cookies.
      // We need to refresh our authStatusCoreAtom to read the new state.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("[loginAtom] Login successful. Calling set(authStatusCoreAtom) to mark for refresh.");
        console.log(`[loginAtom] Current document.cookie immediately after successful /rpc/login response (before authStatusCoreAtom refresh):`, document.cookie);
      }
      set(authStatusCoreAtom); 
      // Removed: await get(authStatusCoreAtom);
      // loginAtom now resolves after triggering the refresh.
      // Components should observe authStatusLoadableAtom to react to the loading and final state.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("[loginAtom] authStatusCoreAtom refresh triggered. loginAtom resolving.");
      }
      // The authStatusLoadableAtom will reflect the new state.

    } catch (error) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.error('[loginAtom] Catch block error. Refreshing auth status and re-throwing.', error);
      } else {
        console.error('[loginAtom] Login attempt failed.'); // Less verbose for production
      }
      // Refresh to ensure we have the latest (likely unauthenticated) status.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("[loginAtom] Error in login. Calling set(authStatusCoreAtom) to ensure consistent state. loginAtom re-throwing.");
      }
      set(authStatusCoreAtom); 
      // Removed: await get(authStatusCoreAtom);
      throw error; // Re-throw to be caught by LoginForm.tsx
    }
  }
)

export const clientSideRefreshAtom = atom<
  null, 
  [], 
  Promise<{ success: boolean; newStatus?: Omit<AuthStatus, 'loading'> }>
>(null, async (get, set) => {
  // This atom's purpose is to call the /rpc/refresh and then update auth state.
  // It should now just refresh the authStatusCoreAtom.
  const client = get(restClientAtom);
  if (!client) {
    console.error("clientSideRefreshAtom: No client available.");
    return { success: false };
  }
  try {
    // The actual refresh RPC call is implicitly handled by authStatusCoreAtom's read function
    // if it were designed to attempt refresh on 401.
    // However, our authStatusCoreAtom just fetches /rest/rpc/auth_status.
    // For an explicit client-side refresh, we still need to call the /rest/rpc/refresh endpoint.
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log(`[clientSideRefreshAtom] Current document.cookie before calling client.rpc('refresh'):`, document.cookie);
    }
    const { data: refreshRpcResponse, error } = await client.rpc('refresh'); // This uses fetchWithAuthRefresh internally

    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      console.log(`[clientSideRefreshAtom] Current document.cookie after client.rpc('refresh') call:`, document.cookie);
    }

    if (error) {
      console.error("clientSideRefreshAtom: Refresh RPC failed:", error);
      set(authStatusCoreAtom); // Trigger a re-fetch of auth_status to get a consistent state
      await get(authStatusCoreAtom);
      return { success: false };
    }

    // The 'refresh' RPC now returns an auth.auth_response object.
    // We can parse it to check for is_authenticated and error_code.
    const parsedRefreshStatus = _parseAuthStatusRpcResponseToAuthStatus(refreshRpcResponse);

    if (!parsedRefreshStatus.isAuthenticated) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.warn(`clientSideRefreshAtom: Refresh RPC succeeded but returned unauthenticated. Error code: ${parsedRefreshStatus.error_code}`);
      }
      // Even if refresh "succeeded" but returned unauth, cookies might have been cleared by the server.
      // Refresh authStatusCoreAtom to get the definitive state from /rest/rpc/auth_status.
      set(authStatusCoreAtom);
      await get(authStatusCoreAtom); // Ensure it re-fetches and updates.
      return { success: false }; // Indicate refresh didn't lead to an authenticated state.
    }

    // After successful RPC refresh AND if it indicates authenticated state, cookies are updated by the server.
    // Refresh our authStatusCoreAtom to reflect the new state.
    set(authStatusCoreAtom); 
    const newCoreStatus = await get(authStatusCoreAtom);
    return { success: true, newStatus: newCoreStatus };

  } catch (e) {
    console.error("clientSideRefreshAtom: Error during client-side refresh:", e);
    set(authStatusCoreAtom); 
    await get(authStatusCoreAtom);
    return { success: false };
  }
});

export const logoutAtom = atom(
  null,
  async (get, set) => {
    // No need to manually set loading states on authStatusAtom now.
    const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
    const logoutUrl = `${apiUrl}/rest/rpc/logout`;

    try {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[logoutAtom] Current document.cookie before calling ${logoutUrl}:`, document.cookie);
      }
      const response = await fetch(logoutUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        credentials: 'include' // Crucial for Set-Cookie to work and be stored/cleared
      });

      // The logout RPC now returns an auth_status_response.
      // We expect this response to indicate an unauthenticated state.
      const responseData = await response.json();

      // The logout RPC clears cookies on the server.
      // We need to refresh our authStatusCoreAtom to reflect the unauthenticated state.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[logoutAtom] Current document.cookie immediately after successful /rpc/logout response (before authStatusCoreAtom refresh):`, document.cookie);
      }
      set(authStatusCoreAtom); 
      await get(authStatusCoreAtom); // Ensure it re-fetches and updates.
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[logoutAtom] Current document.cookie after logout and authStatusCoreAtom refresh:`, document.cookie);
      }
      // The authStatusLoadableAtom will reflect the new state.

    } catch (error) {
      console.error('Error during logout API call:', error);
      // Refresh to ensure we have the latest (likely unauthenticated) status.
      set(authStatusCoreAtom); 
      await get(authStatusCoreAtom);
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[logoutAtom] Current document.cookie after logout error and authStatusCoreAtom refresh:`, document.cookie);
      }
    }
    
    // Clear other sensitive data. authStatusCoreAtom is now reset.
    set(baseDataCoreAtom); // Refresh baseDataCoreAtom.
    set(workerStatusCoreAtom); // Refresh workerStatusCoreAtom.
    // The synchronous wrapper atoms will reflect the initial/empty state after their core atoms resolve.
    
    // Reset other relevant atoms to their initial/empty state
    set(searchStateAtom, initialSearchStateValues);
    set(searchResultAtom, { data: [], total: 0, loading: false, error: null });
    set(selectedUnitsAtom, []);
    set(tableColumnsAtom, []); // This will be re-initialized on next load if needed
    set(gettingStartedUIStateAtom, { currentStep: 0, completedSteps: [], isVisible: true });
    set(importStateAtom, { isImporting: false, progress: 0, currentFile: null, errors: [], completed: false, useExplicitDates: false, selectedImportTimeContextIdent: null });
    set(unitCountsAtom, { legalUnits: null, establishmentsWithLegalUnit: null, establishmentsWithoutLegalUnit: null });
    // Note: Similar to login, a hard redirect (`window.location.href = "/login";`
    // in LogoutForm.tsx) will ensure a full app re-initialization.
  }
)

// Base data actions
export const refreshBaseDataAtom = atom(null, (_get, set) => { // get is not used
  set(baseDataCoreAtom);
});

// refreshHasStatisticalUnitsAtomAction is removed.
// To refresh hasStatisticalUnits, refresh baseDataCoreAtom.
// The hasStatisticalUnitsAtom derived atom will update accordingly.

// The refreshWorkerStatusAtom now just resets the core atom.
// The functionName parameter is no longer supported by this simplified refresh.
// SSEConnectionManager will need to adapt to this if it was using functionName.
export const refreshWorkerStatusAtom = atom(null, (get, set, _functionName?: string) => {
  set(workerStatusCoreAtom);
});

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

// These are now defined near their core atoms. This section can be removed or kept as a comment.
// export const baseDataLoadableAtom = loadable(baseDataCoreAtom) // Now defined earlier
// export const authStatusLoadableAtom = loadable(authStatusCoreAtom); // Now defined earlier
// export const workerStatusLoadableAtom = loadable(workerStatusCoreAtom); // Now defined earlier

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
import { SearchAction, type SetQuery } from '@/app/search/search';


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
    if (ftsAction.type === 'set_query' && ftsAction.payload.api_param_name && ftsAction.payload.api_param_value) {
      params.set(ftsAction.payload.api_param_name, ftsAction.payload.api_param_value);
    }
  }

  // 2. Filters from searchState.filters
  Object.entries(searchState.filters).forEach(([appParamName, appParamValue]) => {
    let actionPayloadPart: SetQuery['payload'] | null = null;

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
        const unitTypeAction = unitTypeDeriveStateUpdateFromValues(unitTypeValues);
        if (unitTypeAction.type === 'set_query') actionPayloadPart = unitTypeAction.payload;
        break;
      case INVALID_CODES:
        // appParamValue is ["yes"] or [] from searchState.filters
        // invalidCodesDeriveStateUpdateFromValues expects "yes" or null.
        const invalidCodesValue = Array.isArray(appParamValue) && appParamValue.length > 0 && appParamValue[0] === "yes" 
                                  ? "yes" 
                                  : null;
        const invalidCodesAction = invalidCodesDeriveStateUpdateFromValues(invalidCodesValue);
        if (invalidCodesAction.type === 'set_query') actionPayloadPart = invalidCodesAction.payload;
        break;
      case LEGAL_FORM:
        const ensuredLegalFormValues = Array.isArray(appParamValue)
          ? appParamValue.map(v => v == null ? null : String(v))
          : (appParamValue != null ? [String(appParamValue)] : []);
        const legalFormAction = legalFormDeriveStateUpdateFromValues(ensuredLegalFormValues);
        if (legalFormAction.type === 'set_query') actionPayloadPart = legalFormAction.payload;
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
        const regionAction = regionDeriveStateUpdateFromValues(regionValues);
        if (regionAction.type === 'set_query') actionPayloadPart = regionAction.payload;
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
        const sectorAction = sectorDeriveStateUpdateFromValues(sectorValues);
        if (sectorAction.type === 'set_query') actionPayloadPart = sectorAction.payload;
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
        const activityCategoryAction = activityCategoryDeriveStateUpdateFromValues(activityCategoryValues);
        if (activityCategoryAction.type === 'set_query') actionPayloadPart = activityCategoryAction.payload;
        break;
      case STATUS:
        const ensuredStatusValues = Array.isArray(appParamValue)
          ? appParamValue.map(v => v == null ? null : String(v))
          : (appParamValue != null ? [String(appParamValue)] : []);
        const statusAction = statusDeriveStateUpdateFromValues(ensuredStatusValues);
        if (statusAction.type === 'set_query') actionPayloadPart = statusAction.payload;
        break;
      case UNIT_SIZE:
        const ensuredUnitSizeValues = Array.isArray(appParamValue)
          ? appParamValue.map(v => v == null ? null : String(v))
          : (appParamValue != null ? [String(appParamValue)] : []);
        const unitSizeAction = unitSizeDeriveStateUpdateFromValues(ensuredUnitSizeValues);
        if (unitSizeAction.type === 'set_query') actionPayloadPart = unitSizeAction.payload;
        break;
      case DATA_SOURCE:
        const ensuredDataSourceValues = Array.isArray(appParamValue)
          ? appParamValue.map(v => v == null ? null : String(v))
          : (appParamValue != null ? [String(appParamValue)] : []);
        const dataSourceAction = dataSourceDeriveStateUpdateFromValues(ensuredDataSourceValues, allDataSources);
        if (dataSourceAction.type === 'set_query') actionPayloadPart = dataSourceAction.payload;
        break;
      default:
        const extIdentType = externalIdentTypes.find(type => type.code === appParamName);
        if (extIdentType) {
          const externalIdentAction = externalIdentDeriveStateUpdateFromValues(extIdentType, appParamValue as string | null);
          if (externalIdentAction.type === 'set_query') actionPayloadPart = externalIdentAction.payload;
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
          const statisticalVariableAction = statisticalVariableDeriveStateUpdateFromValue(statDef, parsedStatVarValue);
          if (statisticalVariableAction.type === 'set_query') actionPayloadPart = statisticalVariableAction.payload;
          break;
        }
    }

    if (actionPayloadPart && actionPayloadPart.api_param_name && actionPayloadPart.api_param_value) {
      params.set(actionPayloadPart.api_param_name, actionPayloadPart.api_param_value);
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
  const authLoadable = get(authStatusLoadableAtom);
  const baseDataLoadable = get(baseDataLoadableAtom);
  const baseD = get(baseDataAtom);

  const isLoadingBaseD = baseDataLoadable.state === 'loading';
  const isAuthLoading = authLoadable.state === 'loading';
  
  // If auth is not loading, its "process" is complete for readiness purposes.
  const isAuthProcessComplete = !isAuthLoading; 
  const isAuthenticatedUser = authLoadable.state === 'hasData' && authLoadable.data.isAuthenticated;
  const currentUser = authLoadable.state === 'hasData' ? authLoadable.data.user : null;

  // Base data is considered ready if not loading and has essential data (e.g., stat definitions).
  const isBaseDataProcessComplete = !isLoadingBaseD && baseD.statDefinitions.length > 0;

  // The dashboard is ready to render if auth is complete and base data is loaded.
  const isReadyToRenderDashboard = 
    isAuthProcessComplete &&
    isAuthenticatedUser &&
    isBaseDataProcessComplete;
    
  // isSetupComplete is removed from this global atom. 
  // If a global "is the very basic setup done (e.g. units exist)" flag is needed,
  // it could be derived from baseDataAtom.hasStatisticalUnits, but it won't gate the dashboard rendering here.

  return {
    isLoadingAuth: isAuthLoading,
    isLoadingBaseData: isLoadingBaseD,

    isAuthProcessComplete,
    isAuthenticated: isAuthenticatedUser,
    
    isBaseDataLoaded: isBaseDataProcessComplete,
    // isGettingStartedDataLoaded: true, // Removed, or assume true if not gating

    // isSetupComplete, // Removed from here
    isReadyToRenderDashboard,

    user: currentUser,
  };
});

// ============================================================================
// DERIVED UI STATE ATOMS
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
  
  // Worker Status
  workerStatusAtom,
  workerStatusLoadableAtom,
  workerStatusCoreAtom,
  refreshWorkerStatusAtom,
  
  // Rest Client
  restClientAtom,
  
  // Time Context
  selectedTimeContextAtom,
  
  // Search
  searchStateAtom,
  searchResultAtom,
  performSearchAtom,
  resetSearchStateAtom,
  initialSearchStateValues,
  derivedApiSearchParamsAtom,
  searchPageDataAtom,
  setSearchPageDataAtom,
  
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
  activityCategoryStandardSettingAtomAsync,
  numberOfRegionsAtomAsync,
  numberOfCustomActivityCodesAtomAsync,
  numberOfCustomSectorsAtomAsync,
  numberOfCustomLegalFormsAtomAsync,
  numberOfTotalActivityCodesAtomAsync,
  
  // Import
  importStateAtom,
  unitCountsAtom,
  refreshUnitCountAtom,
  refreshAllUnitCountsAtom,
  setImportSelectedTimeContextAtom,
  setImportUseExplicitDatesAtom,
  createImportJobAtom,
  allPendingJobsStateAtom,
  refreshPendingJobsByPatternAtom,
  
  // Computed
  appReadyAtom,

  // App Initialization State
  authStatusInitiallyCheckedAtom,
  // fetchAndSetAuthStatusAtom, // Removed
  initialAuthCheckDoneEffect,
  searchStateInitializedAtom,

  // Client-side refresh action
  clientSideRefreshAtom,
  
  // Loadable
  baseDataLoadableAtom,
  authStatusLoadableAtom,

  // Derived UI States
  analysisPageVisualStateAtom,
}
