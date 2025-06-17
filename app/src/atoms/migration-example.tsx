"use client";

/**
 * Migration Example: Before and After
 * 
 * This file shows how to migrate from Context + useEffect patterns to Jotai atoms.
 * It demonstrates the complexity reduction and improved performance you get with Jotai.
 */

import React, { Suspense } from 'react'
import { Provider } from 'jotai'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import {
  useAuth,
  useBaseData,
  useTimeContext,
  useSelection,
  useSearch,
  useAppInitialization,
  useSSEConnection,
} from './hooks'
import { type StatisticalUnit } from "@/atoms/index";

// ============================================================================
// BEFORE: Complex Context Provider Pattern
// ============================================================================

/*
// This is what you had before - complex, hard to maintain, performance issues

const MyComplexComponent = () => {
  // Multiple context hooks with complex dependencies
  const { isAuthenticated, user } = useAuth() // AuthContext
  const { 
    statDefinitions, 
    refreshBaseData, 
    workerStatus,
    refreshWorkerStatus 
  } = useBaseData() // BaseDataContext
  const { selectedTimeContext, setSelectedTimeContext } = useTimeContext() // TimeContext
  const { selected, toggle, clearSelected } = useSelectionContext() // SelectionContext
  const { searchState, modifySearchState, searchResult } = useSearchContext() // SearchContext
  const { tableColumns, updateColumns } = useTableColumns() // TableColumnsContext
  
  // Complex useEffect chains that cause cascading re-renders
  useEffect(() => {
    if (isAuthenticated) {
      refreshBaseData()
    }
  }, [isAuthenticated, refreshBaseData])
  
  useEffect(() => {
    if (isAuthenticated && statDefinitions.length > 0) {
      refreshWorkerStatus()
    }
  }, [isAuthenticated, statDefinitions.length, refreshWorkerStatus])
  
  useEffect(() => {
    // SSE connection setup with complex cleanup
    let eventSource: EventSource | null = null
    
    if (isAuthenticated) {
      eventSource = new EventSource('/api/sse/worker-check') // Use specific endpoint for worker status
      eventSource.onmessage = (event) => {
        // Handle messages and trigger multiple state updates
        const data = JSON.parse(event.data)
        if (data.type === 'worker_status') {
          refreshWorkerStatus(data.functionName)
        }
      }
    }
    
    return () => {
      if (eventSource) {
        eventSource.close()
      }
    }
  }, [isAuthenticated, refreshWorkerStatus])
  
  // More complex state management...
  
  return (
    <div>
      {/ Component JSX /}
    </div>
  )
}

// And this had to be wrapped in multiple providers:
const App = () => (
  <AuthProvider>
    <ClientBaseDataProvider>
      <TimeContextProvider>
        <SearchProvider>
          <SelectionProvider>
            <TableColumnsProvider>
              <GettingStartedProvider>
                <ImportUnitsProvider>
                  <MyComplexComponent />
                </ImportUnitsProvider>
              </GettingStartedProvider>
            </TableColumnsProvider>
          </SelectionProvider>
        </SearchProvider>
      </TimeContextProvider>
    </ClientBaseDataProvider>
  </AuthProvider>
)
*/

// ============================================================================
// AFTER: Simple Jotai Pattern
// ============================================================================

const MySimpleComponent = () => {
  // Simple, clean hooks - no cascading re-renders
  const auth = useAuth()
  const baseData = useBaseData()
  const timeContext = useTimeContext()
  const selection = useSelection()
  const search = useSearch()
  
  // App initialization handled by a single hook
  useAppInitialization()
  
  // SSE connection handled by a single hook for worker status
  useSSEConnection('/api/sse/worker-check')
  
  return (
    <div>
      {auth.loading ? (
        <h1>Auth Status: Loading auth...</h1>
      ) : (
        <h1>Auth Status: {auth.isAuthenticated ? 'Logged In' : 'Logged Out'}</h1>
      )}
      <p>User: {auth.loading ? '...' : auth.user?.email || 'None'}</p>
      <p>Stat Definitions: {baseData.statDefinitions.length}</p>
      <p>Worker Status: {baseData.workerStatus.isImporting ? 'Importing' : 'Idle'}</p>
      <p>Selected Time Context: {timeContext.selectedTimeContext?.ident}</p>
      <p>Selected Units: {selection.count}</p>
      <p>Search Query: {search.searchState.query}</p>
      
      <button onClick={() => auth.login({ email: 'test@example.com', password: 'test' })}>
        Login
      </button>
      <button onClick={() => baseData.refreshBaseData()}>
        Refresh Data
      </button>
      <button onClick={() => search.updateSearchQuery('new query')}>
        Update Search
      </button>
    </div>
  )
}

// And this only needs a single Provider at the root:
const SimpleApp = () => (
  <Provider>
    <Suspense fallback={<div>Loading...</div>}>
      <MySimpleComponent />
    </Suspense>
  </Provider>
)

// ============================================================================
// MIGRATION EXAMPLES: Specific Pattern Replacements
// ============================================================================

// Example 1: Replace TimeContext useEffect pattern
const TimeContextMigrationExample = () => {
  // BEFORE: Complex useEffect in TimeContext
  /*
  const [selectedTimeContext, setSelectedTimeContext] = useState<TimeContextRow | null>(null)
  const { timeContexts, defaultTimeContext } = useBaseData()
  
  useEffect(() => {
    if (!selectedTimeContext && defaultTimeContext) {
      setSelectedTimeContext(defaultTimeContext)
    }
  }, [selectedTimeContext, defaultTimeContext])
  */
  
  // AFTER: Simple hook that handles everything
  const { selectedTimeContext, setSelectedTimeContext, timeContexts, defaultTimeContext } = useTimeContext()
  
  return (
    <select 
      value={selectedTimeContext?.ident || ''} 
      onChange={(e) => {
        const tc = timeContexts.find(tc => tc.ident === e.target.value)
        if (tc) setSelectedTimeContext(tc)
      }}
    >
      {timeContexts.map(tc => (
        <option key={tc.ident} value={tc.ident!}>{tc.valid_on}</option>
      ))}
    </select>
  )
}

// Example 2: Replace Selection Context pattern
const SelectionMigrationExample = () => {
  // BEFORE: Complex context with reducer pattern
  /*
  const [selectedState, dispatch] = useReducer(selectionReducer, { selected: [] })
  
  const toggle = useCallback((unit: StatisticalUnit) => {
    dispatch({ type: 'TOGGLE', unit })
  }, [])
  
  const clearSelected = useCallback(() => {
    dispatch({ type: 'CLEAR' })
  }, [])
  */
  
  // AFTER: Simple hooks
  const selection = useSelection()
  
  const handleUnitClick = (unit: StatisticalUnit) => {
    selection.toggle(unit)
  }
  
  return (
    <div>
      <p>Selected: {selection.count} units</p>
      <button onClick={selection.clear}>Clear Selection</button>
      {/* Your unit list here */}
    </div>
  )
}

// Example 3: Replace Search Context pattern
const SearchMigrationExample = () => {
  // BEFORE: Complex reducer with multiple dispatch calls
  /*
  const [searchState, dispatch] = useReducer(searchReducer, initialSearchState)
  
  const updateQuery = useCallback((query: string) => {
    dispatch({ type: 'UPDATE_QUERY', query })
    dispatch({ type: 'RESET_PAGINATION' })
  }, [])
  
  const updateFilters = useCallback((filters: Record<string, any>) => {
    dispatch({ type: 'UPDATE_FILTERS', filters })
    dispatch({ type: 'RESET_PAGINATION' })
  }, [])
  */
  
  // AFTER: Simple hook calls
  const search = useSearch()
  
  const handleSearch = (query: string) => {
    search.updateSearchQuery(query)
    search.updatePagination(1) // Reset to first page
    search.executeSearch()
  }
  
  return (
    <div>
      <input 
        value={search.searchState.query}
        onChange={(e) => handleSearch(e.target.value)}
        placeholder="Search..."
      />
      <p>Results: {search.searchResult.total}</p>
      {search.searchResult.loading && <p>Loading...</p>}
    </div>
  )
}

// ============================================================================
// PERFORMANCE COMPARISON
// ============================================================================

const PerformanceComparisonExample = () => {
  // With Jotai, only components using specific atoms re-render
  // This component only re-renders when auth status changes
  const isAuthenticated = useAuth().isAuthenticated;
  
  console.log('PerformanceExample re-rendered') // This will only log when auth changes
  
  return (
    <div>
      Status: {isAuthenticated ? 'Authenticated' : 'Not Authenticated'}
    </div>
  )
}

// This component only re-renders when selection changes
const SelectionCountDisplay = () => {
  const selectionCount = useSelection().count
  
  console.log('SelectionCountDisplay re-rendered') // Only when selection changes
  
  return <div>Selected: {selectionCount}</div>
}

// ============================================================================
// ASYNC PATTERNS
// ============================================================================

const AsyncPatternExample = () => {
  // BEFORE: Complex async useEffect patterns
  /*
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [data, setData] = useState<any>(null)
  
  useEffect(() => {
    let cancelled = false
    
    const fetchData = async () => {
      setLoading(true)
      setError(null)
      
      try {
        const result = await someAsyncOperation()
        if (!cancelled) {
          setData(result)
        }
      } catch (err) {
        if (!cancelled) {
          setError(err.message)
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }
    
    fetchData()
    
    return () => {
      cancelled = true
    }
  }, [dependency1, dependency2])
  */
  
  // AFTER: Simple atom-based async
  const baseData = useBaseData()
  
  const handleRefresh = async () => {
    try {
      await baseData.refreshBaseData()
    } catch (error) {
      console.error('Refresh failed:', error)
    }
  }
  
  return (
    <div>
      <button onClick={handleRefresh}>
        Refresh Data
      </button>
      {baseData.workerStatus.loading && <p>Loading...</p>}
      {baseData.workerStatus.error && <p>Error: {baseData.workerStatus.error}</p>}
    </div>
  )
}

// ============================================================================
// EXPORT EXAMPLES
// ============================================================================

export {
  SimpleApp,
  TimeContextMigrationExample,
  SelectionMigrationExample,
  SearchMigrationExample,
  PerformanceComparisonExample,
  AsyncPatternExample,
}

// ============================================================================
// MIGRATION CHECKLIST
// ============================================================================

/*
MIGRATION CHECKLIST:

1. ✅ Install Jotai: `pnpm add jotai`

2. ✅ Create atoms to replace Context state:
   - authStatusAtom replaces AuthContext
   - baseDataAtom replaces BaseDataContext
   - searchStateAtom replaces SearchContext
   - selectedUnitsAtom replaces SelectionContext
   - etc.

3. ✅ Create utility hooks:
   - useAuth() replaces useAuth() + AuthContext
   - useBaseData() replaces useBaseData() + BaseDataContext
   - useSelection() replaces useSelectionContext()
   - etc.

4. 🔄 Migrate components one by one:
   - Replace Context hook calls with atom hooks
   - Remove useEffect chains where possible
   - Simplify state update logic

5. 🔄 Update your app root:
   - Remove nested Context providers
   - Add single Jotai Provider
   - Add Suspense boundaries for async atoms

6. 🔄 Test and refine:
   - Verify no performance regressions
   - Check that state updates work correctly
   - Test SSR compatibility if needed

BENEFITS YOU'LL GET:

✅ Simpler code - no more useEffect chains
✅ Better performance - granular re-renders
✅ Easier testing - atoms can be tested in isolation
✅ Better TypeScript support
✅ Smaller bundle size
✅ Built-in async support with Suspense
✅ Persistent state with atomWithStorage
✅ No provider hell
✅ Easier debugging with devtools support
*/
