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
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useCallback, useEffect, useMemo } from 'react'
import { isEqual } from 'moderndash'

import type { Database, Tables } from '@/lib/database.types'
import type { TableColumn, AdaptableTableColumn, ColumnProfile, SearchResult as ApiSearchResultType, SearchAction, SetQuery } from '../app/search/search.d'
import { getStatisticalUnits } from '../app/search/search-requests'
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
  SEARCH,
  UNIT_TYPE,
  INVALID_CODES,
  LEGAL_FORM,
  REGION,
  SECTOR,
  ACTIVITY_CATEGORY_PATH,
  STATUS,
  UNIT_SIZE,
  DATA_SOURCE,
} from '../app/search/filters/url-search-params'

import { selectedTimeContextAtom } from './app'
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
      total: 0,
      loading: false,
      error: "Search client not initialized.",
    });
    return;
  }

  set(searchResultAtom, (prev) => ({
    ...prev,
    loading: true,
    error: null,
  }));

  try {
    const response: ApiSearchResultType = await getStatisticalUnits(
      postgrestClient,
      derivedApiParams
    );

    set(searchResultAtom, {
      data: response.statisticalUnits,
      total: response.count,
      loading: false,
      error: null,
    });
  } catch (error) {
    console.error("Search failed in performSearchAtom:", error);
    set(searchResultAtom, (prev) => ({
      ...prev,
      loading: false,
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
  // Optionally, reset search results as well
  set(searchResultAtom, {
    data: [],
    total: 0,
    loading: false,
    error: null,
  });
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
  if (baseData.loading) {
    // Guard: Do not initialize columns until base data (and thus stat definitions) is loaded.
    // This prevents a double-initialization which was the root cause of the re-render loop.
    return;
  }

  const availableColumns = get(availableTableColumnsAtom);
  const storedColumns = get(tableColumnsAtom); // Preferences from localStorage

  if (availableColumns.length === 0 && storedColumns.length === 0) {
    // If no stat definitions yet, and no stored columns, do nothing or set to a minimal default
    // This might occur on initial load before baseData is ready.
    // availableTableColumnsAtom returns a minimal Name column in this case.
    set(tableColumnsAtom, availableColumns);
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
      return {
        ...availCol,
        visible:
          storedCol && storedCol.type === "Adaptable"
            ? storedCol.visible
            : availCol.visible,
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
          let parsedStatVarValue: { operator: string; operand: string } | null =
            null;
          if (
            typeof appParamValue === "string" &&
            appParamValue.includes(":")
          ) {
            const [op, val] = appParamValue.split(":", 2);
            parsedStatVarValue = { operator: op, operand: val };
          } else if (appParamValue === null) {
            // This case means the filter was cleared
            parsedStatVarValue = null;
          }
          // If appParamValue is not a string "op:val" or null, it's an invalid state for stat var,
          // statisticalVariableDeriveStateUpdateFromValue will handle `null` by not setting the param.
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
      params.set(
        actionPayloadPart.api_param_name,
        actionPayloadPart.api_param_value
      );
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
      params.set("order", `external_idents->>${orderName}.${orderDirection}`);
    } else if (statDefinition) {
      params.set("order", `stats_summary->${orderName}->sum.${orderDirection}`);
    } else {
      params.set("order", `${orderName}.${orderDirection}`);
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
