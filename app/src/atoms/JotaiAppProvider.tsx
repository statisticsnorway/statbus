"use client";

/**
 * JotaiAppProvider - Simple replacement for complex Provider nesting
 * 
 * This component replaces all your Context providers with a single Jotai Provider
 * and handles app initialization without complex useEffect chains.
 */

import React, { Suspense, useEffect, ReactNode, useState } from 'react'; // Added useState
import { Provider } from 'jotai';
import { useAtomValue, useSetAtom } from 'jotai';
import { useRouter, usePathname } from 'next/navigation';
import {
  authStatusAtom,
  baseDataAtom,
  restClientAtom,
  refreshBaseDataAtom,
  refreshWorkerStatusAtom,
  workerStatusAtom,
  authStatusLoadableAtom, // Added import
  baseDataLoadableAtom, // Added import
  workerStatusLoadableAtom, // Added import
  // isAuthenticatedAtom, // We'll use authStatusAtom directly for more clarity on loading vs authenticated
  initializeTableColumnsAtom,
  // refreshAllGettingStartedDataAtom, // Removed
  refreshAllUnitCountsAtom,
  fetchAndSetAuthStatusAtom,
  authStatusInitiallyCheckedAtom,
  // gettingStartedDataAtom, // Removed
  activityCategoryStandardSettingAtomAsync, // Import the atom
  numberOfRegionsAtomAsync, // Import the regions atom
} from './index';

// ============================================================================
// APP INITIALIZER - Handles startup logic
// ============================================================================

const AppInitializer = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom); // Renamed to avoid conflict if authLoadable is declared later
  const initialAuthCheckDone = useAtomValue(authStatusInitiallyCheckedAtom);
  const restClient = useAtomValue(restClientAtom);
  const triggerFetchAuthStatus = useSetAtom(fetchAndSetAuthStatusAtom);
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setRestClient = useSetAtom(restClientAtom)
  const initializeTableColumns = useSetAtom(initializeTableColumnsAtom);
  // const refreshGettingStartedData = useSetAtom(refreshAllGettingStartedDataAtom); // Removed
  const refreshUnitCounts = useSetAtom(refreshAllUnitCountsAtom);

  const router = useRouter();
  const pathname = usePathname();
  // const gettingStartedData = useAtomValue(gettingStartedDataAtom); // Removed
  const baseData = useAtomValue(baseDataAtom);
  const activityStandard = useAtomValue(activityCategoryStandardSettingAtomAsync); // Consume the atom
  const numberOfRegions = useAtomValue(numberOfRegionsAtomAsync); // Consume the regions atom
  const [isRedirectingToSetup, setIsRedirectingToSetup] = useState(false); // Flag to prevent double redirect
  
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
    if (restClient && !initialAuthCheckDone && authLoadableValue.state !== 'loading') {
      triggerFetchAuthStatus(); 
    }
  }, [restClient, initialAuthCheckDone, authLoadableValue.state, triggerFetchAuthStatus]);
  
  const [appDataInitialized, setAppDataInitialized] = useState(false);

  // Initialize app data when authenticated, not loading, and client is ready
  useEffect(() => {
    let mounted = true;

    const initializeApp = async () => {
      const currentAuthIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;
      const isAuthCurrentlyLoading = authLoadableValue.state === 'loading';

      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("AppInitializer: Checking conditions for app data initialization...", {
          appDataInitialized,
          initialAuthCheckDone,
          authLoadableState: authLoadableValue.state,
          isAuthenticated: currentAuthIsAuthenticated,
          isRestClientReady: !!restClient,
        });
      }

      // Core conditions: auth must be checked, user authenticated, client ready.
      if (!initialAuthCheckDone || !currentAuthIsAuthenticated || !restClient || isAuthCurrentlyLoading) {
        return;
      }

      // Primary gate: only run once.
      if (appDataInitialized) {
        return;
      }
      
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("AppInitializer: Conditions met, proceeding with app data initialization.");
      }
      setAppDataInitialized(true); // Mark as initialized immediately

      try {
        // Fetch base data
        await refreshBaseData();
        
        // Initialize table columns (depends on base data, e.g., statDefinitions)
        initializeTableColumns();

        // Fetch Import Unit Counts
        refreshUnitCounts();

        // Fetch worker status
        await refreshWorkerStatus();
        
      } catch (error) {
        if (mounted) {
          console.error('AppInitializer: App initialization failed:', error);
          // Consider if appDataInitialized should be reset to false here to allow a retry.
          // For now, keeping it true to prevent loops if an error is persistent.
          // A manual refresh mechanism or more specific error handling might be needed for retries.
        }
      }
    };
    
    initializeApp();
    
    return () => {
      mounted = false;
    };
  }, [
    authLoadableValue, // Depend on the whole loadable value
    restClient,                
    initialAuthCheckDone,      
    appDataInitialized,        
    refreshBaseData,            
    refreshUnitCounts,         
    refreshWorkerStatus,       
    initializeTableColumns     
  ]);

  // "Getting Started" redirect logic is removed.
  // The dashboard will now load if auth and base data are ready.
  // Any "getting started" guidance or conditional rendering will be handled
  // by the dashboard page or its components.

  // Effect for redirecting to setup pages if necessary
  useEffect(() => {
    let mounted = true;
    if (!mounted) return;

    const currentIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;
    const isAuthLoading = authLoadableValue.state === 'loading';

    // Early exit if critical conditions are not met or already redirecting
    if (isRedirectingToSetup || pathname !== '/' || !currentIsAuthenticated || isAuthLoading || !initialAuthCheckDone || !restClient) {
      if (pathname !== '/' || !currentIsAuthenticated ) { 
        setIsRedirectingToSetup(false);
      }
      return;
    }

    // At this point: on '/', authenticated, not loading, client ready, initial auth check done, and not currently in a redirect loop.

    // Check 1: Activity Standard
    // `activityStandard` is the value from `useAtomValue(activityCategoryStandardSettingAtomAsync)`
    if (activityStandard === null) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("AppInitializer: No activity category standard set. Pushing to /getting-started/activity-standard.");
      }
      setIsRedirectingToSetup(true);
      router.push('/getting-started/activity-standard');
      return; 
    }

    // Check 2: Regions (only if activity standard is set)
    // `numberOfRegions` is the value from `useAtomValue(numberOfRegionsAtomAsync)`
    // It will be null if still loading or on error, or a number once resolved.
    if (numberOfRegions === null || numberOfRegions === 0) {
      // If numberOfRegions is null, it might be loading. We redirect if it's explicitly 0 or still null (initial load/error).
      // A more robust check might involve a separate loading state for numberOfRegionsAtomAsync if needed,
      // but for now, this covers "not yet loaded" or "loaded and is zero".
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`AppInitializer: Activity standard is set, but regions count is ${numberOfRegions}. Pushing to /getting-started/upload-regions.`);
      }
      setIsRedirectingToSetup(true);
      router.push('/getting-started/upload-regions');
      return;
    }

    // Check 3: Statistical Units (only if activity standard is set AND regions exist)
    // `baseData.hasStatisticalUnits` and `baseData.statDefinitions.length` are in the dependency array.
    // We check `baseData.statDefinitions.length > 0` as a proxy for `baseData` being loaded.
    if (baseData.statDefinitions.length > 0 && !baseData.hasStatisticalUnits) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("AppInitializer: Activity standard set, regions exist, but no statistical units found. Pushing to /import.");
      }
      setIsRedirectingToSetup(true);
      router.push('/import');
      return;
    }
    
    // If all checks passed (i.e., no redirect was triggered in this run of the effect)
    if (isRedirectingToSetup) {
       setIsRedirectingToSetup(false);
    }
    
    return () => {
      mounted = false;
    };
  }, [
    pathname,
    authLoadableValue, // Depend on the whole loadable value
    initialAuthCheckDone,
    restClient,
    activityStandard,
    numberOfRegions,
    baseData.hasStatisticalUnits, 
    baseData.statDefinitions.length, 
    router,
    isRedirectingToSetup, 
  ]);
  
  return <>{children}</>
}

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom); // Correctly use authStatusLoadableAtom
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  
  useEffect(() => {
    // Connect SSE only if authenticated and not in a loading state
    const currentIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;
    const isAuthLoading = authLoadableValue.state === 'loading';

    if (!currentIsAuthenticated || isAuthLoading) return
    
    let eventSource: EventSource | null = null
    let reconnectTimeout: NodeJS.Timeout | null = null
    let reconnectAttempts = 0
    const maxReconnectAttempts = 5
    
    const connect = () => {
      try {
        // Connect to the specific SSE endpoint for worker status checks
        eventSource = new EventSource('/api/sse/worker-check')
        
        eventSource.onopen = () => {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log('SSE connection established');
          }
          reconnectAttempts = 0
        }
        
        eventSource.onmessage = (event) => {
          try {
            const data = JSON.parse(event.data)
            
            // Handle different SSE message types
            switch (data.type) {
              case 'function_status_change':
                // refreshWorkerStatusAtom no longer takes functionName.
                // A full refresh is triggered. If targeted refresh is critical,
                // workerStatusCoreAtom would need a more complex write function.
                refreshWorkerStatus() 
                break
              case 'worker_status_update':
                refreshWorkerStatus()
                break
              default:
                if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
                  console.log('Unknown SSE message type:', data.type)
                }
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
            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              console.log(`SSE: Scheduling reconnect attempt ${reconnectAttempts + 1} in ${delay / 1000}s.`);
            }
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
  }, [authLoadableValue, refreshWorkerStatus])  // Depend on the whole loadable value
  
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
  const authLoadableValue = useAtomValue(authStatusLoadableAtom); 
  const baseDataLoadableValue = useAtomValue(baseDataLoadableAtom); 
  const workerStatusLoadableValue = useAtomValue(workerStatusLoadableAtom); 

  useEffect(() => {
    setMounted(true);
  }, []);
  
  // Use NEXT_PUBLIC_DEBUG for client-side conditional rendering of devtools
  if (process.env.NEXT_PUBLIC_DEBUG !== 'true' && process.env.NODE_ENV === 'production') {
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
          <strong>Auth State:</strong> {authLoadableValue.state}
        </div>
        {authLoadableValue.state === 'hasData' && (
          <>
            <div>
              <strong>Auth:</strong> {authLoadableValue.data.isAuthenticated ? 'Yes' : 'No'}
            </div>
            <div>
              <strong>User:</strong> {authLoadableValue.data.user?.email || 'None'}
            </div>
          </>
        )}
        {authLoadableValue.state === 'hasError' && <div><strong>Auth Error:</strong> Present</div>}
        <div>
          <strong>Base Data State:</strong> {baseDataLoadableValue.state}
        </div>
        {baseDataLoadableValue.state === 'hasData' && (
          <div>
            <strong>Base Data Loaded:</strong> {baseDataLoadableValue.data.statDefinitions.length} stat definitions
          </div>
        )}
        {baseDataLoadableValue.state === 'hasError' && <div><strong>Base Data Error:</strong> Present</div>}
        <div>
          <strong>Worker Status State:</strong> {workerStatusLoadableValue.state}
        </div>
        {workerStatusLoadableValue.state === 'hasData' && (
          <div>
            <strong>Worker Status:</strong>
            {workerStatusLoadableValue.data.isImporting ? ' Importing' : ''}
            {workerStatusLoadableValue.data.isDerivingUnits ? ' Deriving Units' : ''}
            {workerStatusLoadableValue.data.isDerivingReports ? ' Deriving Reports' : ''}
            {!workerStatusLoadableValue.data.isImporting && !workerStatusLoadableValue.data.isDerivingUnits && !workerStatusLoadableValue.data.isDerivingReports ? ' Idle' : ''}
          </div>
        )}
        {workerStatusLoadableValue.state === 'hasError' && <div><strong>Worker Status Error:</strong> Present</div>}
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
