/**
 * Utility Hooks for Jotai Atoms
 * 
 * These hooks provide convenient ways to interact with atoms and replace
 * the complex useEffect + Context patterns with simpler, more predictable code.
 */

import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useCallback, useEffect } from 'react'
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
  type TimeContextRow,
} from './index'

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
  
  const updateSorting = useCallback((field: string, direction: 'asc' | 'desc') => {
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
  }
}

// ============================================================================
// SELECTION HOOKS - Replace SelectionContext patterns
// ============================================================================

export const useSelection = () => {
  const selectedUnits = useAtomValue(selectedUnitsAtom)
  const selectedUnitIds = useAtomValue(selectedUnitIdsAtom)
  const selectionCount = useAtomValue(selectionCountAtom)
  const toggleSelection = useSetAtom(toggleSelectionAtom)
  const clearSelection = useSetAtom(clearSelectionAtom)
  
  const isSelected = useCallback((unit: StatisticalUnit) => {
    return selectedUnitIds.includes(unit.id)
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
  
  useEffect(() => {
    let mounted = true
    
    const initializeApp = async () => {
      if (!isAuthenticated) return
      
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
  }, [isAuthenticated, refreshBaseData, refreshWorkerStatus])
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