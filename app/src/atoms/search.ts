"use client";

/**
 * Search, Selection, and Table Column Atoms and Hooks
 *
 * This file contains atoms and hooks related to the main search functionality,
 * including managing search state, results, unit selection, and table column
 * visibility and configuration.
 */

import { atom } from 'jotai'
import { atomWithStorage, selectAtom } from 'jotai/utils'
import { atomEffect } from 'jotai-effect'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useCallback, useEffect, useMemo } from 'react'
import { isEqual } from 'moderndash'

import type { Database, Tables } from '@/lib/database.types'
import type { TableColumn, AdaptableTableColumn, ColumnProfile, SearchResult as ApiSearchResultType, SearchAction, SetQuery } from '../app/search/search.d'
import { getStatisticalUnitsData, getStatisticalUnitsCount } from '../app/search/search-requests'
import {
  fullTextSearchDeriveStateUpdateFromValue,
  unitTypeDeriveStateUpdateFromValues,
  invalidCodesDeriveStateUpdateFromValues,
  legalFormDeriveStateUpdateFromValues,
  regionDeriveStateUpdateFromValues,
  sectorDeriveStateUpdateFromValues,
  activityCategoryDeriveStateUpdateFromValues,
  statusDeriveStateUpdateFromValues,
  domesticDeriveStateUpdateFromValues,
  lastEditByUserDeriveStateUpdateFromValues,
  unitSizeDeriveStateUpdateFromValues,
  dataSourceDeriveStateUpdateFromValues,
  externalIdentDeriveStateUpdateFromValues,
  statisticalVariableDeriveStateUpdateFromValue,
  statisticalVariableParse,
  SEARCH,
  UNIT_TYPE,
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SECTOR,
  ACTIVITY_CATEGORY_PATH,
  STATUS,
  LAST_EDIT_BY_USER,
  UNIT_SIZE,
  DATA_SOURCE,
  DOMESTIC,
} from "../app/search/filters/url-search-params";

import { selectedTimeContextAtom, searchStateInitializedAtom } from './app'
import { restClientAtom } from './rest-client'
import { externalIdentTypesAtom, statDefinitionsAtom, useBaseData } from './base-data'

// ============================================================================
// SEARCH ATOMS - Replace SearchContext
// ============================================================================

// Define initial values for the search state
export type SearchDirection = 'asc' | 'desc' | 'desc.nullslast'

export interface SearchPagination {
  page: number
  pageSize: number
}

export interface SearchSorting {
  field: string
  direction: SearchDirection
}


// By separating pagination into its own atom, we ensure its reference stability.
// It will only update when explicitly changed, and it won't be affected by
// updates to the main searchStateAtom, which was the root cause of the loop.
export const paginationAtom = atom<SearchPagination>({ page: 1, pageSize: 10 });

// Sorting state is also isolated into its own atom to guarantee reference stability.
export const sortingAtom = atom<SearchSorting>({ field: 'name', direction: 'asc' });

// Query state is also isolated into its own atom to guarantee reference stability.
export const queryAtom = atom<string>('');

// Filters state is also isolated into its own atom to guarantee reference stability.
// Note: This does NOT use atomWithStorage. The URL is the single source of
// truth for filter state. Using localStorage here would create a race condition
// where the stored state could overwrite the state derived from the URL on
// navigation.
export const filtersAtom = atom<Record<string, any>>({});

export interface SearchResult {
  data: any[]
  total: number | null  // null means count not yet fetched
  loading: boolean      // true while fetching data
  countLoading: boolean // true while fetching count in background
  error: string | null
}

export const searchResultAtom = atom<SearchResult>({
  data: [],
  total: null,
  loading: false,
  countLoading: false,
  error: null,
})

// Data typically fetched once for the search page (e.g., dropdown options)
export interface SearchPageData {
  allRegions: Tables<"region_used">[];
  allActivityCategories: Tables<"activity_category_used">[];
  allStatuses: Tables<"status">[];
  allUnitSizes: Tables<"unit_size">[];
  allDataSources: Tables<"data_source_used">[];
  allExternalIdentTypes: Tables<"external_ident_type_active">[];
  allLegalForms: Tables<"legal_form_used">[];
  allSectors: Tables<"sector_used">[];
}

export const searchPageDataAtom = atom<SearchPageData>({
  allRegions: [],
  allActivityCategories: [],
  allStatuses: [],
  allUnitSizes: [],
  allDataSources: [],
  allExternalIdentTypes: [],
  allLegalForms: [],
  allSectors: [],
});

// Tracks whether searchPageDataAtom has been populated with lookup data.
// This prevents race conditions where table rows render before lookup data is available.
export const searchPageDataReadyAtom = atom<boolean>(false);

// Action atom to set the search page data (used by server-side props fallback)
export const setSearchPageDataAtom = atom(
  null,
  (get, set, data: SearchPageData) => {
    set(searchPageDataAtom, data);
    // Mark lookup data as ready after setting it
    set(searchPageDataReadyAtom, true);
  }
);

// Action atom to fetch search page data client-side
// This is more reliable than RSC props which can have hydration issues
export const fetchSearchPageDataAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom);

    if (!client) {
      console.warn('[fetchSearchPageDataAtom] REST client not ready');
      return;
    }

    // Check if data is already loaded to avoid redundant fetches
    const currentData = get(searchPageDataAtom);
    if (currentData.allRegions.length > 0) {
      // Data already loaded, just mark as ready
      set(searchPageDataReadyAtom, true);
      return;
    }

    try {
      const [
        { data: regions, error: regionsError },
        { data: activityCategories, error: activityCategoriesError },
        { data: statuses, error: statusesError },
        { data: unitSizes, error: unitSizesError },
        { data: dataSources, error: dataSourcesError },
        { data: externalIdentTypes, error: externalIdentTypesError },
        { data: legalForms, error: legalFormsError },
        { data: sectors, error: sectorsError },
      ] = await Promise.all([
        client.from("region_used").select(),
        client.from("activity_category_used").select(),
        client.from("status").select().filter("enabled", "eq", true),
        client.from("unit_size").select().filter("enabled", "eq", true),
        client.from("data_source_used").select(),
        client.from("external_ident_type_active").select(),
        client.from("legal_form_used").select().not("code", "is", null),
        client.from("sector_used").select(),
      ]);

      // Log any errors
      if (regionsError) console.error('[fetchSearchPageDataAtom] Error fetching regions:', regionsError);
      if (activityCategoriesError) console.error('[fetchSearchPageDataAtom] Error fetching activity categories:', activityCategoriesError);
      if (statusesError) console.error('[fetchSearchPageDataAtom] Error fetching statuses:', statusesError);
      if (unitSizesError) console.error('[fetchSearchPageDataAtom] Error fetching unit sizes:', unitSizesError);
      if (dataSourcesError) console.error('[fetchSearchPageDataAtom] Error fetching data sources:', dataSourcesError);
      if (externalIdentTypesError) console.error('[fetchSearchPageDataAtom] Error fetching external ident types:', externalIdentTypesError);
      if (legalFormsError) console.error('[fetchSearchPageDataAtom] Error fetching legal forms:', legalFormsError);
      if (sectorsError) console.error('[fetchSearchPageDataAtom] Error fetching sectors:', sectorsError);

      const newData = {
        allRegions: regions || [],
        allActivityCategories: activityCategories || [],
        allStatuses: statuses || [],
        allUnitSizes: unitSizes || [],
        allDataSources: dataSources || [],
        allExternalIdentTypes: externalIdentTypes || [],
        allLegalForms: legalForms || [],
        allSectors: sectors || [],
      };
      set(searchPageDataAtom, newData);

      // Only mark as ready if we actually got data. This prevents caching
      // empty results due to auth issues, allowing a retry on next navigation.
      const hasData = newData.allRegions.length > 0 || newData.allActivityCategories.length > 0;
      if (hasData) {
        set(searchPageDataReadyAtom, true);
      } else {
        console.warn('[fetchSearchPageDataAtom] Fetch returned empty data - not marking as ready');
      }
    } catch (error) {
      console.error('[fetchSearchPageDataAtom] Failed to fetch search page data:', error);
    }
  }
);

// Action atom to reset search initialization state.
// Resets both searchStateInitializedAtom and searchPageDataReadyAtom together.
// Use this for testing or when a full re-initialization is needed.
export const resetSearchInitializationAtom = atom(
  null,
  (get, set) => {
    set(searchStateInitializedAtom, false);
    set(searchPageDataReadyAtom, false);
  }
);

// ============================================================================
// SELECTION ATOMS - Replace SelectionContext
// ============================================================================

// Re-export discriminated union types from app/types.d.ts for use in search components
export type { NumericStatAgg, CategoricalStatAgg, ArrayStatAgg, DateStatAgg, StatAgg } from '@/app/types';
import type { StatsSummary, ExternalIdents } from '@/app/types';

export type StatisticalUnit = Omit<Tables<"statistical_unit">, 'external_idents' | 'stats_summary'> & {
  external_idents: ExternalIdents;
  stats_summary: StatsSummary;
};

export const selectedUnitsAtom = atom<StatisticalUnit[]>([])

// Derived atoms for selection operations
// Unstable: returns a new Set object on every read. Kept private.
const selectedUnitIdsAtomUnstable = atom((get) =>
  new Set(get(selectedUnitsAtom).map(unit => `${unit.unit_type}:${unit.unit_id}`))
)
// Stable: uses selectAtom with a deep equality check.
export const selectedUnitIdsAtom = selectAtom(selectedUnitIdsAtomUnstable, (ids) => ids, isEqual);

export const selectionCountAtom = atom((get) => get(selectedUnitsAtom).length);


// ============================================================================
// TABLE COLUMNS ATOMS - Replace TableColumnsContext
// ============================================================================

export const tableColumnsAtom = atomWithStorage<TableColumn[]>(
  "search-columns-state", // Matches COLUMN_LOCALSTORAGE_NAME from original provider
  [] // Initialized as empty; will be populated by an initializer atom/effect
);

// Hydration state atom tracks when tableColumnsAtom has completed hydration
export const tableColumnsHydratedAtom = atom<boolean>(false);

// Hydration effect that detects when atomWithStorage has completed hydration
export const tableColumnsHydrationEffectAtom = atomEffect((get, set) => {
  const storedColumns = get(tableColumnsAtom);
  const isHydrated = get(tableColumnsHydratedAtom);
  
  // Skip if already hydrated
  if (isHydrated) {
    return;
  }
  
  // Check localStorage directly to see if we have persisted data
  const hasStorageData = typeof window !== 'undefined' && 
                         localStorage.getItem('search-columns-state') !== null;
  
  // Mark as hydrated if either:
  // 1. We have data from storage (successful hydration), OR
  // 2. We have no stored data but the atom is stable (confirmed empty)
  const shouldMarkHydrated = hasStorageData || 
                            (!hasStorageData && storedColumns.length === 0);
  
  if (shouldMarkHydrated) {
    set(tableColumnsHydratedAtom, true);
  }
});

// ============================================================================
// ASYNC ACTION ATOMS (Search)
// ============================================================================

// Selection actions
export const toggleSelectionAtom = atom(
  null,
  (get, set, unit: StatisticalUnit) => {
    const currentSelection = get(selectedUnitsAtom);
    const isSelected = currentSelection.some(
      (selected) =>
        selected.unit_id === unit.unit_id &&
        selected.unit_type === unit.unit_type
    );

    if (isSelected) {
      set(
        selectedUnitsAtom,
        currentSelection.filter(
          (selected) =>
            !(
              selected.unit_id === unit.unit_id &&
              selected.unit_type === unit.unit_type
            )
        )
      );
    } else {
      set(selectedUnitsAtom, [...currentSelection, unit]);
    }
  }
);

export const clearSelectionAtom = atom(null, (get, set) => {
  set(selectedUnitsAtom, []);
});

// Search actions
export const performSearchAtom = atom(null, async (get, set) => {
  // Make the writer async
  const postgrestClient = get(restClientAtom);
  const derivedApiParams = get(derivedApiSearchParamsAtom);

  if (!postgrestClient) {
    console.error("performSearchAtom: REST client not available.");
    set(searchResultAtom, {
      data: [],
      total: null,
      loading: false,
      countLoading: false,
      error: "Search client not initialized.",
    });
    return;
  }

  // Set loading state - data loading, count will load after
  set(searchResultAtom, (prev) => ({
    ...prev,
    loading: true,
    countLoading: true,
    error: null,
  }));

  try {
    // Step 1: Fetch data without count (fastest - ~950ms vs ~1400ms with count)
    const dataResponse = await getStatisticalUnitsData(
      postgrestClient,
      derivedApiParams
    );

    // Update with data immediately - table renders now, count shows "counting..."
    set(searchResultAtom, (prev) => ({
      ...prev,
      data: dataResponse.statisticalUnits,
      loading: false,
      // Keep countLoading: true, total stays null or previous value
    }));

    // Step 2: Fetch exact count in background
    try {
      const exactCount = await getStatisticalUnitsCount(
        postgrestClient,
        derivedApiParams
      );

      set(searchResultAtom, (prev) => ({
        ...prev,
        total: exactCount,
        countLoading: false,
      }));
    } catch (countError) {
      console.warn("Failed to fetch search count:", countError);
      set(searchResultAtom, (prev) => ({
        ...prev,
        total: null,
        countLoading: false,
      }));
    }
  } catch (error) {
    console.error("Search failed in performSearchAtom:", error);
    set(searchResultAtom, (prev) => ({
      ...prev,
      loading: false,
      countLoading: false,
      error: error instanceof Error ? error.message : "Search operation failed",
    }));
    throw error; // Let the caller handle it
  }
});

// Atom to reset the search state to its initial values
export const resetPaginationAtom = atom(null, (get, set) => {
  set(paginationAtom, { page: 1, pageSize: 10 });
});

export const resetSortingAtom = atom(null, (get, set) => {
  set(sortingAtom, { field: "name", direction: "asc" });
});

export const resetQueryAtom = atom(null, (get, set) => {
  set(queryAtom, "");
});

export const resetFiltersAtom = atom(null, (get, set) => {
  set(filtersAtom, {});
});

export const resetSearchStateAtom = atom(null, (get, set) => {
  set(resetFiltersAtom); // Explicitly reset filters.
  set(resetPaginationAtom); // Explicitly reset pagination.
  set(resetSortingAtom); // Explicitly reset sorting.
  set(resetQueryAtom); // Explicitly reset query.
});

// ============================================================================
// COMPUTED/DERIVED ATOMS (Search)
// ============================================================================

// Unstable: returns a new array on every read. Kept private.
const availableTableColumnsAtomUnstable = atom<TableColumn[]>((get) => {
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
      }) as AdaptableTableColumn
  );

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
      code: "physical_country_iso_2",
      label: "Country",
      visible: false,
      stat_code: null,
      profiles: ["All"],
    },
    {
      type: "Adaptable",
      code: "domestic",
      label: "Domestic",
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

// Stable: uses selectAtom with a deep equality check.
export const availableTableColumnsAtom = selectAtom(
  availableTableColumnsAtomUnstable,
  (cols) => cols,
  isEqual
);

import { baseDataAtom } from "./base-data";

// Atom to initialize table columns by merging available columns with stored preferences
export const initializeTableColumnsAtom = atom(null, (get, set) => {
  const baseData = get(baseDataAtom);
  const isHydrated = get(tableColumnsHydratedAtom);
  
  // Guard: Do not initialize columns until base data is loaded and free of errors.
  // If baseData has an error, it returns initial empty arrays. Initializing against
  // these empty arrays would destructively wipe the user's column preferences.
  if (baseData.loading || baseData.error) {
    console.log('initializeTableColumnsAtom: Skipping - baseData loading or error', { loading: baseData.loading, error: baseData.error });
    return;
  }

  // NEW GUARD: Wait for hydration to complete before proceeding
  if (!isHydrated) {
    console.log('initializeTableColumnsAtom: Skipping - tableColumnsAtom not yet hydrated');
    return;
  }

  const availableColumns = get(availableTableColumnsAtom);
  
  // Safety Guard: Prevent destructive merge with partial data.
  // If we have no adaptable (statistic) columns but do have static columns,
  // it's likely baseData failed to load stats correctly. Abort to prevent 
  // overwriting preferences with an incomplete column list.
  const hasAdaptableColumns = availableColumns.some(col => col.type === 'Adaptable');
  if (availableColumns.length > 0 && !hasAdaptableColumns) {
    return; // Skip if no adaptable columns detected, likely partial data load
  }
  const storedColumns = get(tableColumnsAtom); // Preferences from localStorage

  if (availableColumns.length === 0 && storedColumns.length === 0) {
    // If no stat definitions yet, and no stored columns, do nothing or set to a minimal default
    // This might occur on initial load before baseData is ready.
    // availableTableColumnsAtom returns a minimal Name column in this case.
    set(tableColumnsAtom, availableColumns);
    return;
  }

  if (storedColumns.length === 0) {
    // Fresh initialization for new users - hydration effect ensures this is safe
    const initColumns = availableColumns.map((col) =>
      col.type === "Adaptable" ? { ...col, visible: true } : col
    );
    set(tableColumnsAtom, initColumns);
    return;
  }

  const mergedColumns = availableColumns.map((availCol) => {
    const storedCol = storedColumns.find(
      (sc) =>
        sc.code === availCol.code &&
        (sc.type === "Always" ||
          (sc.type === "Adaptable" &&
            availCol.type === "Adaptable" &&
            sc.stat_code === availCol.stat_code))
    );
    if (availCol.type === "Adaptable") {
      const resultVisible = storedCol && storedCol.type === "Adaptable"
        ? storedCol.visible
        : availCol.visible;
      
      // Debug: Log when we're falling back to availCol.visible (this is the bug!)
      if (!storedCol && availCol.visible !== false) {
        console.warn('🔥 POTENTIAL BUG: No stored match for', availCol.code, 'falling back to default visible:', availCol.visible);
      }
      
      return {
        ...availCol,
        visible: resultVisible,
      };
    }
    return availCol; // For 'Always' type columns
  });

  const currentColumns = get(tableColumnsAtom);
  // To prevent loops, only set the new columns if they are actually different.
  if (!isEqual(currentColumns, mergedColumns)) {
    set(tableColumnsAtom, mergedColumns);
  }
});

// Unstable: .filter() returns a new array on every read. Kept private.
const visibleTableColumnsAtomUnstable = atom<TableColumn[]>((get) => {
  const allColumns = get(tableColumnsAtom);
  return allColumns.filter(
    (col) => col.type === "Always" || (col.type === "Adaptable" && col.visible)
  );
});

// Stable: uses selectAtom with a deep equality check.
export const visibleTableColumnsAtom = selectAtom(
  visibleTableColumnsAtomUnstable,
  (cols) => cols,
  isEqual
);

// Action atom to toggle a column's visibility
export const toggleTableColumnAtom = atom(
  null,
  (get, set, columnToToggle: TableColumn) => {
    const currentColumns = get(tableColumnsAtom);
    const newColumns = currentColumns.map((col) => {
      if (
        col.type === "Adaptable" &&
        columnToToggle.type === "Adaptable" &&
        col.code === columnToToggle.code &&
        col.stat_code === columnToToggle.stat_code
      ) {
        return { ...col, visible: !col.visible };
      }
      return col;
    });
    set(tableColumnsAtom, newColumns);
  }
);

// Unstable: returns a new object on every read. Kept private.
const columnProfilesAtomUnstable = atom((get) => {
  const currentColumns = get(tableColumnsAtom);
  const profiles: Record<ColumnProfile, TableColumn[]> = {
    Brief: [],
    Regular: [],
    All: [],
  };

  (Object.keys(profiles) as ColumnProfile[]).forEach((profileName) => {
    profiles[profileName] = currentColumns.map((col) => {
      if (col.type === "Adaptable" && col.profiles) {
        return { ...col, visible: col.profiles.includes(profileName) };
      }
      return col; // 'Always' visible columns are part of all profiles as-is
    });
  });
  return profiles;
});

// Stable: uses selectAtom with a deep equality check.
export const columnProfilesAtom = selectAtom(
  columnProfilesAtomUnstable,
  (profiles) => profiles,
  isEqual
);

// Action atom to set column visibility based on a profile
export const setTableColumnProfileAtom = atom(
  null,
  (get, set, profile: ColumnProfile) => {
    const availableColumns = get(availableTableColumnsAtom); // Use defaults to reset structure
    const newColumns = availableColumns.map((col) => {
      if (col.type === "Adaptable" && col.profiles) {
        return { ...col, visible: col.profiles.includes(profile) };
      }
      return col;
    });
    set(tableColumnsAtom, newColumns);
  }
);

// Unstable atom that derives API search parameters. Kept private.
const derivedApiSearchParamsAtomUnstable = atom((get) => {
  const query = get(queryAtom);
  const filters = get(filtersAtom);
  const selectedTimeContext = get(selectedTimeContextAtom);
  const externalIdentTypes = get(externalIdentTypesAtom); // from baseDataAtom
  const statDefinitions = get(statDefinitionsAtom); // from baseDataAtom
  const { allDataSources } = get(searchPageDataAtom); // for dataSourceDeriveStateUpdateFromValues

  const params = new URLSearchParams();

  // 1. Full-text search query
  if (query && query.trim().length > 0) {
    // The SEARCH constant from url-search-params.ts is the app_param_name for FTS.
    // fullTextSearchDeriveStateUpdateFromValue handles generating the api_param_name and api_param_value.
    const ftsAction = fullTextSearchDeriveStateUpdateFromValue(query.trim());
    if (
      ftsAction.type === "set_query" &&
      ftsAction.payload.api_param_name &&
      ftsAction.payload.api_param_value
    ) {
      params.set(
        ftsAction.payload.api_param_name,
        ftsAction.payload.api_param_value
      );
    }
  }

  // 2. Filters from filtersAtom
  Object.entries(filters).forEach(([appParamName, appParamValue]) => {
    let actionPayloadPart: SetQuery["payload"] | null = null;

    switch (appParamName) {
      case UNIT_TYPE:
        let unitTypeValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          unitTypeValues = appParamValue as (string | null)[];
        } else if (
          typeof appParamValue === "string" &&
          appParamValue.trim().length > 0
        ) {
          unitTypeValues = [appParamValue.trim()];
        }
        // If appParamValue is null, undefined, or an empty string, unitTypeValues remains [].
        // unitTypeDeriveStateUpdateFromValues will correctly handle an empty array by setting api_param_value to null.
        const unitTypeAction =
          unitTypeDeriveStateUpdateFromValues(unitTypeValues);
        if (unitTypeAction.type === "set_query")
          actionPayloadPart = unitTypeAction.payload;
        break;
      case INVALID_CODES:
        // appParamValue is ["yes"] or [] from searchState.filters
        // invalidCodesDeriveStateUpdateFromValues expects "yes" or null.
        const invalidCodesValue =
          Array.isArray(appParamValue) &&
          appParamValue.length > 0 &&
          appParamValue[0] === "yes"
            ? "yes"
            : null;
        const invalidCodesAction =
          invalidCodesDeriveStateUpdateFromValues(invalidCodesValue);
        if (invalidCodesAction.type === "set_query")
          actionPayloadPart = invalidCodesAction.payload;
        break;
      case DOMESTIC:
       const domesticValue =
         Array.isArray(appParamValue) && appParamValue.length > 0
           ? (appParamValue[0] as string | null)
           : null;
        const domesticAction =
          domesticDeriveStateUpdateFromValues(domesticValue);
        if (domesticAction.type === "set_query")
          actionPayloadPart = domesticAction.payload;
        break;
      case LEGAL_FORM:
        const ensuredLegalFormValues = Array.isArray(appParamValue)
          ? appParamValue.map((v) => (v == null ? null : String(v)))
          : appParamValue != null
            ? [String(appParamValue)]
            : [];
        const legalFormAction = legalFormDeriveStateUpdateFromValues(
          ensuredLegalFormValues
        );
        if (legalFormAction.type === "set_query")
          actionPayloadPart = legalFormAction.payload;
        break;
      case REGION:
        let regionValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          regionValues = appParamValue as (string | null)[];
        } else if (
          typeof appParamValue === "string" &&
          appParamValue.trim().length > 0
        ) {
          regionValues = [appParamValue.trim()];
        } else if (appParamValue === null) {
          // Handle explicit null for "Missing"
          regionValues = [null];
        }
        const regionAction = regionDeriveStateUpdateFromValues(regionValues);
        if (regionAction.type === "set_query")
          actionPayloadPart = regionAction.payload;
        break;
      case SECTOR:
        let sectorValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          sectorValues = appParamValue as (string | null)[];
        } else if (
          typeof appParamValue === "string" &&
          appParamValue.trim().length > 0
        ) {
          sectorValues = [appParamValue.trim()];
        } else if (appParamValue === null) {
          // Handle explicit null for "Missing"
          sectorValues = [null];
        }
        const sectorAction = sectorDeriveStateUpdateFromValues(sectorValues);
        if (sectorAction.type === "set_query")
          actionPayloadPart = sectorAction.payload;
        break;
      case ACTIVITY_CATEGORY_PATH:
        let activityCategoryValues: (string | null)[] = [];
        if (Array.isArray(appParamValue)) {
          activityCategoryValues = appParamValue as (string | null)[];
        } else if (
          typeof appParamValue === "string" &&
          appParamValue.trim().length > 0
        ) {
          activityCategoryValues = [appParamValue.trim()];
        } else if (appParamValue === null) {
          // Handle explicit null for "Missing"
          activityCategoryValues = [null];
        }
        const activityCategoryAction =
          activityCategoryDeriveStateUpdateFromValues(activityCategoryValues);
        if (activityCategoryAction.type === "set_query")
          actionPayloadPart = activityCategoryAction.payload;
        break;
      case STATUS:
        const ensuredStatusValues = Array.isArray(appParamValue)
          ? appParamValue.map((v) => (v == null ? null : String(v)))
          : appParamValue != null
            ? [String(appParamValue)]
            : [];
        const statusAction =
          statusDeriveStateUpdateFromValues(ensuredStatusValues);
        if (statusAction.type === "set_query")
          actionPayloadPart = statusAction.payload;
        break;
      case UNIT_SIZE:
        const ensuredUnitSizeValues = Array.isArray(appParamValue)
          ? appParamValue.map((v) => (v == null ? null : String(v)))
          : appParamValue != null
            ? [String(appParamValue)]
            : [];
        const unitSizeAction = unitSizeDeriveStateUpdateFromValues(
          ensuredUnitSizeValues
        );
        if (unitSizeAction.type === "set_query")
          actionPayloadPart = unitSizeAction.payload;
        break;
      case LAST_EDIT_BY_USER:
        const ensuredLastEditByUserValues = Array.isArray(appParamValue)
          ? appParamValue.map((v) => (v == null ? null : String(v)))
          : appParamValue != null
            ? [String(appParamValue)]
            : [];
        const lastEditByUserAction = lastEditByUserDeriveStateUpdateFromValues(
          ensuredLastEditByUserValues
        );
        if (lastEditByUserAction.type === "set_query")
          actionPayloadPart = lastEditByUserAction.payload;
        break;
      case DATA_SOURCE:
        const ensuredDataSourceValues = Array.isArray(appParamValue)
          ? appParamValue.map((v) => (v == null ? null : String(v)))
          : appParamValue != null
            ? [String(appParamValue)]
            : [];
        const dataSourceAction = dataSourceDeriveStateUpdateFromValues(
          ensuredDataSourceValues,
          allDataSources
        );
        if (dataSourceAction.type === "set_query")
          actionPayloadPart = dataSourceAction.payload;
        break;
      default:
        const extIdentType = externalIdentTypes.find(
          (type) => type.code === appParamName
        );
        if (extIdentType) {
          const externalIdentAction = externalIdentDeriveStateUpdateFromValues(
            extIdentType,
            appParamValue as string | null
          );
          if (externalIdentAction.type === "set_query")
            actionPayloadPart = externalIdentAction.payload;
          break;
        }
        const statDef = statDefinitions.find(
          (def) => def.code === appParamName
        );
        if (statDef) {
          // Parse the statistical variable value (handles both single and multi-condition)
          const parsedStatVarValue = typeof appParamValue === "string"
            ? statisticalVariableParse(appParamValue)
            : null;
          
          const statisticalVariableAction =
            statisticalVariableDeriveStateUpdateFromValue(
              statDef,
              parsedStatVarValue
            );
          if (statisticalVariableAction.type === "set_query")
            actionPayloadPart = statisticalVariableAction.payload;
          break;
        }
    }

    if (
      actionPayloadPart &&
      actionPayloadPart.api_param_name &&
      actionPayloadPart.api_param_value
    ) {
      // Check if this is a multi-condition filter (marked with MULTI:)
      if (actionPayloadPart.api_param_value.startsWith('MULTI:')) {
        // Extract individual conditions and append them separately
        const conditions = actionPayloadPart.api_param_value
          .substring(6) // Remove 'MULTI:' prefix
          .split('|');
        
        for (const condition of conditions) {
          params.append(actionPayloadPart.api_param_name, condition);
        }
      } else {
        // Single condition - use set() as before
        params.set(
          actionPayloadPart.api_param_name,
          actionPayloadPart.api_param_value
        );
      }
    }
    // If api_param_value is null, the parameter is intentionally not added.
  });

  // 3. Time context
  if (selectedTimeContext && selectedTimeContext.valid_on) {
    params.set("valid_from", `lte.${selectedTimeContext.valid_on}`);
    params.set("valid_to", `gte.${selectedTimeContext.valid_on}`);
  }

  // 4. Sorting
  const searchSorting = get(sortingAtom);
  if (searchSorting.field) {
    const orderName = searchSorting.field;
    const orderDirection = searchSorting.direction;
    const externalIdentType = externalIdentTypes.find(
      (type) => type.code === orderName
    );
    const statDefinition = statDefinitions.find(
      (def) => def.code === orderName
    );

    if (externalIdentType) {
      params.set(
        "order",
        `external_idents->>${orderName}.${orderDirection},unit_type.asc,unit_id.asc`
      );
    } else if (statDefinition) {
      params.set(
        "order",
        `stats_summary->${orderName}->sum.${orderDirection},unit_type.asc,unit_id.asc`
      );
    } else {
      params.set(
        "order",
        `${orderName}.${orderDirection},unit_type.asc,unit_id.asc`
      );
    }
  }

  // 5. Pagination
  const pagination = get(paginationAtom);
  if (pagination.page && pagination.pageSize) {
    const offset = (pagination.page - 1) * pagination.pageSize;
    params.set("limit", `${pagination.pageSize}`);
    params.set("offset", `${offset}`);
  }
  return params;
});

// A stable, memoized version of the API search params atom.
// It uses `selectAtom` to ensure it only returns a new reference when the
// string representation of the params has actually changed. This prevents
// infinite loops in components that depend on this atom.
export const derivedApiSearchParamsAtom = selectAtom(
  derivedApiSearchParamsAtomUnstable,
  (params) => params,
  (a, b) => a.toString() === b.toString()
);

// ============================================================================
// HOOKS (Search, Selection, Table Columns)
// ============================================================================

// Granular hooks for performance. Consumers should prefer these over `useSearch`.

// A lean hook for components that only need to read the pagination value.
export const useSearchPaginationValue = () => {
  return useAtomValue(paginationAtom);
};

export const useSearchPagination = () => {
  const pagination = useSearchPaginationValue();
  const setPagination = useSetAtom(paginationAtom);
  const updatePagination = useCallback(
    (page: number, pageSize?: number) => {
      setPagination((prev) => ({ page, pageSize: pageSize ?? prev.pageSize }));
    },
    [setPagination]
  );
  return useMemo(
    () => ({ pagination, updatePagination }),
    [pagination, updatePagination]
  );
};

export const useSearchSorting = () => {
  const sorting = useAtomValue(sortingAtom);
  const setSorting = useSetAtom(sortingAtom);
  const resetPagination = useSetAtom(resetPaginationAtom);

  const updateSorting = useCallback(
    (field: string, direction: SearchDirection) => {
      setSorting((prev) => {
        if (prev.field === field && prev.direction === direction) return prev;
        // Reset pagination when sorting changes
        resetPagination();
        return { field, direction };
      });
    },
    [setSorting, resetPagination]
  );

  return useMemo(() => ({ sorting, updateSorting }), [sorting, updateSorting]);
};

export const updateQueryAtom = atom(null, (get, set, newQuery: string) => {
  if (get(queryAtom) === newQuery) return;

  // Atomically reset pagination and update the query.
  set(resetPaginationAtom);
  set(queryAtom, newQuery);
});

export const useSearchQuery = () => {
  const query = useAtomValue(queryAtom);
  const updateQuery = useSetAtom(updateQueryAtom);

  const updateSearchQuery = useCallback(
    (newQuery: string) => {
      updateQuery(newQuery);
    },
    [updateQuery]
  );

  return useMemo(
    () => ({ query, updateSearchQuery }),
    [query, updateSearchQuery]
  );
};

export const useSearchFilters = () => {
  const filters = useAtomValue(filtersAtom);
  const setFilters = useSetAtom(filtersAtom);
  const resetPagination = useSetAtom(resetPaginationAtom);

  const updateFilters = useCallback(
    (newFilters: Record<string, any>) => {
      // This is now an atomic update to just the filters.
      // We still need to reset pagination when filters change.
      resetPagination();
      setFilters(newFilters);
    },
    [setFilters, resetPagination]
  );

  return useMemo(() => ({ filters, updateFilters }), [filters, updateFilters]);
};

export const useSearchResult = () => useAtomValue(searchResultAtom);
export const useSearchPageData = () => useAtomValue(searchPageDataAtom);
export const useSearchPageDataReady = () => useAtomValue(searchPageDataReadyAtom);

export const useSelection = () => {
  const selectedUnits = useAtomValue(selectedUnitsAtom);
  // selectedUnitIds is now a Set<string> for efficient lookups
  const selectedUnitIds = useAtomValue(selectedUnitIdsAtom);
  const selectionCount = useAtomValue(selectionCountAtom);
  const toggleSelection = useSetAtom(toggleSelectionAtom);
  const clearSelection = useSetAtom(clearSelectionAtom);

  const isSelected = useCallback(
    (unit: StatisticalUnit) => {
      const compositeId = `${unit.unit_type}:${unit.unit_id}`;
      // Use Set.has() for O(1) average time complexity lookup
      return selectedUnitIds.has(compositeId);
    },
    [selectedUnitIds]
  );

  const toggle = useCallback(
    (unit: StatisticalUnit) => {
      toggleSelection(unit);
    },
    [toggleSelection]
  );

  const clear = useCallback(() => {
    clearSelection();
  }, [clearSelection]);

  return {
    selected: selectedUnits,
    selectedIds: selectedUnitIds,
    count: selectionCount,
    isSelected,
    toggle,
    clear,
  };
};


export const useTableColumnsManager = () => {
  const { loading: baseDataLoading } = useBaseData(); // Add dependency on baseData loading state
  const columns = useAtomValue(tableColumnsAtom);
  const visibleColumns = useAtomValue(visibleTableColumnsAtom);
  const profiles = useAtomValue(columnProfilesAtom);
  const toggleColumn = useSetAtom(toggleTableColumnAtom);
  const setProfile = useSetAtom(setTableColumnProfileAtom);

  // Helper function to generate a suffix for a column
  const columnSuffix = useCallback((column: TableColumn): string => {
    return `${column.code}${column.type === "Adaptable" && column.code === "statistic" && column.stat_code ? `-${column.stat_code}` : ""}`;
  }, []);

  // Helper function to generate a suffix for a unit
  const unitSuffix = useCallback((unit: StatisticalUnit): string => {
    return `${unit.unit_type}-${unit.unit_id}${unit.valid_from ? `-${unit.valid_from}` : ''}`;
  }, []);

  const visibleColumnsSuffix = useMemo(() => {
    return visibleColumns.map(col => columnSuffix(col)).join("-");
  }, [visibleColumns, columnSuffix]);
  
  const headerRowSuffix = visibleColumnsSuffix;

  const headerCellSuffix = useCallback((column: TableColumn): string => {
    return columnSuffix(column);
  }, [columnSuffix]);

  const bodyRowSuffix = useCallback((unit: StatisticalUnit): string => {
    return unitSuffix(unit);
  }, [unitSuffix]);

  const bodyCellSuffix = useCallback((unit: StatisticalUnit, column: TableColumn): string => {
    return `${unitSuffix(unit)}-${columnSuffix(column)}`;
  }, [unitSuffix, columnSuffix]);

  const emptyStaticManager = useMemo(() => ({
    columns: [],
    visibleColumns: [],
    toggleColumn: () => {},
    profiles: { Brief: [], Regular: [], All: [] },
    setProfile: () => {},
    headerRowSuffix: 'loading',
    headerCellSuffix: () => 'loading',
    bodyRowSuffix: (unit: StatisticalUnit) => `${unit.unit_type}-${unit.unit_id}-loading`,
    bodyCellSuffix: (unit: StatisticalUnit, col: TableColumn) => `${unit.unit_type}-${unit.unit_id}-${columnSuffix(col)}-loading`,
  }), [columnSuffix]);

  return useMemo(() => {
    // This is the definitive fix. By guarding the return value of this hook,
    // we ensure it only returns a stable, static object during the initial
    // render when baseData is loading. Once baseData is loaded, it returns the
    // real, dynamic values. This prevents a post-mount change to the hook's
    // return value, which was the trigger for the re-render that caused the loop.
    if (baseDataLoading) {
      return emptyStaticManager;
    }
    return {
      columns,
      visibleColumns,
      toggleColumn,
      profiles,
      setProfile,
      headerRowSuffix,
      headerCellSuffix,
      bodyRowSuffix,
      bodyCellSuffix,
    };
  }, [
    baseDataLoading, // Add loading state to dependency array
    emptyStaticManager,
    columns,
    visibleColumns,
    toggleColumn,
    profiles,
    setProfile,
    headerRowSuffix,
    headerCellSuffix,
    bodyRowSuffix,
    bodyCellSuffix,
  ]);
};
