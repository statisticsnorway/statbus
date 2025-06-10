/**
 * Core Jotai Atoms - Replacing Context Providers
 * 
 * This file contains the main atoms that replace the complex Context + useEffect patterns.
 * Atoms are globally accessible and only trigger re-renders for components that use them.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable } from 'jotai/utils'
import type { Database, Tables } from '@/lib/database.types'
import type { PostgrestClient } from '@supabase/postgrest-js'

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

export interface TimeContextRow {
  id: number
  year?: number
  // Add other fields as needed
}

// Persistent selected time context
export const selectedTimeContextAtom = atomWithStorage<TimeContextRow | null>(
  'selectedTimeContext',
  null
)

// ============================================================================
// SEARCH ATOMS - Replace SearchContext
// ============================================================================

export interface SearchState {
  query: string
  filters: Record<string, any>
  pagination: {
    page: number
    pageSize: number
  }
  sorting: {
    field: string
    direction: 'asc' | 'desc'
  }
}

export const searchStateAtom = atom<SearchState>({
  query: '',
  filters: {},
  pagination: { page: 1, pageSize: 25 },
  sorting: { field: 'name', direction: 'asc' },
})

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

// ============================================================================
// SELECTION ATOMS - Replace SelectionContext
// ============================================================================

export interface StatisticalUnit {
  id: number
  name: string
  // Add other fields as needed
}

export const selectedUnitsAtom = atom<StatisticalUnit[]>([])

// Derived atoms for selection operations
export const selectedUnitIdsAtom = atom((get) => 
  get(selectedUnitsAtom).map(unit => unit.id)
)

export const selectionCountAtom = atom((get) => get(selectedUnitsAtom).length)

// ============================================================================
// TABLE COLUMNS ATOMS - Replace TableColumnsContext
// ============================================================================

export interface ColumnConfig {
  id: string
  label: string
  visible: boolean
  width?: number
  sortable?: boolean
}

export const tableColumnsAtom = atomWithStorage<ColumnConfig[]>(
  'tableColumns',
  [] // Default columns will be set by the component
)

// ============================================================================
// GETTING STARTED ATOMS - Replace GettingStartedContext
// ============================================================================

export interface GettingStartedState {
  currentStep: number
  completedSteps: number[]
  isVisible: boolean
}

export const gettingStartedAtom = atomWithStorage<GettingStartedState>(
  'gettingStarted',
  {
    currentStep: 0,
    completedSteps: [],
    isVisible: true,
  }
)

// ============================================================================
// IMPORT UNITS ATOMS - Replace ImportUnitsContext
// ============================================================================

export interface ImportState {
  isImporting: boolean
  progress: number
  currentFile: string | null
  errors: string[]
  completed: boolean
}

export const importStateAtom = atom<ImportState>({
  isImporting: false,
  progress: 0,
  currentFile: null,
  errors: [],
  completed: false,
})

// ============================================================================
// ASYNC ACTION ATOMS - For handling side effects
// ============================================================================

// Auth actions
export const loginAtom = atom(
  null,
  async (get, set, credentials: { email: string; password: string }) => {
    try {
      // Import RestClientStore to get authenticated client
      const { getServerRestClient } = await import('@/context/RestClientStore')
      const client = await getServerRestClient()
      
      // Perform login logic here
      // This is where you'd replace your AuthStore.login method
      
      // Update auth status
      set(authStatusAtom, {
        isAuthenticated: true,
        tokenExpiring: false,
        user: null, // Set actual user data
      })
    } catch (error) {
      console.error('Login failed:', error)
      throw error
    }
  }
)

export const logoutAtom = atom(
  null,
  async (get, set) => {
    // Perform logout logic
    set(authStatusAtom, {
      isAuthenticated: false,
      tokenExpiring: false,
      user: null,
    })
    
    // Clear other sensitive data
    set(baseDataAtom, {
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null,
      hasStatisticalUnits: false,
    })
  }
)

// Base data actions
export const refreshBaseDataAtom = atom(
  null,
  async (get, set) => {
    const client = get(restClientAtom)
    if (!client) throw new Error('No client available')
    
    try {
      // Import BaseDataStore for the actual data fetching logic
      const { baseDataStore } = await import('@/context/BaseDataStore')
      const freshData = await baseDataStore.getBaseData(client)
      
      set(baseDataAtom, freshData)
    } catch (error) {
      console.error('Failed to refresh base data:', error)
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
      const { baseDataStore } = await import('@/context/BaseDataStore')
      await baseDataStore.refreshWorkerStatus(functionName)
      
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
    const isSelected = currentSelection.some(selected => selected.id === unit.id)
    
    if (isSelected) {
      set(selectedUnitsAtom, currentSelection.filter(selected => selected.id !== unit.id))
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
    const searchState = get(searchStateAtom)
    const client = get(restClientAtom)
    
    if (!client) throw new Error('No client available')
    
    set(searchResultAtom, prev => ({ ...prev, loading: true, error: null }))
    
    try {
      // Perform actual search logic here
      // This would replace your search context logic
      
      const result = {
        data: [], // Your search results
        total: 0,
        loading: false,
        error: null,
      }
      
      set(searchResultAtom, result)
    } catch (error) {
      set(searchResultAtom, prev => ({
        ...prev,
        loading: false,
        error: error instanceof Error ? error.message : 'Search failed'
      }))
    }
  }
)

// ============================================================================
// LOADABLE ATOMS - For async data with loading states
// ============================================================================

// Loadable versions of async atoms that don't require Suspense
export const baseDataLoadableAtom = loadable(baseDataAtom)
export const authStatusLoadableAtom = loadable(authStatusAtom)
export const workerStatusLoadableAtom = loadable(workerStatusAtom)

// ============================================================================
// COMPUTED/DERIVED ATOMS
// ============================================================================

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
  
  // Selection
  selectedUnitsAtom,
  selectedUnitIdsAtom,
  selectionCountAtom,
  toggleSelectionAtom,
  clearSelectionAtom,
  
  // Table Columns
  tableColumnsAtom,
  
  // Getting Started
  gettingStartedAtom,
  
  // Import
  importStateAtom,
  
  // Computed
  appReadyAtom,
  
  // Loadable
  baseDataLoadableAtom,
  authStatusLoadableAtom,
  workerStatusLoadableAtom,
}