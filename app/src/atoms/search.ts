"use client";

/**
 * Search, Selection, and Table Column Atoms and Hooks
 *
 * This file contains atoms and hooks related to the main search functionality,
 * including managing search state, results, unit selection, and table column
 * visibility and configuration.
 */

import { atom } from 'jotai'
import { atomWithStorage } from 'jotai/utils'
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
import { externalIdentTypesAtom, statDefinitionsAtom } from './base-data'

// ============================================================================
// SEARCH ATOMS - Replace SearchContext
// ============================================================================

// Define initial values for the search state
export const initialSearchStateValues: SearchState = {
  query: '',
  filters: {},
  pagination: { page: 1, pageSize: 10 },
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

export const selectionCountAtom = atom((get) => get(selectedUnitsAtom).length);

export interface EditTarget {
  fieldId: string;
}

export const currentEditAtom = atom<EditTarget | null>(null);

export const setEditTargetAtom = atom(null, (get, set, target: EditTarget) => {
  set(currentEditAtom, target);
});

export const exitEditModeAtom = atom(null, (get, set) => {
  set(currentEditAtom, null);
});

// ============================================================================
// TABLE COLUMNS ATOMS - Replace TableColumnsContext
// ============================================================================

export const tableColumnsAtom = atomWithStorage<TableColumn[]>(
  'search-columns-state', // Matches COLUMN_LOCALSTORAGE_NAME from original provider
  [] // Initialized as empty; will be populated by an initializer atom/effect
)

// ============================================================================
// ASYNC ACTION ATOMS (Search)
// ============================================================================

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
// COMPUTED/DERIVED ATOMS (Search)
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

// ============================================================================
// HOOKS (Search, Selection, Table Columns)
// ============================================================================

export const useSearch = () => {
  const [searchState, setSearchState] = useAtom(searchStateAtom)
  const searchResult = useAtomValue(searchResultAtom)
  const performSearch = useSetAtom(performSearchAtom)
  const searchPageData = useAtomValue(searchPageDataAtom)
  
  const updateSearchQuery = useCallback((query: string) => {
    setSearchState(prev => {
      if (prev.query === query) return prev;
      return { ...prev, query, pagination: { ...prev.pagination, page: 1 } };
    })
  }, [setSearchState])
  
  const updateFilters = useCallback((filters: Record<string, any>) => {
    setSearchState(prev => {
      if (isEqual(prev.filters, filters)) return prev;
      return { ...prev, filters, pagination: { ...prev.pagination, page: 1 } };
    })
  }, [setSearchState])
  
  const updatePagination = useCallback((page: number, pageSize?: number) => {
    setSearchState(prev => ({
      ...prev,
      pagination: {
        page,
        pageSize: pageSize ?? prev.pagination.pageSize,
      }
    }))
  }, [setSearchState])
  

  const updateSorting = useCallback((field: string, direction: SearchDirection) => {
    setSearchState(prev => {
      if (prev.sorting.field === field && prev.sorting.direction === direction) return prev;
      return {
        ...prev,
        sorting: { field, direction },
        pagination: { ...prev.pagination, page: 1 }
      }
    })
  }, [setSearchState])
  
  const executeSearch = useCallback(async () => {
    try {
      await performSearch()
    } catch (error) {
      console.error('Search failed:', error)
      throw error
    }
  }, [performSearch])
  
  return {
    searchState,
    searchResult,
    updateSearchQuery,
    updateFilters,
    updatePagination,
    updateSorting,
    executeSearch,
    ...searchPageData,
  }
}

export const useSelection = () => {
  const selectedUnits = useAtomValue(selectedUnitsAtom)
  // selectedUnitIds is now a Set<string> for efficient lookups
  const selectedUnitIds = useAtomValue(selectedUnitIdsAtom) 
  const selectionCount = useAtomValue(selectionCountAtom)
  const toggleSelection = useSetAtom(toggleSelectionAtom)
  const clearSelection = useSetAtom(clearSelectionAtom)
  
  const isSelected = useCallback((unit: StatisticalUnit) => {
    const compositeId = `${unit.unit_type}:${unit.unit_id}`;
    // Use Set.has() for O(1) average time complexity lookup
    return selectedUnitIds.has(compositeId) 
  }, [selectedUnitIds])
  
  const toggle = useCallback((unit: StatisticalUnit) => {
    toggleSelection(unit)
  }, [toggleSelection])
  
  const clear = useCallback(() => {
    clearSelection()
  }, [clearSelection])
  
  return {
    selected: selectedUnits,
    selectedIds: selectedUnitIds,
    count: selectionCount,
    isSelected,
    toggle,
    clear,
  };
};

export const useEditManager = () => {
  const currentEdit = useAtomValue(currentEditAtom);
  const setEditTarget = useSetAtom(setEditTargetAtom);
  const exitEditMode = useSetAtom(exitEditModeAtom);

  return {
    currentEdit,
    setEditTarget,
    exitEditMode,
  };
};

export const useTableColumnsManager = () => {
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
    // Ensure unit_id and unit_type are present; valid_from might be optional or not always relevant for keying
    // Adjust based on what uniquely identifies a unit for rendering stability.
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
    return `${unitSuffix(unit)}-${visibleColumnsSuffix}`;
  }, [unitSuffix, visibleColumnsSuffix]);

  const bodyCellSuffix = useCallback((unit: StatisticalUnit, column: TableColumn): string => {
    return `${unitSuffix(unit)}-${columnSuffix(column)}`;
  }, [unitSuffix, columnSuffix]);

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
};
