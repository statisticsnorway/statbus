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
  authStatusAtom,
  baseDataAtom,
  restClientAtom,
  refreshBaseDataAtom,
  refreshWorkerStatusAtom,
  workerStatusAtom, // This is the combined synchronous atom
  authStatusLoadableAtom,
  baseDataLoadableAtom,
  initializeTableColumnsAtom,
  refreshAllUnitCountsAtom,
  authStatusInitiallyCheckedAtom,
  initialAuthCheckDoneEffect,
  activityCategoryStandardSettingAtomAsync,
  numberOfRegionsAtomAsync,
  restClientAtom as importedRestClientAtom, // Alias to avoid conflict with local restClient variable
  type ValidWorkerFunctionName, // Import the type
  pendingRedirectAtom,
  loginActionInProgressAtom,
  requiredSetupRedirectAtom, // Import the new atom
  lastKnownPathBeforeAuthChangeAtom,
  clientMountedAtom,
  clientSideRefreshAtom,
} from './index';
import { AuthCrossTabSyncer } from './AuthCrossTabSyncer'; // Import the new syncer

// ============================================================================
// APP INITIALIZER - Handles startup logic
// ============================================================================

const AppInitializer = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const authStatus = useAtomValue(authStatusAtom);
  const clientSideRefresh = useSetAtom(clientSideRefreshAtom);
  const initialAuthCheckDone = useAtomValue(authStatusInitiallyCheckedAtom);
  const restClient = useAtomValue(restClientAtom);
  useAtomValue(initialAuthCheckDoneEffect); // Activate the effect atom
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
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log('AppInitializer: Access token expired, refresh possible. Attempting auto-refresh...');
      }
      clientSideRefresh();
    }
  }, [authStatus.expired_access_token_call_refresh, clientSideRefresh]);

  // Initialize REST client
  useEffect(() => {
    let mounted = true
    const initializeClient = async () => {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log('AppInitializer: Attempting to initialize browser REST client...');
      }
      // Log the BROWSER_REST_URL the client-side code sees
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`AppInitializer: NEXT_PUBLIC_BROWSER_REST_URL (client-side) = "${process.env.NEXT_PUBLIC_BROWSER_REST_URL}"`);
      }

      try {
        // Import your existing RestClientStore
        const { getBrowserRestClient } = await import('@/context/RestClientStore')
        const client = await getBrowserRestClient() // This is an async function
        
        if (mounted) {
          if (client) {
            setRestClient(client);
            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              console.log('AppInitializer: Browser REST client successfully initialized and set in restClientAtom.', { clientUrl: client.url });
              console.log('AppInitializer: Full client object for debugging:', { clientObject: client });
            }
          } else {
            // This case should ideally not happen if getBrowserRestClient throws on failure.
            console.error('AppInitializer: getBrowserRestClient() returned null/undefined without throwing an error. This is unexpected. Setting restClientAtom to null.');
            setRestClient(null); // Explicitly set to null if it wasn't set
          }
        } else {
          console.log('AppInitializer: Component unmounted before REST client could be set.');
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
      const isAuthCurrentlyLoading = authLoadableValue.state === 'loading';

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
    initialAuthCheckDone,      
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
    const isAuthLoading = authLoadableValue.state === 'loading';

    // Setup checks are only relevant if on the dashboard ('/') and authenticated.
    if (pathname !== '/' || !currentIsAuthenticated || isAuthLoading || !initialAuthCheckDone || !restClient) {
      // If not in a state where setup redirects are relevant, ensure no setup redirect is pending.
      setRequiredSetupRedirect(null);
      return;
    }

    // At this point: on '/', authenticated, not loading, client ready, initial auth check done.
    let targetSetupPath: string | null = null;

    if (activityStandard === null) {
      targetSetupPath = '/getting-started/activity-standard';
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`AppInitializer: Setup check - No activity standard. Target: ${targetSetupPath}`);
      }
    } else if (numberOfRegions === null || numberOfRegions === 0) {
      targetSetupPath = '/getting-started/upload-regions';
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`AppInitializer: Setup check - No regions (count: ${numberOfRegions}). Target: ${targetSetupPath}`);
      }
    } else if (baseData.statDefinitions.length > 0 && !baseData.hasStatisticalUnits) {
      targetSetupPath = '/import';
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`AppInitializer: Setup check - No statistical units. Target: ${targetSetupPath}`);
      }
    }

    // Set or clear the setup redirect atom based on checks.
    setRequiredSetupRedirect(targetSetupPath);
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      if (targetSetupPath) {
        console.log(`AppInitializer: Setting requiredSetupRedirectAtom to "${targetSetupPath}".`);
      } else {
        // console.log("AppInitializer: All setup checks passed. Ensuring requiredSetupRedirectAtom is null.");
      }
    }
  }, [
    pathname,
    authLoadableValue,
    initialAuthCheckDone,
    restClient,
    activityStandard,
    numberOfRegions,
    baseData.hasStatisticalUnits,
    baseData.statDefinitions.length,
    setRequiredSetupRedirect // Add setter to dependencies
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

  useEffect(() => {
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
  }, [pathname, search, authStatus.isAuthenticated, setLastPath]);

  return null;
};

// ============================================================================
// REDIRECT GUARD - Handles redirecting unauthenticated users to login
// ============================================================================

const RedirectGuard = () => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const initialAuthCheckDone = useAtomValue(authStatusInitiallyCheckedAtom);
  const pathname = usePathname();
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);

  useEffect(() => {
    const debug = process.env.NEXT_PUBLIC_DEBUG === 'true';
    const isAuthStableAndChecked = initialAuthCheckDone && authLoadableValue.state !== 'loading';
    const currentIsAuthenticated = authLoadableValue.state === 'hasData' && authLoadableValue.data.isAuthenticated;
    const canRefresh = authLoadableValue.state === 'hasData' && authLoadableValue.data.expired_access_token_call_refresh;

    if (!isAuthStableAndChecked) {
      return;
    }

    const publicPaths = ['/login'];

    if (!currentIsAuthenticated && !canRefresh && !publicPaths.some(p => pathname.startsWith(p))) {
      if (debug) {
        console.log(`RedirectGuard: User is not authenticated on protected path ("${pathname}") and cannot refresh. Redirecting to login.`);
      }
      // The path has already been saved by PathSaver. Just trigger the redirect.
      setPendingRedirect('/login');
    }
  }, [
    pathname,
    authLoadableValue,
    initialAuthCheckDone,
    setPendingRedirect
  ]);

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

  // Effect to navigate if we are not at the target path
  useEffect(() => {
    if (targetPath && targetPath !== pathname) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`RedirectHandler: Target path ("${targetPath}") differs from current ("${pathname}"). Navigating via router.push().`);
      }
      router.push(targetPath);
    }
  }, [targetPath, pathname, router]);

  // Effect to clear the redirect atoms once we have arrived at the destination.
  // This is mainly for router.push() in production. For window.location.href,
  // the page reloads and state is reset anyway.
  useEffect(() => {
    if (targetPath && targetPath === pathname) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`RedirectHandler: Arrived at target "${targetPath}". Clearing redirect atoms.`);
      }
      // Clear the atom that triggered the redirect
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
  }, [pathname, targetPath, explicitRedirect, setupRedirect, loginActionIsActive, setExplicitRedirect, setSetupRedirect, setLoginActionInProgress]);

  return null;
};

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
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
        
        eventSource.onmessage = (event) => { // Handles default messages (event: message or no event field)
          // This block can be kept for other general messages if any, or removed if '/api/sse/worker-check' only sends named events.
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log('SSE default onmessage received:', event.data);
          }
        };

        eventSource.addEventListener('check', (event) => {
          // Assuming event.data is a string like "is_importing", "is_deriving_statistical_units", etc.
          const functionName = event.data as string;
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log(`SSE 'check' event received, data: "${functionName}". Refreshing specific worker status.`);
          }
          // Type assertion for safety, though refreshWorkerStatusAtom handles undefined gracefully.
          if (functionName === "is_importing" || functionName === "is_deriving_statistical_units" || functionName === "is_deriving_reports") {
            refreshWorkerStatus(functionName as ValidWorkerFunctionName);
          } else {
            console.warn(`SSE 'check' event received with unknown data: "${functionName}". Refreshing all worker statuses as a fallback.`);
            refreshWorkerStatus(); // Refresh all if data is not one of the expected strings
          }
        });

        eventSource.addEventListener('connected', (event) => {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log('SSE "connected" event received:', event.data);
          }
          // You might want to trigger an initial full refresh of worker status upon connection
          refreshWorkerStatus();
        });
        
        eventSource.onerror = (event) => {
          // The 'event' object for onerror might not be a MessageEvent and may not have a 'type' or 'readyState' in the same way.
          // It's often a simple Event.
          console.error(`SSE connection error. Attempting to reconnect...`, event);
          
          eventSource?.close();
          
          if (reconnectAttempts < maxReconnectAttempts) {
            const delay = Math.min(1000 * Math.pow(2, reconnectAttempts), 30000);
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
  }, [authLoadableValue, refreshWorkerStatus])
  
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
 * Only renders in development mode
 */
export const JotaiStateInspector = () => {
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
  const initialAuthCheckDoneFromAtom = useAtomValue(authStatusInitiallyCheckedAtom);
  const restClientFromAtom = useAtomValue(importedRestClientAtom);
  const activityStandardFromAtom = useAtomValue(activityCategoryStandardSettingAtomAsync);
  const numberOfRegionsFromAtom = useAtomValue(numberOfRegionsAtomAsync);
  // baseData.hasStatisticalUnits and baseData.statDefinitions.length are derived from baseDataLoadableValue

  useEffect(() => {
    setMounted(true);
  }, []);

  // Show if NEXT_PUBLIC_DEBUG is true OR if NODE_ENV is 'development'.
  // Hide if NEXT_PUBLIC_DEBUG is NOT true AND NODE_ENV is NOT 'development'.
  useEffect(() => {
    if (mounted && typeof window !== 'undefined') { // Log only on the client-side, once mounted
      console.log('[JotaiStateInspector] Env Vars Check:', {
        NEXT_PUBLIC_DEBUG: process.env.NEXT_PUBLIC_DEBUG,
        NODE_ENV: process.env.NODE_ENV,
        shouldRender: process.env.NEXT_PUBLIC_DEBUG === 'true' || process.env.NODE_ENV === 'development',
      });
    }
  }, [mounted]);

  if (process.env.NEXT_PUBLIC_DEBUG !== 'true' && process.env.NODE_ENV !== 'development') {
    return null;
  }

  if (!mounted) {
    return (
      <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-2 rounded-lg text-xs max-w-md">
        <span className="font-bold">JotaiStateInspector:</span> Loading...
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
      redirectRelevantState: {
        initialAuthCheckDone: initialAuthCheckDoneFromAtom,
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
        <span onClick={toggleExpand} className="cursor-pointer font-bold">JotaiStateInspector {isExpanded ? '▼' : '▶'}</span>
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
            <strong>Redirect Relevant State:</strong>
            <div className="pl-4 mt-1 space-y-1">
              <div><strong>Pathname:</strong> {pathname}</div>
              <div><strong>Initial Auth Check Done:</strong> {initialAuthCheckDoneFromAtom ? 'Yes' : 'No'}</div>
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
  <JotaiStateInspector /> // Optional, only in development
</JotaiAppProvider>
*/

export default JotaiAppProvider
