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
  initialAuthCheckCompletedAtom,
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
  isAuthenticatedAtom,
  lastKnownPathBeforeAuthChangeAtom,
  loginActionInProgressAtom,
  authStateStabilizerEffect,
  lastStableIsAuthenticatedAtom,
  rawAuthStatusDetailsAtom,
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
  searchStateAtom,
  selectedUnitsAtom,
} from './search';
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
  useAtom(authStateStabilizerEffect); // Mount the effect to stabilize auth state
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const isAuthenticated = useAtomValue(isAuthenticatedAtom);
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
  const setRequiredSetupRedirect = useSetAtom(requiredSetupRedirectAtom);
  
  // Use Jotai's `loadable` utility to check the status of async atoms
  // without causing the component to suspend. This is key to preventing
  // redirects based on stale data.
  const activityStandardLoadable = useAtomValue(loadable(activityCategoryStandardSettingAtomAsync));
  const numberOfRegionsLoadable = useAtomValue(loadable(numberOfRegionsAtomAsync));
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const setLastPath = useSetAtom(lastKnownPathBeforeAuthChangeAtom);
  const setClientMounted = useSetAtom(clientMountedAtom);
  const initialAuthCheckCompleted = useAtomValue(initialAuthCheckCompletedAtom);
  const setInitialAuthCheckCompleted = useSetAtom(initialAuthCheckCompletedAtom);
  // isRedirectingToSetup flag is removed as RedirectHandler manages actual navigation.
  
  // Effect to signal that the client has mounted. This helps prevent hydration issues.
  useEffect(() => {
    setClientMounted(true);
  }, [setClientMounted]);

  // Effect to establish when the first successful authentication check has completed.
  // This creates a stable "app is ready" signal for other components like RedirectGuard,
  // preventing them from acting on transient, intermediate auth states.
  useEffect(() => {
    // If we've already completed the check, we're done here.
    if (initialAuthCheckCompleted) {
      return;
    }
    // Once auth status has data for the first time, we mark the initial check as complete.
    // This flag will persist for the lifetime of the app session.
    if (authLoadableValue.state === 'hasData') {
      setInitialAuthCheckCompleted(true);
    }
  }, [authLoadableValue, initialAuthCheckCompleted, setInitialAuthCheckCompleted]);

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
      // Core conditions: user must be authenticated and REST client ready.
      // We use the new, stabilized `isAuthenticated` atom here to prevent the
      // "auth flap" from disrupting the initial data load.
      if (!isAuthenticated || !restClient) {
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
    // Setup checks are only relevant on the dashboard ('/') and when authenticated.
    if (pathname !== '/' || !isAuthenticated || !restClient) {
      setRequiredSetupRedirect(null);
      return;
    }

    // Wait until all required data has finished loading before making a decision.
    // This prevents redirects based on stale data from a previous page that is still refreshing.
    if (
        activityStandardLoadable.state === 'loading' ||
        numberOfRegionsLoadable.state === 'loading' ||
        baseData.loading
    ) {
      return; // Data is not ready, wait for the next render.
    }

    // At this point, all data is loaded and stable. We can now safely check the values.
    const currentActivityStandard = activityStandardLoadable.state === 'hasData' ? activityStandardLoadable.data : null;
    const currentNumberOfRegions = numberOfRegionsLoadable.state === 'hasData' ? numberOfRegionsLoadable.data : null;

    let targetSetupPath: string | null = null;

    if (currentActivityStandard === null) {
      targetSetupPath = '/getting-started/activity-standard';
    } else if (currentNumberOfRegions === null || currentNumberOfRegions === 0) {
      targetSetupPath = '/getting-started/upload-regions';
    } else if (baseData.statDefinitions.length > 0 && !baseData.hasStatisticalUnits) {
      targetSetupPath = '/import';
    }

    // Set or clear the setup redirect atom based on checks.
    setRequiredSetupRedirect(targetSetupPath);
  }, [
    pathname,
    isAuthenticated,
    restClient,
    activityStandardLoadable,
    numberOfRegionsLoadable,
    baseData,
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
  const isAuthenticated = useAtomValue(isAuthenticatedAtom);

  useEffect(() => {
    // Continuously save the current path to sessionStorage while the user is authenticated.
    // This ensures that if a logout event occurs, or an auth change requires a
    // redirect, the last known good path is already stored.
    // The logic is now simpler because the stabilized `isAuthenticated` atom prevents
    // the complex "flap" scenario this component previously had to handle.
    if (isAuthenticated) {
      const fullPath = `${pathname}${search ? `?${search}` : ''}`;
      // Don't save the login page itself as a restoration target.
      if (pathname !== '/login') {
        setLastPath(fullPath);
      }
    }
  }, [pathname, search, isAuthenticated, setLastPath]);

  return null;
};

// ============================================================================
// REDIRECT GUARD - Handles redirecting unauthenticated users to login
// ============================================================================

const RedirectGuard = () => {
  const isAuthenticated = useAtomValue(isAuthenticatedAtom);
  const authLoadable = useAtomValue(authStatusLoadableAtom);
  const pathname = usePathname();
  const setPendingRedirect = useSetAtom(pendingRedirectAtom);
  const [pendingRedirectValue] = useAtom(pendingRedirectAtom);
  const initialAuthCheckCompleted = useAtomValue(initialAuthCheckCompletedAtom);

  useEffect(() => {
    // Wait until the initial authentication check has successfully completed at least once.
    if (!initialAuthCheckCompleted) {
      return;
    }

    // Do not trigger a new redirect if one is already pending.
    if (pendingRedirectValue) {
      return;
    }

    // We still check the loading state from the loadable to prevent redirecting
    // during the very first, initial auth check before `isAuthenticated` has stabilized.
    const isAuthLoading = authLoadable.state === 'loading';
    const publicPaths = ['/login'];

    // Redirect if auth is not loading, user is not authenticated, and not on a public path.
    // The `isAuthenticated` atom is stabilized and already accounts for pending token refreshes.
    if (!isAuthLoading && !isAuthenticated && !publicPaths.some(p => pathname.startsWith(p))) {
      // The path has already been saved by PathSaver. Just trigger the redirect.
      setPendingRedirect('/login');
    }
  }, [pathname, isAuthenticated, authLoadable, setPendingRedirect, pendingRedirectValue, initialAuthCheckCompleted]);

  return null;
};

// ============================================================================
// REDIRECT HANDLER - Handles programmatic redirects
// ============================================================================

const RedirectHandler = () => {
  const [explicitRedirect, setExplicitRedirect] = useAtom(pendingRedirectAtom);
  const [setupRedirect, setSetupRedirect] = useAtom(requiredSetupRedirectAtom);
  const [loginActionIsActive, setLoginActionInProgress] = useAtom(loginActionInProgressAtom);
  const setLastPathBeforeAuthChange = useSetAtom(lastKnownPathBeforeAuthChangeAtom);
  const router = useRouter();
  const pathname = usePathname();
  // A ref to track the pathname from the previous render. This is the key to
  // detecting when a user-initiated navigation has occurred, allowing us to
  // cancel any pending programmatic redirects.
  const prevPathnameRef = React.useRef(pathname);

  // Determine the single desired target path. Explicit redirects take priority.
  const targetPath = explicitRedirect || setupRedirect;

  // This effect runs on every render where pathname or a redirect atom changes.
  // It's the core of the centralized navigation logic.
  useEffect(() => {
    const prevPathname = prevPathnameRef.current;
    // Update ref for the next render *before* any early returns. This ensures
    // the ref is always current for the next comparison.
    prevPathnameRef.current = pathname;

    // SCENARIO 1: User-initiated navigation overrides a pending redirect.
    // We detect this by checking if a redirect was pending (`targetPath`), if the URL
    // has changed (`pathname !== prevPathname`), AND if the new URL is NOT our
    // intended redirect destination. If all are true, the user has taken control
    // (e.g., by clicking a <Link>). We must cancel our redirect and yield.
    if (targetPath && pathname !== prevPathname && targetPath.split('?')[0] !== pathname) {
      if (explicitRedirect) {
        setExplicitRedirect(null);
      }
      if (setupRedirect) {
        setSetupRedirect(null);
      }
      return; // Stop processing to allow the user's navigation to complete.
    }

    // If there's no target path, there's nothing to do.
    if (!targetPath) {
      return;
    }

    const targetPathname = targetPath.split('?')[0];

    // SCENARIO 2: Execute a pending programmatic redirect.
    // If we are not already at the target destination, navigate.
    if (targetPathname !== pathname) {
      router.push(targetPath);
    } else {
      // SCENARIO 3: Cleanup after a successful redirect.
      // We have arrived at our destination. Clear the state that triggered the
      // redirect to prevent loops.
      if (explicitRedirect) {
        setExplicitRedirect(null);
        // After any successful explicit redirect, the "login action" is complete (if one was active)
        // and the "last known path" has been restored or is no longer relevant.
        // We clear all related state to prevent stale values from causing issues.
        setLoginActionInProgress(false);
        setLastPathBeforeAuthChange(null);
      }
      if (setupRedirect) {
        setSetupRedirect(null);
      }
    }
  }, [targetPath, pathname, router, explicitRedirect, setupRedirect, loginActionIsActive, setExplicitRedirect, setSetupRedirect, setLoginActionInProgress, setLastPathBeforeAuthChange]);

  return null;
};

// ============================================================================
// SSE CONNECTION MANAGER
// ============================================================================

const SSEConnectionManager = ({ children }: { children: ReactNode }) => {
  const isAuthenticated = useAtomValue(isAuthenticatedAtom);
  const refreshInitialWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const setWorkerStatus = useSetAtom(setWorkerStatusAtom);
  
  useEffect(() => {
    // Connect SSE only when the user is in a stable authenticated state.
    // Using the stabilized `isAuthenticatedAtom` prevents unnecessary
    // disconnects/reconnects during transient auth state flaps.
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
  }, [isAuthenticated, refreshInitialWorkerStatus, setWorkerStatus])
  
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
// Helper to recursively calculate the difference between two objects.
const objectDiff = (obj1: any, obj2: any): any | undefined => {
  // Simple comparison for non-objects or if they are identical
  if (Object.is(obj1, obj2)) {
    return undefined;
  }
  // If one is not an object (or is null), return the change
  if (typeof obj1 !== 'object' || obj1 === null || typeof obj2 !== 'object' || obj2 === null) {
    return { oldValue: obj1, newValue: obj2 };
  }

  // For arrays, we'll do a simple stringify compare for brevity, not a deep diff
  if (Array.isArray(obj1) || Array.isArray(obj2)) {
    if (JSON.stringify(obj1) !== JSON.stringify(obj2)) {
      return { oldValue: obj1, newValue: obj2 };
    }
    return undefined;
  }

  const keys = [...new Set([...Object.keys(obj1), ...Object.keys(obj2)])];
  const diff: { [key: string]: any } = {};
  let hasChanges = false;

  for (const key of keys) {
    const result = objectDiff(obj1[key], obj2[key]);
    if (result !== undefined) {
      diff[key] = result;
      hasChanges = true;
    }
  }

  return hasChanges ? diff : undefined;
};

// Helper to format the diff object into a readable string for clipboard.
const formatDiffToString = (diff: any, path: string = ''): string => {
  let result = '';
  if (!diff) return '';
  for (const key in diff) {
    const newPath = path ? `${path}.${key}` : key;
    const value = diff[key];
    if (value && typeof value.oldValue !== 'undefined') {
      result += `- ${newPath}: ${JSON.stringify(value.oldValue)}\n`;
      result += `+ ${newPath}: ${JSON.stringify(value.newValue)}\n`;
    } else if (typeof value === 'object' && value !== null) {
      result += formatDiffToString(value, newPath);
    }
  }
  return result;
};

// Helper component to visually render the diff.
const DiffViewer = ({ diffData }: { diffData: any }) => {
  if (!diffData) return <div className="pl-4 mt-1">No changes detected to next state.</div>;
  return (
    <div className="pl-4 mt-1 space-y-1 font-mono text-xs">
      {Object.entries(diffData).map(([key, value]: [string, any]) => {
        if (value && typeof value.oldValue !== 'undefined') {
          return (
            <div key={key}>
              <span className="text-gray-400">{key}: </span>
              <span className="text-red-500" style={{ textDecoration: 'line-through' }}>
                {JSON.stringify(value.oldValue)}
              </span>
              <span className="text-gray-400"> → </span>
              <span className="text-green-500">{JSON.stringify(value.newValue)}</span>
            </div>
          );
        }
        if (value && typeof value === 'object') {
          return (
            <div key={key}>
              <span className="font-semibold text-gray-300">{key}:</span>
              <DiffViewer diffData={value} />
            </div>
          );
        }
        return null;
      })}
    </div>
  );
};


export const StateInspector = () => {
  const [isVisible, setIsVisible] = useAtom(stateInspectorVisibleAtom);
  const [mounted, setMounted] = React.useState(false);
  const [isExpanded, setIsExpanded] = React.useState(false);
  const [copyStatus, setCopyStatus] = React.useState(''); // For "Copied!" message
  const [history, setHistory] = React.useState<any[]>([]);
  const [viewingIndex, setViewingIndex] = React.useState<number>(0);
  const [diff, setDiff] = React.useState<any | null>(null);

  // Atoms for general state
  const authLoadableValue = useAtomValue(authStatusLoadableAtom);
  const rawAuthStatusDetailsValue = useAtomValue(rawAuthStatusDetailsAtom);
  const baseDataFromAtom = useAtomValue(baseDataAtom);
  const workerStatusValue = useAtomValue(workerStatusAtom);
  const searchStateValue = useAtomValue(searchStateAtom);
  const searchResultValue = useAtomValue(searchResultAtom);
  const selectedUnitsValue = useAtomValue(selectedUnitsAtom);

  // Atoms for redirect logic debugging
  const pathname = usePathname();
  const isAuthenticatedValue = useAtomValue(isAuthenticatedAtom);
  const lastStableIsAuthenticatedValue = useAtomValue(lastStableIsAuthenticatedAtom);
  const initialAuthCheckCompletedValue = useAtomValue(initialAuthCheckCompletedAtom);
  const pendingRedirectValue = useAtomValue(pendingRedirectAtom);
  const requiredSetupRedirectValue = useAtomValue(requiredSetupRedirectAtom);
  const loginActionInProgressValue = useAtomValue(loginActionInProgressAtom);
  const lastKnownPathValue = useAtomValue(lastKnownPathBeforeAuthChangeAtom);
  const restClientFromAtom = useAtomValue(importedRestClientAtom);
  const activityStandardLoadable = useAtomValue(loadable(activityCategoryStandardSettingAtomAsync));
  const numberOfRegionsLoadable = useAtomValue(loadable(numberOfRegionsAtomAsync));

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey) {
        e.preventDefault();
        setIsVisible(prev => !prev);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [setIsVisible]);

  const baseDataState = baseDataFromAtom.loading ? 'loading' : baseDataFromAtom.error ? 'hasError' : 'hasData';
  const fullState = {
    pathname,
    authStatus: {
      state: rawAuthStatusDetailsValue.loading ? 'loading' : rawAuthStatusDetailsValue.error_code ? 'hasError' : 'hasData',
      isAuthenticated: isAuthenticatedValue,
      lastStableIsAuthenticated: lastStableIsAuthenticatedValue,
      isAuthenticated_RAW: rawAuthStatusDetailsValue.isAuthenticated,
      user: rawAuthStatusDetailsValue.user,
      expired_access_token_call_refresh: rawAuthStatusDetailsValue.expired_access_token_call_refresh,
      error: rawAuthStatusDetailsValue.error_code,
    },
    baseData: { state: baseDataState, statDefinitionsCount: baseDataState === 'hasData' ? baseDataFromAtom.statDefinitions.length : undefined, externalIdentTypesCount: baseDataState === 'hasData' ? baseDataFromAtom.externalIdentTypes.length : undefined, statbusUsersCount: baseDataState === 'hasData' ? baseDataFromAtom.statbusUsers.length : undefined, timeContextsCount: baseDataState === 'hasData' ? baseDataFromAtom.timeContexts.length : undefined, defaultTimeContextIdent: baseDataState === 'hasData' ? baseDataFromAtom.defaultTimeContext?.ident : undefined, hasStatisticalUnits: baseDataState === 'hasData' ? baseDataFromAtom.hasStatisticalUnits : undefined, error: baseDataState === 'hasError' ? String(baseDataFromAtom.error) : undefined },
    workerStatus: { state: workerStatusValue.loading ? 'loading' : workerStatusValue.error ? 'hasError' : 'hasData', isImporting: workerStatusValue.isImporting, isDerivingUnits: workerStatusValue.isDerivingUnits, isDerivingReports: workerStatusValue.isDerivingReports, loading: workerStatusValue.loading, error: workerStatusValue.error },
    searchAndSelection: {
      searchText: searchStateValue.query,
      activeFilterCodes: Object.keys(searchStateValue.filters),
      pagination: searchStateValue.pagination,
      order: searchStateValue.sorting,
      selectedUnitsCount: selectedUnitsValue.length,
      searchResult: {
        total: searchResultValue.total,
        loading: searchResultValue.loading,
        error: searchResultValue.error ? String(searchResultValue.error) : null,
      },
    },
    navigationState: { pendingRedirect: pendingRedirectValue, requiredSetupRedirect: requiredSetupRedirectValue, loginActionInProgress: loginActionInProgressValue, lastKnownPathBeforeAuthChange: lastKnownPathValue },
    redirectRelevantState: { initialAuthCheckCompleted: initialAuthCheckCompletedValue, authCheckDone: authLoadableValue.state !== 'loading', isRestClientReady: !!restClientFromAtom, activityStandard: activityStandardLoadable.state === 'hasData' ? activityStandardLoadable.data : null, numberOfRegions: numberOfRegionsLoadable.state === 'hasData' ? numberOfRegionsLoadable.data : null, baseDataHasStatisticalUnits: baseDataState === 'hasData' ? baseDataFromAtom.hasStatisticalUnits : 'BaseDataNotLoaded', baseDataStatDefinitionsLength: baseDataState === 'hasData' ? baseDataFromAtom.statDefinitions.length : 'BaseDataNotLoaded' }
  };

  const fullStateString = JSON.stringify(fullState);

  useEffect(() => {
    setHistory(prev => {
      if (prev.length > 0 && JSON.stringify(prev[prev.length - 1]) === fullStateString) return prev;
      const newHistory = [...prev, fullState].slice(-5);
      setViewingIndex(newHistory.length - 1);
      return newHistory;
    });
  }, [fullStateString]);

  useEffect(() => {
    if (viewingIndex < history.length - 1) {
      setDiff(objectDiff(history[viewingIndex], history[viewingIndex + 1]));
    } else {
      setDiff(null);
    }
  }, [viewingIndex, history]);

  const handleCopy = () => {
    if (!history[viewingIndex]) return; // Guard against empty history

    // 1. Get current state string
    const currentStateString = JSON.stringify(history[viewingIndex], null, 2);
    const selectedStateLabel = viewingIndex === history.length - 1 ? 'Now' : String(viewingIndex - (history.length - 1));

    // 2. Get historical diffs string
    let fullDiffReport = '';
    const totalStates = history.length;
    if (totalStates > 1) {
      for (let i = totalStates - 2; i >= 0; i--) {
        const currentDiff = objectDiff(history[i], history[i + 1]);
        if (!currentDiff) continue;

        const fromLabel = i - (totalStates - 1);
        const toLabel = (i + 1 - (totalStates - 1)) || 'Now';

        fullDiffReport += `--- Diff from state ${fromLabel} to ${toLabel} ---\n`;
        fullDiffReport += formatDiffToString(currentDiff);
        fullDiffReport += '\n';
      }
    }

    // 3. Combine them
    let content = `== Selected State (${selectedStateLabel}) ==\n${currentStateString}\n\n`;
    if (fullDiffReport.trim()) {
      content += `== Historical Diffs ==\n${fullDiffReport}`;
    } else if (totalStates > 1) {
      content += `== No historical diffs detected ==\n`;
    }

    // 4. Copy to clipboard
    navigator.clipboard.writeText(content.trim()).then(() => {
      setCopyStatus('Debug Info Copied!');
      setTimeout(() => setCopyStatus(''), 2000);
    }).catch(err => {
      console.error('Failed to copy debug info:', err);
      setCopyStatus('Failed to copy');
    });
  };

  const getSimpleStatus = (s: any) => s.state === 'loading' ? 'Loading' : s.state === 'hasError' ? 'Error' : 'OK';
  const getWorkerSummary = (d: any) => !d ? 'N/A' : d.isImporting ? 'Importing' : d.isDerivingUnits ? 'Deriving Units' : d.isDerivingReports ? 'Deriving Reports' : 'Idle';

  if (!isVisible) return null;
  if (!mounted) return <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-2 rounded-lg text-xs max-w-md"><span className="font-bold">State Inspector:</span> Loading...</div>;

  const stateToDisplay = history[viewingIndex] || {};

  return (
    <div className="fixed bottom-4 right-4 bg-black bg-opacity-80 text-white p-2 rounded-lg text-xs max-w-md max-h-[80vh] overflow-auto z-[9999]">
      <div className="flex justify-between items-center">
        <span onClick={() => setIsExpanded(!isExpanded)} className="cursor-pointer font-bold">State Inspector {isExpanded ? '▼' : '▶'}</span>
        <button
          onClick={handleCopy}
          className="ml-2 px-2 py-1 bg-gray-700 hover:bg-gray-600 rounded text-xs"
          title="Copy selected state and all historical diffs"
        >
          {copyStatus || 'Copy Debug Info'}
        </button>
      </div>
      {!isExpanded && history.length > 0 && (
        <div className="mt-1">
          <span>Auth: {getSimpleStatus(stateToDisplay.authStatus)}</span> | <span>Base: {getSimpleStatus(stateToDisplay.baseData)}</span> | <span>Worker: {stateToDisplay.workerStatus?.loading ? 'Loading' : stateToDisplay.workerStatus?.error ? 'Error' : getWorkerSummary(stateToDisplay.workerStatus)}</span>
        </div>
      )}
      {isExpanded && history.length > 0 && (
        <div className="mt-2 space-y-2">
          <div className="flex items-center space-x-1">
            <strong>History:</strong>
            {history.map((_, index) => {
              const label = index - (history.length - 1);
              return (
                <button key={index} onClick={() => setViewingIndex(index)} disabled={index === viewingIndex} className={`px-2 py-0.5 text-xs rounded ${index === viewingIndex ? 'bg-blue-600 text-white' : 'bg-gray-600 hover:bg-gray-500'}`} title={`View state from ${label === 0 ? 'now' : `${Math.abs(label)} renders ago`}`}>
                  {label === 0 ? 'Now' : label}
                </button>
              );
            })}
          </div>

          {diff && (
            <div>
              <strong>State Diff to Next:</strong>
              <DiffViewer diffData={diff} />
              <hr className="my-2 border-gray-500" />
            </div>
          )}

          <div>
            <strong>Auth Status:</strong> {stateToDisplay.authStatus?.state}
            <div className="pl-4 mt-1 space-y-1">
              {stateToDisplay.authStatus?.state === 'hasData' && (
                <>
                  <div><strong>Authenticated (Stable):</strong> {stateToDisplay.authStatus.isAuthenticated ? 'Yes' : 'No'}</div>
                  <div><strong>Last Stable Is Authenticated:</strong> {stateToDisplay.authStatus.lastStableIsAuthenticated === null ? 'N/A' : stateToDisplay.authStatus.lastStableIsAuthenticated ? 'Yes' : 'No'}</div>
                  <div><strong>Authenticated (Raw):</strong> {stateToDisplay.authStatus.isAuthenticated_RAW ? 'Yes' : 'No'}</div>
                  <div><strong>User:</strong> {stateToDisplay.authStatus.user?.email || 'None'}</div>
                  <div><strong>UID:</strong> {stateToDisplay.authStatus.user?.uid || 'N/A'}</div>
                  <div><strong>Role:</strong> {stateToDisplay.authStatus.user?.role || 'N/A'}</div>
                  <div><strong>Statbus Role:</strong> {stateToDisplay.authStatus.user?.statbus_role || 'N/A'}</div>
                  <div><strong>Refresh Needed:</strong> {stateToDisplay.authStatus.expired_access_token_call_refresh ? 'Yes' : 'No'}</div>
                </>
              )}
              {stateToDisplay.authStatus?.state === 'hasError' && <div><strong>Error:</strong> {String(stateToDisplay.authStatus.error)}</div>}
            </div>
          </div>

          <div>
            <strong>Base Data Status:</strong> {stateToDisplay.baseData?.state}
            <div className="pl-4 mt-1 space-y-1">
              {stateToDisplay.baseData?.state === 'hasData' && (
                <>
                  <div><strong>Stat Definitions:</strong> {stateToDisplay.baseData.statDefinitionsCount}</div>
                  <div><strong>External Ident Types:</strong> {stateToDisplay.baseData.externalIdentTypesCount}</div>
                  <div><strong>Statbus Users:</strong> {stateToDisplay.baseData.statbusUsersCount}</div>
                  <div><strong>Time Contexts:</strong> {stateToDisplay.baseData.timeContextsCount}</div>
                  <div><strong>Default Time Context:</strong> {stateToDisplay.baseData.defaultTimeContextIdent || 'None'}</div>
                  <div><strong>Has Statistical Units:</strong> {stateToDisplay.baseData.hasStatisticalUnits ? 'Yes' : 'No'}</div>
                </>
              )}
              {stateToDisplay.baseData?.state === 'hasError' && <div><strong>Error:</strong> {String(stateToDisplay.baseData.error)}</div>}
            </div>
          </div>

          <div>
            <strong>Search & Selection State:</strong>
            <div className="pl-4 mt-1 space-y-1">
              <div><strong>Search Text:</strong> {stateToDisplay.searchAndSelection?.searchText || 'None'}</div>
              <div><strong>Active Filters:</strong> {stateToDisplay.searchAndSelection?.activeFilterCodes?.join(', ') || 'None'}</div>
              <div><strong>Pagination:</strong> Page {stateToDisplay.searchAndSelection?.pagination?.page}, Size {stateToDisplay.searchAndSelection?.pagination?.pageSize}</div>
              <div><strong>Order:</strong> {stateToDisplay.searchAndSelection?.order?.field} {stateToDisplay.searchAndSelection?.order?.direction}</div>
              <div><strong>Selected Units:</strong> {stateToDisplay.searchAndSelection?.selectedUnitsCount}</div>
              <div><strong>Search Result:</strong> Total {stateToDisplay.searchAndSelection?.searchResult?.total ?? 'N/A'}, Loading: {stateToDisplay.searchAndSelection?.searchResult?.loading ? 'Yes' : 'No'}</div>
              {stateToDisplay.searchAndSelection?.searchResult?.error && <div><strong>Search Error:</strong> {stateToDisplay.searchAndSelection.searchResult.error}</div>}
            </div>
          </div>

          <div>
            <strong>Worker Status:</strong> {stateToDisplay.workerStatus?.loading ? 'Loading' : stateToDisplay.workerStatus?.error ? 'Error' : 'OK'}
            <div className="pl-4 mt-1 space-y-1">
              {stateToDisplay.workerStatus && !stateToDisplay.workerStatus.loading && !stateToDisplay.workerStatus.error && (
                <>
                  <div><strong>Importing:</strong> {stateToDisplay.workerStatus.isImporting === null ? 'N/A' : stateToDisplay.workerStatus.isImporting ? 'Yes' : 'No'}</div>
                  <div><strong>Deriving Units:</strong> {stateToDisplay.workerStatus.isDerivingUnits === null ? 'N/A' : stateToDisplay.workerStatus.isDerivingUnits ? 'Yes' : 'No'}</div>
                  <div><strong>Deriving Reports:</strong> {stateToDisplay.workerStatus.isDerivingReports === null ? 'N/A' : stateToDisplay.workerStatus.isDerivingReports ? 'Yes' : 'No'}</div>
                </>
              )}
              {stateToDisplay.workerStatus?.error && <div><strong>Error:</strong> {stateToDisplay.workerStatus.error}</div>}
            </div>
          </div>

          <div>
            <strong>Navigation & Redirect Debugging:</strong>
            <div className="pl-4 mt-1 space-y-1">
              <div><strong>Initial Auth Check Completed:</strong> {stateToDisplay.redirectRelevantState?.initialAuthCheckCompleted ? 'Yes' : 'No'}</div>
              <hr className="my-1 border-gray-500" />
              <div><strong>Pathname:</strong> {stateToDisplay.pathname}</div>
              <div><strong>Active Redirect Target:</strong> {(stateToDisplay.navigationState?.pendingRedirect || stateToDisplay.navigationState?.requiredSetupRedirect) || 'None'}</div>
              <div><strong>Pending Redirect:</strong> {stateToDisplay.navigationState?.pendingRedirect || 'None'}</div>
              <div><strong>Required Setup Redirect:</strong> {stateToDisplay.navigationState?.requiredSetupRedirect || 'None'}</div>
              <div><strong>Login Action in Progress:</strong> {stateToDisplay.navigationState?.loginActionInProgress ? 'Yes' : 'No'}</div>
              <div><strong>Last Known Path (pre-auth):</strong> {stateToDisplay.navigationState?.lastKnownPathBeforeAuthChange || 'None'}</div>
              <hr className="my-1 border-gray-500" />
              <div><strong>Auth Check Done:</strong> {stateToDisplay.redirectRelevantState?.authCheckDone ? 'Yes' : 'No'}</div>
              <div><strong>REST Client Ready:</strong> {stateToDisplay.redirectRelevantState?.isRestClientReady ? 'Yes' : 'No'}</div>
              <div><strong>Activity Standard:</strong> {stateToDisplay.redirectRelevantState?.activityStandard === null ? 'Null' : JSON.stringify(stateToDisplay.redirectRelevantState?.activityStandard)}</div>
              <div><strong>Number of Regions:</strong> {stateToDisplay.redirectRelevantState?.numberOfRegions === null ? 'Null/Loading' : stateToDisplay.redirectRelevantState?.numberOfRegions}</div>
              <div><strong>BaseData - Has Statistical Units:</strong> {stateToDisplay.redirectRelevantState?.baseDataHasStatisticalUnits === 'BaseDataNotLoaded' ? 'BaseDataNotLoaded' : (stateToDisplay.redirectRelevantState?.baseDataHasStatisticalUnits ? 'Yes' : 'No')}</div>
              <div><strong>BaseData - Stat Definitions Count:</strong> {stateToDisplay.redirectRelevantState?.baseDataStatDefinitionsLength}</div>
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
