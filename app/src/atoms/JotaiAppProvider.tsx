"use client";

/**
 * JotaiAppProvider - Simple replacement for complex Provider nesting
 * 
 * This component replaces all your Context providers with a single Jotai Provider
 * and handles app initialization without complex useEffect chains.
 */

import React, { Suspense, ReactNode, useState } from 'react';
import { useGuardedEffect } from '@/hooks/use-guarded-effect';
import { Provider, useAtom } from 'jotai';
import { useAtomValue, useSetAtom } from 'jotai';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import {
  clientMountedAtom,
  initialAuthCheckCompletedAtom,
  isTokenManuallyExpiredAtom,
  requiredSetupRedirectAtom,
  selectedTimeContextAtom,
  setupRedirectCheckAtom,
  stateInspectorVisibleAtom,
  redirectRelevantStateAtom,
  eventJournalAtom,
  pageUnloadDetectorEffectAtom,
  logReloadToJournalAtom,
  unifyEventJournalsAtom,
  journalUnificationEffectAtom,
  stateInspectorExpandedAtom,
  addEventJournalEntryAtom,
  useAppReady,
} from './app';
import { restClientAtom } from './rest-client';
import {
  authStatusAtom,
  clientSideRefreshAtom,
  expireAccessTokenAtom,
  isAuthenticatedStrictAtom,
  isUserConsideredAuthenticatedForUIAtom,
  lastKnownPathBeforeAuthChangeAtom,
  authStatusDetailsAtom,
  fetchAuthStatusAtom,
  authMachineAtom,
  isAuthActionInProgressAtom,
  authMachineScribeEffectAtom,
  loginUiMachineScribeEffectAtom,
} from './auth';
import {
  baseDataAtom,
  refreshBaseDataAtom,
} from './base-data';
import {
  activityCategoryStandardSettingAtomAsync,
  numberOfRegionsAtomAsync,
} from './getting-started';
import { loadable } from 'jotai/utils';
import { refreshAllUnitCountsAtom } from './import';
import {
  initializeTableColumnsAtom,
  searchResultAtom,
  selectedUnitsAtom,
} from './search';
import {
  refreshWorkerStatusAtom,
  setWorkerStatusAtom,
  workerStatusAtom,
  type WorkerStatusType,
} from './worker_status';
import { AuthCrossTabSyncer } from './AuthCrossTabSyncer';
import { NavigationManager } from './NavigationManager';
import { navigationMachineAtom, navMachineScribeEffectAtom } from './navigation-machine';

// ============================================================================
// APP INITIALIZER - Handles startup logic
// ============================================================================

const AppInitializer = ({ children }: { children: ReactNode }) => {
  // Activate the state machine scribes and system loggers. These are effects
  // that will run whenever their dependencies change, but only log when the
  // inspector is visible.
  useAtomValue(authMachineScribeEffectAtom);
  useAtomValue(loginUiMachineScribeEffectAtom);
  useAtomValue(navMachineScribeEffectAtom);
  useAtomValue(pageUnloadDetectorEffectAtom);
  useAtomValue(journalUnificationEffectAtom);

  const authStatusDetails = useAtomValue(authStatusDetailsAtom);
  const isAuthenticated = useAtomValue(isUserConsideredAuthenticatedForUIAtom);
  const authStatus = useAtomValue(authStatusAtom);
  const clientSideRefresh = useSetAtom(clientSideRefreshAtom);
  const fetchAuthStatus = useSetAtom(fetchAuthStatusAtom);
  const restClient = useAtomValue(restClientAtom);
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setRestClient = useSetAtom(restClientAtom)
  const initializeTableColumnsAction = useSetAtom(initializeTableColumnsAtom);
  const refreshUnitCounts = useSetAtom(refreshAllUnitCountsAtom);

  // const router = useRouter(); // router.push will be removed from here
  const pathname = usePathname(); // Still needed to gate setup checks
  const baseData = useAtomValue(baseDataAtom);
  const { statDefinitions } = baseData;
  const setupRedirectCheck = useAtomValue(setupRedirectCheckAtom);
  const setLastPath = useSetAtom(lastKnownPathBeforeAuthChangeAtom);
  const setClientMounted = useSetAtom(clientMountedAtom);
  const clientMounted = useAtomValue(clientMountedAtom);
  const logReload = useSetAtom(logReloadToJournalAtom);
  const unifyJournals = useSetAtom(unifyEventJournalsAtom);
  const initialAuthCheckCompleted = useAtomValue(initialAuthCheckCompletedAtom);
  const setInitialAuthCheckCompleted = useSetAtom(initialAuthCheckCompletedAtom);
  const [navState] = useAtom(navigationMachineAtom);
  // isRedirectingToSetup flag is removed as RedirectHandler manages actual navigation.
  
  // Effect to signal that the client has mounted. This helps prevent hydration issues.
  useGuardedEffect(() => {
    setClientMounted(true);
  }, [setClientMounted], 'JotaiAppProvider.tsx:AppInitializer:setClientMounted');

  // Effect to perform one-time actions after the client has mounted.
  useGuardedEffect(() => {
    if (clientMounted) {
      // The unification is now handled declaratively by journalUnificationEffectAtom.
      // We only need to log the reload event here.
      logReload();
    }
  }, [clientMounted, logReload], 'JotaiAppProvider.tsx:AppInitializer:logReload');

  // Effect to establish when the first successful authentication check has completed.
  // This creates a stable "app is ready" signal for other components like RedirectGuard,
  // preventing them from acting on transient, intermediate auth states.
  useGuardedEffect(() => {
    // If we've already completed the check, we're done here.
    if (initialAuthCheckCompleted) {
      return;
    }
    // Once auth status has data for the first time, we mark the initial check as complete.
    // This flag will persist for the lifetime of the app session.
    if (!authStatusDetails.loading) {
      setInitialAuthCheckCompleted(true);
    }
  }, [authStatusDetails.loading, initialAuthCheckCompleted, setInitialAuthCheckCompleted], 'JotaiAppProvider.tsx:AppInitializer:setInitialAuthCheckCompleted');

  // The state machine now handles proactive token refreshes. This useEffect is no longer needed.

  // Initialize REST client
  useGuardedEffect(() => {
    let mounted = true
    const initializeClient = async () => {
      try {
        // Import your existing RestClientStore
        const { getBrowserRestClient } = await import('@/context/RestClientStore')
        const client = await getBrowserRestClient() // This is an async function
        
        if (mounted) {
          if (client) {
            setRestClient(client);
          } else {
            // This case should ideally not happen if getBrowserRestClient throws on failure.
            console.error('AppInitializer: getBrowserRestClient() returned null/undefined without throwing an error. This is unexpected. Setting restClientAtom to null.');
            setRestClient(null); // Explicitly set to null if it wasn't set
          }
        }
      } catch (error) {
        console.error('AppInitializer: CRITICAL - Failed to initialize browser REST client. Setting restClientAtom to null.', error);
        if (mounted) {
          setRestClient(null); // Ensure restClientAtom is null on error
        }
      }
    }
    
    initializeClient()
    
    return () => {
      mounted = false
    }
  }, [setRestClient], 'JotaiAppProvider.tsx:AppInitializer:initializeRestClient')

  const [, sendAuth] = useAtom(authMachineAtom);
  // Effect to inform the auth machine when the REST client is ready.
  useGuardedEffect(() => {
    if (restClient) {
      sendAuth({ type: 'CLIENT_READY', client: restClient });
    } else {
      // This could happen if the client fails to initialize.
      sendAuth({ type: 'CLIENT_UNREADY' });
    }
  }, [restClient, sendAuth], 'JotaiAppProvider.tsx:AppInitializer:sendClientReadyToAuthMachine');
  
  // The useEffect that previously set authStatusInitiallyCheckedAtom is removed.
  // Its logic is now handled by initialAuthCheckDoneEffect from jotai-effect.
  
  const [appDataInitialized, setAppDataInitialized] = useState(false);

  // Initialize app data when authenticated, not loading, and client is ready
  useGuardedEffect(() => {
    let mounted = true;

    const initializeApp = async () => {
      // Core conditions: user must be authenticated, REST client ready, and the
      // initial authentication check must have completed. This prevents race
      // conditions where data is fetched before the token is refreshed.
      if (!isAuthenticated || !restClient || !initialAuthCheckCompleted) {
        return;
      }

      // Primary gate: only run once.
      if (appDataInitialized) {
        return;
      }
      
      setAppDataInitialized(true); // Mark as initialized immediately

      try {
        // Base data will be fetched by baseDataCoreAtom when its dependencies (auth, client) are met.
        
        // Table columns will be initialized by the new useEffect below, reacting to statDefinitions.

        refreshUnitCounts();

        // Worker status will be fetched by workerStatusCoreAtom when its dependencies (auth, client) are met.
        
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
    isAuthenticated,
    restClient,
    appDataInitialized,
    refreshUnitCounts,
    initialAuthCheckCompleted
  ], 'JotaiAppProvider.tsx:AppInitializer:initializeApp');

  // "Getting Started" redirect logic is removed.
  // The dashboard will now load if auth and base data are ready.
  // Any "getting started" guidance or conditional rendering will be handled
  // by the dashboard page or its components.

  // Effect to initialize/update table columns when statDefinitions change
  useGuardedEffect(() => {
    // Only run if statDefinitions have been loaded.
    if (statDefinitions.length > 0) {
      initializeTableColumnsAction();
    }
    // This effect will re-run if statDefinitions array reference changes,
    // or if initializeTableColumnsAction (the atom setter function reference) changes (which is unlikely).
  }, [statDefinitions, initializeTableColumnsAction], 'JotaiAppProvider.tsx:AppInitializer:initializeTableColumns');


  // The guard that showed a loading fallback when navState was not 'idle' has
  // been removed. It was causing a deadlock by unmounting the NavigationManager
  // before it could execute a redirect side-effect. The navigation machine is
  // designed to be fast enough to prevent any significant "flash" of content.
  return <>{children}</>
}

// ============================================================================
// PATH SAVER - Continuously saves the last known authenticated path
// ============================================================================

// The old PathSaver, RedirectGuard, and RedirectHandler components are no longer needed.
// Their logic has been centralized into the NavigationManager and its state machine.

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const isAuthenticated = useAtomValue(isAuthenticatedStrictAtom);
  const refreshInitialWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setWorkerStatus = useSetAtom(setWorkerStatusAtom);
  
  useGuardedEffect(() => {
    // Connect SSE only when the user is in a strict, stable authenticated state.
    // Using the strict `isAuthenticatedAtom` (which is false during token refresh)
    // prevents the connection from being established with an expired token,
    // which would then be immediately cancelled.
    if (!isAuthenticated) return
    
    let eventSource: EventSource | null = null
    let reconnectTimeout: NodeJS.Timeout | null = null
    let reconnectAttempts = 0
    const maxReconnectAttempts = 5
    
    const connect = () => {
      try {
        // Connect to the specific SSE endpoint for worker status checks
        eventSource = new EventSource('/api/sse/worker_status')
        
        eventSource.onopen = () => {
          reconnectAttempts = 0
        }
        
        eventSource.onmessage = (event) => {
          try {
            const payload = JSON.parse(event.data);
            if (payload.type && typeof payload.status === 'boolean') {
              setWorkerStatus({ type: payload.type as WorkerStatusType, status: payload.status });
            } else {
              console.warn("Received SSE message with unexpected payload format:", payload);
            }
          } catch (e) {
            console.error("Failed to parse SSE message data:", event.data, e);
          }
        };

        eventSource.addEventListener('connected', (event) => {
          // Trigger an initial full refresh of worker status upon connection
          refreshInitialWorkerStatus();
        });
        
        eventSource.onerror = (event) => {
          console.error(`SSE connection error. Attempting to reconnect...`, event);
          
          eventSource?.close();
          
          if (reconnectAttempts < maxReconnectAttempts) {
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
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
  }, [isAuthenticated, refreshInitialWorkerStatus, setWorkerStatus], 'JotaiAppProvider.tsx:SSEConnectionManager:connect')
  
  return <>{children}</>
}

// ============================================================================
// PAGE CONTENT GUARD
// ============================================================================

/**
 * PageContentGuardInner contains the core logic that depends on client-side state.
 * It's only rendered after the client has mounted, preventing its hooks from
 * suspending on the server, which is a common cause of hydration errors.
 */
const PageContentGuardInner = ({ children, loadingFallback }: { children: ReactNode, loadingFallback: ReactNode }) => {
  const navState = useAtomValue(navigationMachineAtom);
  const { isLoadingAuth } = useAppReady();

  // The navigation machine is considered to be busy (and thus the UI should wait)
  // if its current state is not tagged as 'stable'. This is a more robust and
  // maintainable approach than checking for specific state names. It prevents
  // content from rendering while the machine is booting, evaluating, or redirecting.
  const isNavigating = !navState.hasTag('stable');

  // By the time this component renders, we are guaranteed to be on the client.
  // We only need to check the application's readiness state.
  if (isNavigating || isLoadingAuth) {
    return <>{loadingFallback}</>;
  }

  return <>{children}</>;
};


/**
 * PageContentGuard acts as a "client-only" boundary. It ensures that the server
 * and the initial client render output the exact same thing (the loading fallback).
 * This prevents hydration mismatches caused by hooks inside child components
 * (like PageContentGuardInner) that might suspend on the server.
 */
const PageContentGuard = ({ children, loadingFallback }: { children: ReactNode, loadingFallback: ReactNode }) => {
  const [isMounted, setIsMounted] = useState(false);

  useGuardedEffect(() => {
    setIsMounted(true);
  }, [], 'JotaiAppProvider.tsx:PageContentGuard:setMounted');

  // On server, and on initial client render, isMounted is false, so we render
  // the fallback. This guarantees the server and client match.
  if (!isMounted) {
    return <>{loadingFallback}</>;
  }

  // After mounting on the client, we render the actual component which can
  // now safely use client-side hooks without causing a hydration mismatch.
  return <PageContentGuardInner loadingFallback={loadingFallback}>{children}</PageContentGuardInner>;
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
  
  useGuardedEffect(() => {
    const handleError = (event: ErrorEvent) => {
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
  }, [], 'JotaiAppProvider.tsx:ErrorBoundary:handleError')
  
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
          <NavigationManager />
          <AuthCrossTabSyncer />
          <PageContentGuard loadingFallback={loadingFallback}>
            {enableSSE ? (
              <SSEConnectionManager>
                {children}
              </SSEConnectionManager>
            ) : (
              children
            )}
          </PageContentGuard>
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
  <StateInspector /> // Optional, can be toggled with Cmd+K
</JotaiAppProvider>
*/

export default JotaiAppProvider
