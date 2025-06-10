/**
 * Utility Hooks for Jotai Atoms
 * 
 * These hooks provide convenient ways to interact with atoms and replace
 * the complex useEffect + Context patterns with simpler, more predictable code.
 */

import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useCallback, useEffect, useMemo } from 'react'
import {
  // Auth atoms
  authStatusAtom,
  isAuthenticatedAtom,
  currentUserAtom,
  loginAtom,
  logoutAtom,
  
  // Base data atoms
  baseDataAtom,
  statDefinitionsAtom,
  externalIdentTypesAtom,
  timeContextsAtom,
  defaultTimeContextAtom,
  hasStatisticalUnitsAtom,
  refreshBaseDataAtom,
  
  // Worker status atoms
  workerStatusAtom,
  refreshWorkerStatusAtom,
  
  // Search atoms
  searchStateAtom,
  searchResultAtom,
  performSearchAtom,
  searchPageDataAtom,
  
  // Selection atoms
  selectedUnitsAtom,
  selectedUnitIdsAtom,
  selectionCountAtom,
  toggleSelectionAtom,
  clearSelectionAtom,
  
  // Time context atoms
  selectedTimeContextAtom,
  
  // App state atoms
  appReadyAtom,
  
  // Types
  type StatisticalUnit,
  type User,
  type AuthStatus,
  type BaseData,
  type WorkerStatus,
  type SearchState,
  type SearchDirection,
  type StatMetric, // Export new metric types
  type NumberStatMetric,
  type CountsStatMetric,
  
  // Table Column Atoms & Types
  tableColumnsAtom,
  visibleTableColumnsAtom,
  toggleTableColumnAtom,
  columnProfilesAtom,
  setTableColumnProfileAtom,  
  // Getting Started Atoms & Types
  gettingStartedUIStateAtom,
  type GettingStartedUIState,
  gettingStartedDataAtom,
  type GettingStartedDataState,
  refreshAllGettingStartedDataAtom,
    
  // Import Atoms & Types for ImportManager
  importStateAtom,
  type ImportState,
  unitCountsAtom,
  type UnitCounts,
  refreshUnitCountAtom,
  refreshAllUnitCountsAtom,
  setImportSelectedTimeContextAtom,
  setImportUseExplicitDatesAtom,
  createImportJobAtom,
  allPendingJobsStateAtom, // Renamed
  refreshPendingJobsByPatternAtom, // Renamed
  type AllPendingJobsState, // Renamed
  type PendingJobsData, // Added
} from './index'
import type { TableColumn, AdaptableTableColumn, ColumnProfile } from '../app/search/search.d'; // Added for new table column types
import type { Tables } from '@/lib/database.types'; // For Tables<'statistical_unit'> and Tables<'import_job'>

// ============================================================================
// AUTH HOOKS - Replace useAuth and AuthContext patterns
// ============================================================================

export const useAuth = () => {
  const authStatus = useAtomValue(authStatusAtom)
  const login = useSetAtom(loginAtom)
  const logout = useSetAtom(logoutAtom)
  
  return {
    ...authStatus,
    login,
    logout,
  }
}

export const useUser = (): User | null => {
  return useAtomValue(currentUserAtom)
}

export const useIsAuthenticated = (): boolean => {
  return useAtomValue(isAuthenticatedAtom)
}

// ============================================================================
// BASE DATA HOOKS - Replace BaseDataClient patterns
// ============================================================================

export const useBaseData = () => {
  const baseData = useAtomValue(baseDataAtom)
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const workerStatus = useAtomValue(workerStatusAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  
  return {
    ...baseData,
    workerStatus,
    refreshBaseData: useCallback(async () => {
      try {
        await refreshBaseData()
      } catch (error) {
        console.error('Failed to refresh base data:', error)
        throw error
      }
    }, [refreshBaseData]),
    refreshWorkerStatus: useCallback(async (functionName?: string) => {
      try {
        await refreshWorkerStatus(functionName)
      } catch (error) {
        console.error('Failed to refresh worker status:', error)
        throw error
      }
    }, [refreshWorkerStatus]),
  }
}

export const useStatDefinitions = () => {
  return useAtomValue(statDefinitionsAtom)
}

export const useExternalIdentTypes = () => {
  return useAtomValue(externalIdentTypesAtom)
}

export const useTimeContexts = () => {
  return useAtomValue(timeContextsAtom)
}

export const useDefaultTimeContext = () => {
  return useAtomValue(defaultTimeContextAtom)
}

export const useHasStatisticalUnits = () => {
  return useAtomValue(hasStatisticalUnitsAtom)
}

export const useWorkerStatus = (): WorkerStatus => {
  return useAtomValue(workerStatusAtom)
}

// ============================================================================
// TIME CONTEXT HOOKS - Replace TimeContext patterns
// ============================================================================

export const useTimeContext = () => {
  const [selectedTimeContext, setSelectedTimeContext] = useAtom(selectedTimeContextAtom)
  const timeContexts = useAtomValue(timeContextsAtom)
  const defaultTimeContext = useAtomValue(defaultTimeContextAtom)
  
  // Auto-select default if none selected and default exists
  useEffect(() => {
    if (!selectedTimeContext && defaultTimeContext) {
      setSelectedTimeContext(defaultTimeContext)
    }
  }, [selectedTimeContext, defaultTimeContext, setSelectedTimeContext])
  
  return {
    selectedTimeContext,
    setSelectedTimeContext,
    timeContexts,
    defaultTimeContext,
  }
}

// ============================================================================
// SEARCH HOOKS - Replace SearchContext patterns
// ============================================================================
export const useSearch = () => {
  const [searchState, setSearchState] = useAtom(searchStateAtom)
  const searchResult = useAtomValue(searchResultAtom)
  const performSearch = useSetAtom(performSearchAtom)
  const searchPageData = useAtomValue(searchPageDataAtom)
  
  const updateSearchQuery = useCallback((query: string) => {
    setSearchState(prev => ({ ...prev, query }))
  }, [setSearchState])
  
  const updateFilters = useCallback((filters: Record<string, any>) => {
    setSearchState(prev => ({ ...prev, filters }))
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
    setSearchState(prev => ({
      ...prev,
      sorting: { field, direction }
    }))
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
    // Expose search page data (allRegions, etc.)
    ...searchPageData,
  }
}

// ============================================================================
// SELECTION HOOKS - Replace SelectionContext patterns
// ============================================================================

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
  }
}

// ============================================================================
// APP STATE HOOKS - High-level app state
// ============================================================================

export const useAppReady = () => {
  return useAtomValue(appReadyAtom)
}

// ============================================================================
// LIFECYCLE HOOKS - For initialization and cleanup
// ============================================================================

/**
 * Hook to initialize the app state when component mounts
 * This replaces the complex useEffect chains in your Context providers
 */
export const useAppInitialization = () => {
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const isAuthenticated = useAtomValue(isAuthenticatedAtom)
  const restClient = useAtomValue(restClientAtom) // Get the REST client state
  
  useEffect(() => {
    let mounted = true
    
    const initializeApp = async () => {
      // Ensure both authentication is true and REST client is available
      if (!isAuthenticated) {
        // console.log("useAppInitialization: Not authenticated, skipping data initialization.");
        return;
      }
      if (!restClient) {
        // console.log("useAppInitialization: REST client not yet available, deferring data initialization.");
        return;
      }
      
      console.log("useAppInitialization: Authenticated and REST client ready, proceeding.");
      try {
        // Initialize base data
        await refreshBaseData()
        
        // Initialize worker status
        await refreshWorkerStatus()
        
      } catch (error) {
        if (mounted) {
          console.error('App initialization failed:', error)
        }
      }
    }
    
    initializeApp()
    
    return () => {
      mounted = false
    }
  }, [isAuthenticated, restClient, refreshBaseData, refreshWorkerStatus]) // Add restClient to dependency array
}

/**
 * Hook for SSE connection management
 * This replaces the SSE logic from your BaseDataClient
 */
export const useSSEConnection = (url?: string) => {
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const isAuthenticated = useAtomValue(isAuthenticatedAtom)
  
  useEffect(() => {
    if (!isAuthenticated || !url) return
    
    let eventSource: EventSource | null = null
    let reconnectTimeout: NodeJS.Timeout | null = null
    
    const connect = () => {
      try {
        eventSource = new EventSource(url)
        
        eventSource.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data)
            
            // Handle different SSE message types
            if (data.type === 'function_status_change') {
              refreshWorkerStatus(data.functionName)
            }
          } catch (error) {
            console.error('Failed to parse SSE message:', error)
          }
        }
        
        eventSource.onerror = (error) => {
          console.error('SSE connection error:', error)
          eventSource?.close()
          
          // Reconnect after a delay
          reconnectTimeout = setTimeout(connect, 5000)
        }
        
      } catch (error) {
        console.error('Failed to establish SSE connection:', error)
      }
    }
    
    connect()
    
    return () => {
      if (reconnectTimeout) {
        clearTimeout(reconnectTimeout)
      }
      if (eventSource) {
        eventSource.close()
      }
    }
  }, [isAuthenticated, url, refreshWorkerStatus])
}

// ============================================================================
// DEBUGGING HOOKS
// ============================================================================

/**
 * Hook for debugging atom values in development
 */
export const useAtomDebug = (atomName: string, atomValue: any) => {
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      console.log(`[Atom Debug] ${atomName}:`, atomValue)
    }
  }, [atomName, atomValue])
}

/**
 * Hook to get debug information about the current app state
 */
export const useDebugInfo = () => {
  const authStatus = useAtomValue(authStatusAtom)
  const baseData = useAtomValue(baseDataAtom)
  const workerStatus = useAtomValue(workerStatusAtom)
  const selectedUnits = useAtomValue(selectedUnitsAtom)
  const searchState = useAtomValue(searchStateAtom)
  
  return {
    auth: authStatus,
    baseData: {
      statDefinitionsCount: baseData.statDefinitions.length,
      externalIdentTypesCount: baseData.externalIdentTypes.length,
      statbusUsersCount: baseData.statbusUsers.length,
      timeContextsCount: baseData.timeContexts.length,
      hasDefaultTimeContext: !!baseData.defaultTimeContext,
      hasStatisticalUnits: baseData.hasStatisticalUnits,
    },
    workerStatus,
    selection: {
      count: selectedUnits.length,
      units: selectedUnits,
    },
    search: searchState,
  }
}

// ============================================================================
// TABLE COLUMNS HOOKS - Replace useTableColumns from TableColumnsProvider
// ============================================================================

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

// ============================================================================
// IMPORT UNITS HOOK - Replace useImportUnits from ImportUnitsContext
// ============================================================================

export const useImportManager = () => {
  const currentImportState = useAtomValue(importStateAtom);
  const currentUnitCounts = useAtomValue(unitCountsAtom);
  const allTimeContextsFromBase = useAtomValue(timeContextsAtom); // These are Tables<'time_context'>[]

  const doRefreshUnitCount = useSetAtom(refreshUnitCountAtom);
  const doRefreshAllUnitCounts = useSetAtom(refreshAllUnitCountsAtom);
  const doSetSelectedTimeContextIdent = useSetAtom(setImportSelectedTimeContextAtom);
  const doSetUseExplicitDates = useSetAtom(setImportUseExplicitDatesAtom);
  const doCreateJob = useSetAtom(createImportJobAtom);

  const availableImportTimeContexts = useMemo<Tables<'time_context'>[]>(() => {
    // allTimeContextsFromBase is Tables<'time_context'>[], so it's an array (possibly empty)
    // The check `!allTimeContextsFromBase` is not strictly necessary as an empty array is not falsy,
    // but it doesn't harm. The main thing is that .filter on an empty array is safe.
    if (!allTimeContextsFromBase) return []; 
    // Filter time contexts for import scope, similar to original provider
    return allTimeContextsFromBase.filter(
      tc => tc.scope === "input" || tc.scope === "input_and_query"
    );
  }, [allTimeContextsFromBase]);

  // Removing previous diagnostic log as we have a new lead.
  // The root cause seems to be that baseDataAtom.timeContexts is empty,
  // likely because server-side auth check fails, preventing base data fetch.
  // useEffect(() => {
  //   // Diagnostic log to check the state of time contexts within useImportManager
  //   console.log('[useImportManager Debug] allTimeContextsFromBase (from baseDataAtom):', JSON.stringify(allTimeContextsFromBase, null, 2));
  //   console.log('[useImportManager Debug] availableImportTimeContexts (after filtering for import scope):', JSON.stringify(availableImportTimeContexts, null, 2));
  // }, [allTimeContextsFromBase, availableImportTimeContexts]);

  const selectedImportTimeContextObject = useMemo<Tables<'time_context'> | null>(() => {
    if (!currentImportState.selectedImportTimeContextIdent || !availableImportTimeContexts) return null;
    return availableImportTimeContexts.find(tc => tc.ident === currentImportState.selectedImportTimeContextIdent) || null;
  }, [currentImportState.selectedImportTimeContextIdent, availableImportTimeContexts]);

  // Structure to mimic the 'timeContext' object from the original context
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
  
  const createImportJob = useCallback(async (definitionSlug: string): Promise<Tables<'import_job'> | null> => {
    return await doCreateJob(definitionSlug);
  }, [doCreateJob]);

  return {
    // Unit counts
    counts: currentUnitCounts,
    refreshUnitCount,
    refreshCounts: refreshAllCounts, // Aligning with original context naming
    
    // Time context for import, structured similarly to original context
    timeContext: importTimeContextData,
    setSelectedTimeContext: setSelectedImportTimeContext, // Aligning with original context naming
    setUseExplicitDates: setImportUseExplicitDates,      // Aligning with original context naming
    
    // Import job creation
    createImportJob,

    // Raw import state (for progress, errors, etc.)
    importState: currentImportState,
  };
};

export const usePendingJobsByPattern = (slugPattern: string) => {
  const allJobsState = useAtomValue(allPendingJobsStateAtom);
  const refreshJobsForPattern = useSetAtom(refreshPendingJobsByPatternAtom);

  // Memoize the selection of state for the specific slugPattern
  const state: PendingJobsData = useMemo(() => {
    return allJobsState[slugPattern] || { jobs: [], loading: false, error: null, lastFetched: null };
  }, [allJobsState, slugPattern]);

  // Memoize the refresh function for this specific pattern
  const refreshJobs = useCallback(() => {
    refreshJobsForPattern(slugPattern);
  }, [refreshJobsForPattern, slugPattern]);

  // Effect to fetch jobs if they haven't been fetched for this pattern yet
  useEffect(() => {
    if (state.jobs.length === 0 && !state.loading && state.lastFetched === null) {
      refreshJobs();
    }
  }, [state.jobs.length, state.loading, state.lastFetched, refreshJobs]); // Dependencies ensure this runs when state for this pattern changes

  return {
    ...state, // jobs, loading, error, lastFetched for the specific pattern
    refreshJobs, // The memoized refresh function for this pattern
  };
};

// ============================================================================
// GETTING STARTED HOOKS - Replace useGettingStarted from GettingStartedContext
// ============================================================================

export const useGettingStartedManager = () => {
  const [uiState, setUiState] = useAtom(gettingStartedUIStateAtom);
  const dataState = useAtomValue(gettingStartedDataAtom);
  const refreshAllData = useSetAtom(refreshAllGettingStartedDataAtom);

  const setUIStep = useCallback((step: number) => {
    setUiState(prev => ({ ...prev, currentStep: step }));
  }, [setUiState]);

  const completeUIStep = useCallback((step: number) => {
    setUiState(prev => {
      if (prev.completedSteps.includes(step)) {
        return prev; // Avoid duplicates
      }
      return { ...prev, completedSteps: [...prev.completedSteps, step] };
    });
  }, [setUiState]);

  const toggleUIVisibility = useCallback(() => {
    setUiState(prev => ({ ...prev, isVisible: !prev.isVisible }));
  }, [setUiState]);
  
  const hideUIVisibility = useCallback(() => {
    setUiState(prev => ({ ...prev, isVisible: false }));
  }, [setUiState]);

  const showUIVisibility = useCallback(() => {
    setUiState(prev => ({ ...prev, isVisible: true }));
  }, [setUiState]);


  // Expose individual refresh actions if needed, for now refreshAllData is primary
  // const refreshActivityCategoryStandard = useSetAtom(refreshActivityCategoryStandardAtom);
  // etc.

  return {
    uiState,
    setUIStep,
    completeUIStep,
    toggleUIVisibility,
    hideUIVisibility,
    showUIVisibility,
    dataState,
    refreshAllData,
    // Expose individual refresh functions if components need them
    // e.g., refreshNumberOfRegions: useSetAtom(refreshNumberOfRegionsAtom)
  };
};
