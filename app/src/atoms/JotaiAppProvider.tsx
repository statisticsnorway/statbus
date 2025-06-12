"use client";

/**
 * JotaiAppProvider - Simple replacement for complex Provider nesting
 * 
 * This component replaces all your Context providers with a single Jotai Provider
 * and handles app initialization without complex useEffect chains.
 */

import React, { Suspense, useEffect, ReactNode } from 'react'
import { Provider } from 'jotai'
import { useAtomValue, useSetAtom } from 'jotai'
import {
  authStatusAtom,
  baseDataAtom,
  restClientAtom,
  refreshBaseDataAtom,
  refreshWorkerStatusAtom,
  workerStatusAtom,
  isAuthenticatedAtom,
  initializeTableColumnsAtom,
  refreshAllGettingStartedDataAtom,
  refreshAllUnitCountsAtom,
  fetchAndSetAuthStatusAtom,
  authStatusInitiallyCheckedAtom,
} from './index'

// ============================================================================
// APP INITIALIZER - Handles startup logic
// ============================================================================

const AppInitializer = ({ children }: { children: ReactNode }) => {
  const authStatus = useAtomValue(authStatusAtom); // Use the full authStatus object to access loading state
  const initialAuthCheckDone = useAtomValue(authStatusInitiallyCheckedAtom);
  const restClient = useAtomValue(restClientAtom);
  const triggerFetchAuthStatus = useSetAtom(fetchAndSetAuthStatusAtom);
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setRestClient = useSetAtom(restClientAtom)
  const initializeTableColumns = useSetAtom(initializeTableColumnsAtom);
  const refreshGettingStartedData = useSetAtom(refreshAllGettingStartedDataAtom);
  const refreshUnitCounts = useSetAtom(refreshAllUnitCountsAtom);
  
  // Initialize REST client
  useEffect(() => {
    let mounted = true
    const initializeClient = async () => {
      try {
        // Import your existing RestClientStore
        const { getBrowserRestClient } = await import('@/context/RestClientStore')
        const client = await getBrowserRestClient()
        
        if (mounted) {
          setRestClient(client)
        }
      } catch (error) {
        console.error('AppInitializer: Failed to initialize REST client:', error)
      }
    }
    
    initializeClient()
    
    return () => {
      mounted = false
    }
  }, [setRestClient])

  // Effect to fetch initial authentication status once REST client is ready and auth is not already loading
  useEffect(() => {
    if (restClient && !initialAuthCheckDone && !authStatus.loading) {
      triggerFetchAuthStatus(); 
    }
  }, [restClient, initialAuthCheckDone, authStatus.loading, triggerFetchAuthStatus]);
  
  // Initialize app data when authenticated, not loading, and client is ready
  useEffect(() => {
    let mounted = true
    
    const initializeApp = async () => {
      // Ensure initial auth check is done, auth is not loading, and user is authenticated
      if (!initialAuthCheckDone || authStatus.loading || !authStatus.isAuthenticated) {
        return;
      }
      if (!restClient) {
        return;
      }
      
      try {
        // Fetch base data
        await refreshBaseData()
        
        // Initialize table columns (depends on base data, e.g., statDefinitions)
        initializeTableColumns();

        // Fetch "Getting Started" data
        refreshGettingStartedData();

        // Fetch Import Unit Counts
        refreshUnitCounts();

        // Pending jobs are now fetched by their respective pages, not globally on init.

        // Fetch worker status
        await refreshWorkerStatus()
        
      } catch (error) {
        if (mounted) {
          console.error('AppInitializer: App initialization failed:', error)
        }
      }
    }
    
    initializeApp()
    
    return () => {
      mounted = false
    }
  }, [authStatus.isAuthenticated, authStatus.loading, restClient, initialAuthCheckDone, refreshBaseData, refreshWorkerStatus, initializeTableColumns, refreshGettingStartedData, refreshUnitCounts])
  
  return <>{children}</>
}

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const authStatus = useAtomValue(authStatusAtom); // Use full authStatus to access loading state
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  
  useEffect(() => {
    // Connect SSE only if authenticated and not in a loading state
    if (!authStatus.isAuthenticated || authStatus.loading) return
    
    let eventSource: EventSource | null = null
    let reconnectTimeout: NodeJS.Timeout | null = null
    let reconnectAttempts = 0
    const maxReconnectAttempts = 5
    
    const connect = () => {
      try {
        // Connect to the specific SSE endpoint for worker status checks
        eventSource = new EventSource('/api/sse/worker-check')
        
        eventSource.onopen = () => {
          // console.log('SSE connection established')
          reconnectAttempts = 0
        }
        
        eventSource.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data)
            
            // Handle different SSE message types
            switch (data.type) {
              case 'function_status_change':
                refreshWorkerStatus(data.functionName)
                break
              case 'worker_status_update':
                refreshWorkerStatus()
                break
              default:
                console.log('Unknown SSE message type:', data.type)
            }
          } catch (error) {
            console.error('Failed to parse SSE message:', error)
          }
        }
        
        eventSource.onerror = (event) => { // The 'error' is an Event object
          // Log the type of event and the readyState of the EventSource
          const readyState = eventSource?.readyState;
          let readyStateString = "UNKNOWN";
          if (readyState === EventSource.CONNECTING) readyStateString = "CONNECTING";
          else if (readyState === EventSource.OPEN) readyStateString = "OPEN";
          else if (readyState === EventSource.CLOSED) readyStateString = "CLOSED";

          console.error(`SSE connection error. Event type: ${event.type}, EventSource readyState: ${readyStateString}. Attempting to reconnect...`, event);
          
          eventSource?.close()
          
          // Implement exponential backoff for reconnection
          if (reconnectAttempts < maxReconnectAttempts) {
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000); // Max 30 seconds
            console.log(`SSE: Scheduling reconnect attempt ${reconnectAttempts + 1} in ${delay / 1000}s.`);
            reconnectTimeout = setTimeout(() => {
              reconnectAttempts++;
              connect();
            }, delay);
          } else {
            console.error(`SSE: Max reconnect attempts (${maxReconnectAttempts}) reached. Giving up.`);
          }
        }
        
      } catch (error) {
        console.error('SSE: Failed to establish initial SSE connection:', error);
        // Optionally, you could try to schedule a reconnect here too if initial connect fails
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
  }, [authStatus.isAuthenticated, authStatus.loading, refreshWorkerStatus])
  
  return <>{children}</>
}

// ============================================================================
// LOADING FALLBACK COMPONENTS
// ============================================================================

const AppLoadingFallback = () => (
  <div className="flex items-center justify-center min-h-screen">
    <div className="text-center">
      <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-gray-900 mx-auto"></div>
      <p className="mt-4 text-lg text-gray-600">Loading application...</p>
    </div>
  </div>
)

const ErrorBoundary = ({ children }: { children: ReactNode }) => {
  const [hasError, setHasError] = React.useState(false)
  
  useEffect(() => {
    const handleError = (event: ErrorEvent) => {
      // Log more details from the ErrorEvent
      console.error('Global error caught by ErrorBoundary:', {
        message: event.message,
        filename: event.filename,
        lineno: event.lineno,
        colno: event.colno,
        errorObject: event.error, // This often contains the actual Error object
      });
      setHasError(true)
    }
    
    window.addEventListener('error', handleError)
    return () => window.removeEventListener('error', handleError)
  }, [])
  
  if (hasError) {
    return (
      <div className="flex items-center justify-center min-h-screen">
        <div className="text-center">
          <h1 className="text-2xl font-bold text-red-600 mb-4">Something went wrong</h1>
          <p className="text-gray-600 mb-4">Please refresh the page and try again.</p>
          <button 
            onClick={() => window.location.reload()}
            className="px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600"
          >
            Refresh Page
          </button>
        </div>
      </div>
    )
  }
  
  return <>{children}</>
}

// ============================================================================
// AUTH STATUS HANDLER
// ============================================================================

const AuthStatusHandler = ({ children }: { children: ReactNode }) => {
  const authStatus = useAtomValue(authStatusAtom)
  
  // You can add redirect logic here if needed
  // For example, redirect to login if not authenticated
  /*
  useEffect(() => {
    if (!authStatus.isAuthenticated) {
      // Redirect to login page
      window.location.href = '/login'
    }
  }, [authStatus.isAuthenticated])
  */
  
  return <>{children}</>
}

// ============================================================================
// MAIN PROVIDER COMPONENT
// ============================================================================

interface JotaiAppProviderProps {
  children: ReactNode
  enableSSE?: boolean
  enableErrorBoundary?: boolean
  loadingFallback?: ReactNode
}

export const JotaiAppProvider = ({ 
  children, 
  enableSSE = true,
  enableErrorBoundary = true,
  loadingFallback = <AppLoadingFallback />
}: JotaiAppProviderProps) => {
  const content = (
    <Provider>
      <Suspense fallback={loadingFallback}>
        <AppInitializer>
          <AuthStatusHandler>
            {enableSSE ? (
              <SSEConnectionManager>
                {children}
              </SSEConnectionManager>
            ) : (
              children
            )}
          </AuthStatusHandler>
        </AppInitializer>
      </Suspense>
    </Provider>
  )
  
  return enableErrorBoundary ? (
    <ErrorBoundary>
      {content}
    </ErrorBoundary>
  ) : (
    content
  )
}

// ============================================================================
// HOOK FOR MANUAL INITIALIZATION
// ============================================================================

/**
 * Hook for components that need to trigger manual initialization
 * Useful for testing or special cases
 */
export const useManualInit = () => {
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setRestClient = useSetAtom(restClientAtom)
  
  const initializeApp = async () => {
    try {
      // Initialize REST client
      const { getBrowserRestClient } = await import('@/context/RestClientStore')
      const client = await getBrowserRestClient()
      setRestClient(client)
      
      // Fetch base data
      await refreshBaseData()
      
      // Fetch worker status
      await refreshWorkerStatus()
      
      return true
    } catch (error) {
      console.error('Manual initialization failed:', error)
      return false
    }
  }
  
  return { initializeApp }
}

// ============================================================================
// DEVELOPMENT TOOLS
// ============================================================================

/**
 * Development component that shows current atom states
 * Only renders in development mode
 */
export const AtomDevtools = () => {
  const [mounted, setMounted] = React.useState(false);
  const authStatus = useAtomValue(authStatusAtom)
  const baseData = useAtomValue(baseDataAtom)
  const workerStatus = useAtomValue(workerStatusAtom)

  useEffect(() => {
    setMounted(true);
  }, []);
  
  if (process.env.NODE_ENV !== 'development') {
    return null
  }

  // Render a placeholder or nothing until mounted to avoid hydration mismatch for dynamic content
  if (!mounted) {
    return (
      <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-4 rounded-lg text-xs max-w-md">
        <h3 className="font-bold mb-2">Atom States (Dev Only)</h3>
        <div>Loading devtools...</div>
      </div>
    );
  }
  
  return (
    <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-4 rounded-lg text-xs max-w-md max-h-96 overflow-auto">
      <h3 className="font-bold mb-2">Atom States (Dev Only)</h3>
      <div className="space-y-2">
        <div>
          <strong>Auth:</strong> {authStatus.isAuthenticated ? 'Yes' : 'No'}
        </div>
        <div>
          <strong>User:</strong> {authStatus.user?.email || 'None'}
        </div>
        <div>
          <strong>Base Data:</strong> {baseData.statDefinitions.length} stat definitions
        </div>
        <div>
          <strong>Worker Status:</strong> 
          {workerStatus.isImporting ? ' Importing' : ''}
          {workerStatus.isDerivingUnits ? ' Deriving Units' : ''}
          {workerStatus.isDerivingReports ? ' Deriving Reports' : ''}
          {!workerStatus.isImporting && !workerStatus.isDerivingUnits && !workerStatus.isDerivingReports ? ' Idle' : ''}
        </div>
      </div>
    </div>
  )
}

// ============================================================================
// USAGE EXAMPLE
// ============================================================================

/*
// Replace your complex provider nesting with this:

// Before:
<AuthProvider>
  <ClientBaseDataProvider>
    <TimeContextProvider>
      <SearchProvider>
        <SelectionProvider>
          <TableColumnsProvider>
            <GettingStartedProvider>
              <ImportUnitsProvider>
                <YourApp />
              </ImportUnitsProvider>
            </GettingStartedProvider>
          </TableColumnsProvider>
        </SelectionProvider>
      </SearchProvider>
    </TimeContextProvider>
  </ClientBaseDataProvider>
</AuthProvider>

// After:
<JotaiAppProvider>
  <YourApp />
  <AtomDevtools /> // Optional, only in development
</JotaiAppProvider>
*/

export default JotaiAppProvider
