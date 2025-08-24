"use client";

/**
 * JotaiAppProvider - Simple replacement for complex Provider nesting
 * 
 * This component replaces all your Context providers with a single Jotai Provider
 * and handles app initialization without complex useEffect chains.
 */

import React, { Suspense, useEffect, ReactNode, useState } from 'react';
import { Provider, useAtom } from 'jotai'; // Added useAtom here
import { useAtomValue, useSetAtom } from 'jotai';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
import {
  clientMountedAtom,
  pendingRedirectAtom,
  requiredSetupRedirectAtom,
  restClientAtom,
  restClientAtom as importedRestClientAtom, // Alias to avoid conflict with local restClient variable
  stateInspectorVisibleAtom,
} from './app';
import {
  authStatusAtom,
  authStatusLoadableAtom,
  clientSideRefreshAtom,
  lastKnownPathBeforeAuthChangeAtom,
  loginActionInProgressAtom,
} from './auth';
import {
  baseDataAtom,
  baseDataLoadableAtom,
  refreshBaseDataAtom,
} from './base-data';
import {
  activityCategoryStandardSettingAtomAsync,
  numberOfRegionsAtomAsync,
} from './getting-started';
import { refreshAllUnitCountsAtom } from './import';
import { initializeTableColumnsAtom } from './search';
import {
  refreshWorkerStatusAtom,
  setWorkerStatusAtom,
  workerStatusAtom,
  type WorkerStatusType,
} from './worker_status';
import { AuthCrossTabSyncer } from './AuthCrossTabSyncer'; // Import the new syncer

// ============================================================================
// APP INITIALIZER - Handles startup logic
// ============================================================================

const AppInitializer = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const authStatus = useAtomValue(authStatusAtom);
  const clientSideRefresh = useSetAtom(clientSideRefreshAtom);
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
  const activityStandard = useAtomValue(activityCategoryStandardSettingAtomAsync);
  const numberOfRegions = useAtomValue(numberOfRegionsAtomAsync);
  const setRequiredSetupRedirect = useSetAtom(requiredSetupRedirectAtom);
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const setLastPath = useSetAtom(lastKnownPathBeforeAuthChangeAtom);
  const setClientMounted = useSetAtom(clientMountedAtom);
  // isRedirectingToSetup flag is removed as RedirectHandler manages actual navigation.
  
  // Effect to signal that the client has mounted. This helps prevent hydration issues.
  useEffect(() => {
    setClientMounted(true);
  }, [setClientMounted]);

  // Effect to handle proactive token refresh when an access token expires
  useEffect(() => {
    if (authStatus.expired_access_token_call_refresh) {
      clientSideRefresh();
    }
  }, [authStatus.expired_access_token_call_refresh, clientSideRefresh]);

  // Initialize REST client
  useEffect(() => {
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
  }, [setRestClient])

  // Effect to fetch initial authentication status once REST client is ready and auth is not already loading
  // This effect is removed. authStatusCoreAtom will fetch when restClient is ready due to its dependency.
  
  // The useEffect that previously set authStatusInitiallyCheckedAtom is removed.
  // Its logic is now handled by initialAuthCheckDoneEffect from jotai-effect.
  
  const [appDataInitialized, setAppDataInitialized] = useState(false);

  // Initialize app data when authenticated, not loading, and client is ready
  useEffect(() => {
    let mounted = true;

    const initializeApp = async () => {
      const currentAuthIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;

      // Core conditions: user must be authenticated and REST client ready.
      // currentAuthIsAuthenticated is false if auth state is loading or has an error.
      if (!currentAuthIsAuthenticated || !restClient) {
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
    authLoadableValue,
    restClient,
    appDataInitialized,
    refreshUnitCounts
  ]);

  // "Getting Started" redirect logic is removed.
  // The dashboard will now load if auth and base data are ready.
  // Any "getting started" guidance or conditional rendering will be handled
  // by the dashboard page or its components.

  // Effect to initialize/update table columns when statDefinitions change
  useEffect(() => {
    // Only run if statDefinitions have been loaded.
    if (statDefinitions.length > 0) {
      initializeTableColumnsAction();
    }
    // This effect will re-run if statDefinitions array reference changes,
    // or if initializeTableColumnsAction (the atom setter function reference) changes (which is unlikely).
  }, [statDefinitions, initializeTableColumnsAction]);


  // Effect for redirecting to setup pages if necessary
  useEffect(() => {
    const currentIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;

    // Setup checks are only relevant if on the dashboard ('/') and authenticated.
    // The auth check must be complete (which is implicit in currentIsAuthenticated)
    // and the REST client must be ready.
    if (pathname !== '/' || !currentIsAuthenticated || !restClient) {
      // If not in a state where setup redirects are relevant, ensure no setup redirect is pending.
      setRequiredSetupRedirect(null);
      return;
    }

    // At this point: on '/', authenticated, not loading, client ready, initial auth check done.
    let targetSetupPath: string | null = null;

    if (activityStandard === null) {
      targetSetupPath = '/getting-started/activity-standard';
    } else if (numberOfRegions === null || numberOfRegions === 0) {
      targetSetupPath = '/getting-started/upload-regions';
    } else if (baseData.statDefinitions.length > 0 && !baseData.hasStatisticalUnits) {
      targetSetupPath = '/import';
    }

    // Set or clear the setup redirect atom based on checks.
    setRequiredSetupRedirect(targetSetupPath);
  }, [
    pathname,
    authLoadableValue,
    restClient,
    activityStandard,
    numberOfRegions,
    baseData.hasStatisticalUnits,
    baseData.statDefinitions.length,
    setRequiredSetupRedirect
  ]);
  
  return <>{children}</>
}

// ============================================================================
// PATH SAVER - Continuously saves the last known authenticated path
// ============================================================================

const PathSaver = () => {
  const pathname = usePathname();
  const search = useSearchParams().toString();
  const setLastPath = useSetAtom(lastKnownPathBeforeAuthChangeAtom);
  const authStatus = useAtomValue(authStatusAtom);
  const pendingRedirect = useAtomValue(pendingRedirectAtom);

  useEffect(() => {
    // Do not save path if a redirect is pending. This prevents an intermediate
    // page (like '/') during a redirect loop from overwriting the original path.
    if (pendingRedirect) {
      return;
    }

    // Continuously save the current path to sessionStorage while the user is authenticated.
    // This ensures that if a logout event occurs, the last known good path is already stored.
    if (authStatus.isAuthenticated) {
      const fullPath = `${pathname}${search ? `?${search}` : ''}`;
      // Don't save the login page itself as a restoration target.
      if (pathname !== '/login') {
        // If on the root path, ensure we save exactly "/" as the default restoration path.
        if (pathname === '/') {
          setLastPath('/');
        } else {
          setLastPath(fullPath);
        }
      }
    }
  }, [pathname, search, authStatus.isAuthenticated, setLastPath, pendingRedirect]);

  return null;
};

// ============================================================================
// REDIRECT GUARD - Handles redirecting unauthenticated users to login
// ============================================================================

const RedirectGuard = () => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const pathname = usePathname();
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const [pendingRedirectValue] = useAtom(pendingRedirectAtom);

  useEffect(() => {
    // Wait until the initial authentication check is complete.
    if (authLoadableValue.state === 'loading') {
      return;
    }

    // Do not trigger a new redirect if one is already pending.
    // This helps prevent loops if auth state flaps during navigation.
    if (pendingRedirectValue) {
      return;
    }

    const currentIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;
    const canRefresh = authLoadableValue.state === 'hasData' && authLoadableValue.data.expired_access_token_call_refresh;
    const publicPaths = ['/login'];

    if (!currentIsAuthenticated && !canRefresh && !publicPaths.some(p => pathname.startsWith(p))) {
      // The path has already been saved by PathSaver. Just trigger the redirect.
      setPendingRedirect('/login');
    }
  }, [pathname, authLoadableValue, setPendingRedirect, pendingRedirectValue]);

  return null;
};

// ============================================================================
// REDIRECT HANDLER - Handles programmatic redirects
// ============================================================================

const RedirectHandler = () => {
  const [explicitRedirect, setExplicitRedirect] = useAtom(pendingRedirectAtom);
  const [setupRedirect, setSetupRedirect] = useAtom(requiredSetupRedirectAtom);
  const [loginActionIsActive, setLoginActionInProgress] = useAtom(loginActionInProgressAtom);
  const router = useRouter();
  const pathname = usePathname();

  // Determine the single desired target path. Explicit redirects take priority.
  const targetPath = explicitRedirect || setupRedirect;

  // A single, consolidated effect to handle navigation and state clearing.
  useEffect(() => {
    if (!targetPath) {
      return;
    }

    const targetPathname = targetPath.split('?')[0];

    // If we are not at the target destination, navigate.
    if (targetPathname !== pathname) {
      router.push(targetPath);
    } else {
      // If we are at the target destination, clear the state that caused the redirect.
      if (explicitRedirect) {
        setExplicitRedirect(null);
        if (loginActionIsActive) {
          setLoginActionInProgress(false);
        }
      }
      if (setupRedirect) {
        setSetupRedirect(null);
      }
    }
  }, [targetPath, pathname, router, explicitRedirect, setupRedirect, loginActionIsActive, setExplicitRedirect, setSetupRedirect, setLoginActionInProgress]);

  return null;
};

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const refreshInitialWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setWorkerStatus = useSetAtom(setWorkerStatusAtom);
  
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
  }, [authLoadableValue, refreshInitialWorkerStatus, setWorkerStatus])
  
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
            <PathSaver />
            <RedirectGuard />
            <RedirectHandler />
            <AuthCrossTabSyncer /> {/* Add the cross-tab syncer */}
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
 */
export const StateInspector = () => {
  const [isVisible, setIsVisible] = useAtom(stateInspectorVisibleAtom);
  const [mounted, setMounted] = React.useState(false);
  const [isExpanded, setIsExpanded] = React.useState(false);
  const [copyStatus, setCopyStatus] = React.useState(''); // For "Copied!" message

  // Atoms for general state
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const baseDataLoadableValue = useAtomValue(baseDataLoadableAtom);
  // Use the combined workerStatusAtom for the inspector.
  // It already includes loading and error states.
  const workerStatusValue = useAtomValue(workerStatusAtom); 

  // Atoms for redirect logic debugging
  const pathname = usePathname(); // Get current pathname
  const pendingRedirectValue = useAtomValue(pendingRedirectAtom);
  const requiredSetupRedirectValue = useAtomValue(requiredSetupRedirectAtom);
  const loginActionInProgressValue = useAtomValue(loginActionInProgressAtom);
  const lastKnownPathValue = useAtomValue(lastKnownPathBeforeAuthChangeAtom);
  const restClientFromAtom = useAtomValue(importedRestClientAtom);
  const activityStandardFromAtom = useAtomValue(activityCategoryStandardSettingAtomAsync);
  const numberOfRegionsFromAtom = useAtomValue(numberOfRegionsAtomAsync);
  // baseData.hasStatisticalUnits and baseData.statDefinitions.length are derived from baseDataLoadableValue

  useEffect(() => {
    setMounted(true);
  }, []);

  // Add keydown listener to toggle visibility
  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        setIsVisible(prev => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => {
      window.removeEventListener('keydown', handleKeyDown);
    };
  }, [setIsVisible]);

  if (!isVisible) {
    return null;
  }

  if (!mounted) {
    return (
      <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-2 rounded-lg text-xs max-w-md">
        <span className="font-bold">State Inspector:</span> Loading...
      </div>
    );
  }

  const toggleExpand = () => setIsExpanded(!isExpanded);

  const handleCopyToClipboard = () => {
    const stateToCopy = {
      pathname,
      authStatus: {
        state: authLoadableValue.state,
        isAuthenticated: authLoadableValue.state === 'hasData' ? authLoadableValue.data.isAuthenticated : undefined,
        user: authLoadableValue.state === 'hasData' ? authLoadableValue.data.user : undefined,
        expired_access_token_call_refresh: authLoadableValue.state === 'hasData' ? authLoadableValue.data.expired_access_token_call_refresh : undefined,
        error: authLoadableValue.state === 'hasError' ? String(authLoadableValue.error) : undefined,
      },
      baseData: {
        state: baseDataLoadableValue.state,
        statDefinitionsCount: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.statDefinitions.length : undefined,
        externalIdentTypesCount: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.externalIdentTypes.length : undefined,
        statbusUsersCount: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.statbusUsers.length : undefined,
        timeContextsCount: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.timeContexts.length : undefined,
        defaultTimeContextIdent: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.defaultTimeContext?.ident : undefined,
        hasStatisticalUnits: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.hasStatisticalUnits : undefined,
        error: baseDataLoadableValue.state === 'hasError' ? String(baseDataLoadableValue.error) : undefined,
      },
      workerStatus: {
        state: workerStatusValue.loading ? 'loading' : workerStatusValue.error ? 'hasError' : 'hasData',
        isImporting: workerStatusValue.isImporting,
        isDerivingUnits: workerStatusValue.isDerivingUnits,
        isDerivingReports: workerStatusValue.isDerivingReports,
        loading: workerStatusValue.loading,
        error: workerStatusValue.error,
      },
      navigationState: {
        pendingRedirect: pendingRedirectValue,
        requiredSetupRedirect: requiredSetupRedirectValue,
        loginActionInProgress: loginActionInProgressValue,
        lastKnownPathBeforeAuthChange: lastKnownPathValue,
      },
      redirectRelevantState: {
        authCheckDone: authLoadableValue.state !== 'loading',
        isRestClientReady: !!restClientFromAtom,
        activityStandard: activityStandardFromAtom, // This is the actual data or null
        numberOfRegions: numberOfRegionsFromAtom, // This is the actual count or null
        // from baseData:
        baseDataHasStatisticalUnits: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.hasStatisticalUnits : 'BaseDataNotLoaded',
        baseDataStatDefinitionsLength: baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.statDefinitions.length : 'BaseDataNotLoaded',
      }
    };
    navigator.clipboard.writeText(JSON.stringify(stateToCopy, null, 2))
      .then(() => {
        setCopyStatus('Copied!');
        setTimeout(() => setCopyStatus(''), 2000);
      })
      .catch(err => {
        console.error('Failed to copy state to clipboard:', err);
        setCopyStatus('Failed to copy');
        setTimeout(() => setCopyStatus(''), 2000);
      });
  };

  const getSimpleStatus = (loadable: any) => {
    if (loadable.state === 'loading') return 'Loading';
    if (loadable.state === 'hasError') return 'Error';
    if (loadable.state === 'hasData') return 'OK';
    return 'Unknown';
  };
  
  const getWorkerSummary = (data: any) => {
    if (!data) return 'N/A';
    if (data.isImporting) return 'Importing';
    if (data.isDerivingUnits) return 'Deriving Units';
    if (data.isDerivingReports) return 'Deriving Reports';
    return 'Idle';
  }

  return (
    <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-2 rounded-lg text-xs max-w-md max-h-[80vh] overflow-auto z-[9999]">
      <div className="flex justify-between items-center">
        <span onClick={toggleExpand} className="cursor-pointer font-bold">State Inspector {isExpanded ? '▼' : '▶'}</span>
        <button 
          onClick={handleCopyToClipboard} 
          className="ml-2 px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs"
          title="Copy all state to clipboard"
        >
          {copyStatus || 'Copy State'}
        </button>
      </div>
      {!isExpanded && (
        <div className="mt-1">
          <span>Auth: {getSimpleStatus(authLoadableValue)}</span> | <span>Base: {getSimpleStatus(baseDataLoadableValue)}</span> | <span>Worker: {workerStatusValue.loading ? 'Loading' : workerStatusValue.error ? 'Error' : getWorkerSummary(workerStatusValue)}</span>
        </div>
      )}
      {isExpanded && (
        <div className="mt-2 space-y-2">
          <div>
            <strong>Auth Status:</strong> {authLoadableValue.state}
            <div className="pl-4 mt-1 space-y-1">
              {authLoadableValue.state === 'hasData' && (
                <>
                  <div><strong>Authenticated:</strong> {authLoadableValue.data.isAuthenticated ? 'Yes' : 'No'}</div>
                  <div><strong>User:</strong> {authLoadableValue.data.user?.email || 'None'}</div>
                  <div><strong>UID:</strong> {authLoadableValue.data.user?.uid || 'N/A'}</div>
                  <div><strong>Role:</strong> {authLoadableValue.data.user?.role || 'N/A'}</div>
                  <div><strong>Statbus Role:</strong> {authLoadableValue.data.user?.statbus_role || 'N/A'}</div>
                  <div><strong>Refresh Needed:</strong> {authLoadableValue.data.expired_access_token_call_refresh ? 'Yes' : 'No'}</div>
                </>
              )}
              {authLoadableValue.state === 'hasError' && <div><strong>Error:</strong> {String(authLoadableValue.error)}</div>}
            </div>
          </div>

          <div>
            <strong>Base Data Status:</strong> {baseDataLoadableValue.state}
            <div className="pl-4 mt-1 space-y-1">
              {baseDataLoadableValue.state === 'hasData' && (
                <>
                  <div><strong>Stat Definitions:</strong> {baseDataLoadableValue.data.statDefinitions.length}</div>
                  <div><strong>External Ident Types:</strong> {baseDataLoadableValue.data.externalIdentTypes.length}</div>
                  <div><strong>Statbus Users:</strong> {baseDataLoadableValue.data.statbusUsers.length}</div>
                  <div><strong>Time Contexts:</strong> {baseDataLoadableValue.data.timeContexts.length}</div>
                  <div><strong>Default Time Context:</strong> {baseDataLoadableValue.data.defaultTimeContext?.ident || 'None'}</div>
                  <div><strong>Has Statistical Units:</strong> {baseDataLoadableValue.data.hasStatisticalUnits ? 'Yes' : 'No'}</div>
                </>
              )}
              {baseDataLoadableValue.state === 'hasError' && <div><strong>Error:</strong> {String(baseDataLoadableValue.error)}</div>}
            </div>
          </div>

          <div>
            <strong>Worker Status:</strong> {workerStatusValue.loading ? 'Loading' : workerStatusValue.error ? 'Error' : 'OK'}
            <div className="pl-4 mt-1 space-y-1">
              {!workerStatusValue.loading && !workerStatusValue.error && (
                <>
                  <div><strong>Importing:</strong> {workerStatusValue.isImporting === null ? 'N/A' : workerStatusValue.isImporting ? 'Yes' : 'No'}</div>
                  <div><strong>Deriving Units:</strong> {workerStatusValue.isDerivingUnits === null ? 'N/A' : workerStatusValue.isDerivingUnits ? 'Yes' : 'No'}</div>
                  <div><strong>Deriving Reports:</strong> {workerStatusValue.isDerivingReports === null ? 'N/A' : workerStatusValue.isDerivingReports ? 'Yes' : 'No'}</div>
                </>
              )}
              {workerStatusValue.error && <div><strong>Error:</strong> {workerStatusValue.error}</div>}
            </div>
          </div>

          <div>
            <strong>Navigation & Redirect Debugging:</strong>
            <div className="pl-4 mt-1 space-y-1">
              <div><strong>Pathname:</strong> {pathname}</div>
              <div><strong>Active Redirect Target:</strong> {(pendingRedirectValue || requiredSetupRedirectValue) || 'None'}</div>
              <div><strong>Pending Redirect:</strong> {pendingRedirectValue || 'None'}</div>
              <div><strong>Required Setup Redirect:</strong> {requiredSetupRedirectValue || 'None'}</div>
              <div><strong>Login Action in Progress:</strong> {loginActionInProgressValue ? 'Yes' : 'No'}</div>
              <div><strong>Last Known Path (pre-auth):</strong> {lastKnownPathValue || 'None'}</div>
              <hr className="my-1 border-gray-500" />
              <div><strong>Auth Check Done:</strong> {authLoadableValue.state !== 'loading' ? 'Yes' : 'No'}</div>
              <div><strong>REST Client Ready:</strong> {restClientFromAtom ? 'Yes' : 'No'}</div>
              <div><strong>Activity Standard:</strong> {activityStandardFromAtom === null ? 'Null' : JSON.stringify(activityStandardFromAtom)}</div>
              <div><strong>Number of Regions:</strong> {numberOfRegionsFromAtom === null ? 'Null/Loading' : numberOfRegionsFromAtom}</div>
              <div><strong>BaseData - Has Statistical Units:</strong> {baseDataLoadableValue.state === 'hasData' ? (baseDataLoadableValue.data.hasStatisticalUnits ? 'Yes' : 'No') : 'BaseDataNotLoaded'}</div>
              <div><strong>BaseData - Stat Definitions Count:</strong> {baseDataLoadableValue.state === 'hasData' ? baseDataLoadableValue.data.statDefinitions.length : 'BaseDataNotLoaded'}</div>
            </div>
          </div>

        </div>
      )}
    </div>
  );
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
  <StateInspector /> // Optional, can be toggled with Cmd+K
</JotaiAppProvider>
*/

export default JotaiAppProvider
