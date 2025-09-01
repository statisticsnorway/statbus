"use client";

import React, { Suspense, ReactNode, useState, useRef } from 'react';
import { useGuardedEffect } from '@/hooks/use-guarded-effect';
import { Provider, atom, useAtom, useAtomValue, useSetAtom } from 'jotai';
import { atomWithRefresh, loadable, atomWithStorage } from 'jotai/utils';
import { useRouter, usePathname, useSearchParams } from 'next/navigation';
// Note: eagerAtom is not used in this reference implementation due to dev environment issues.
// import { eagerAtom } from 'jotai-eager'; 
import type { PostgrestClient } from '@supabase/postgrest-js';
import type { Database } from '@/lib/database.types';

// --- Configuration ---
const DEBUG_LOGGING = true;

// --- Helper Functions ---
const log = (...args: any[]) => {
  if (DEBUG_LOGGING) {
    console.log('[JotaiRef]', ...args);
  }
};

// --- Simplified Data Structures ---
interface SimpleAuthStatus {
  loading: boolean;
  isAuthenticated: boolean;
  expired_access_token_call_refresh: boolean;
  statusMessage: string;
  rawResponse?: any;
}

interface LocalLoginCredentials {
  email: string;
  password: string;
}

const parseSimpleAuthResponse = (rpcResponseData: any, errorObj?: any): Omit<SimpleAuthStatus, 'loading' | 'rawResponse'> => {
  log('parseSimpleAuthResponse: Parsing...', { rpcResponseData, errorObj });
  if (errorObj) {
    const result = { isAuthenticated: false, expired_access_token_call_refresh: false, statusMessage: `Error: ${errorObj.message || 'Unknown fetch error'}` };
    log('parseSimpleAuthResponse: Result (from error):', result);
    return result;
  }
  if (!rpcResponseData && !errorObj) {
    const result = { isAuthenticated: false, expired_access_token_call_refresh: false, statusMessage: "Error: No data from server (RPC success, but null data)" };
    log('parseSimpleAuthResponse: Result (no data):', result);
    return result;
  }
  const isAuthenticated = rpcResponseData?.is_authenticated ?? false;
  const expired_access_token_call_refresh = rpcResponseData?.expired_access_token_call_refresh ?? false;
  const result = {
    isAuthenticated,
    expired_access_token_call_refresh,
    statusMessage: isAuthenticated
      ? `Authenticated (User: ${rpcResponseData.email || 'N/A'})`
      : (rpcResponseData?.error_code ? `Error: ${rpcResponseData.error_code}` : "Not Authenticated"),
  };
  log('parseSimpleAuthResponse: Result (from data):', result);
  return result;
};

// --- Local Jotai Atoms (Simplified & Self-Contained) ---

const localRestClientAtom = atom<PostgrestClient<Database> | null>(null);
const localRestClientInitFailedAtom = atom<boolean>(false);

const autoRefreshOnLoadAtom = atomWithStorage<boolean>('localAutoRefreshOnLoad', true);
// This atom acts as a flag to ensure the initial auth flow (including a potential auto-refresh)
// runs only once per page load. It prevents actions like logout from re-triggering the auto-refresh logic.
// It is not persisted in storage and resets to `false` on a full page reload.
const initialAuthFlowCompletedAtom = atom(false);

// This atom acts as a single source of truth for whether the app has mounted
// on the client. This is crucial for preventing hydration issues with atoms
// that use localStorage and for preventing UI flicker.
const clientMountedAtom = atom(false);

// This atom holds the promise for the current auth status. It is written to by action atoms.
const localAuthStatusCoreAtom = atom<Promise<Omit<SimpleAuthStatus, 'loading'>>>(
  new Promise<Omit<SimpleAuthStatus, 'loading'>>(() => {}) // Start with a pending promise that never resolves
);

const localAuthStatusLoadableAtom = loadable(localAuthStatusCoreAtom);

const localAuthStatusAtom = atom<SimpleAuthStatus>((get) => {
  log('localAuthStatusAtom: Evaluating derived state.');
  const loadableState = get(localAuthStatusLoadableAtom);
  switch (loadableState.state) {
    case 'loading':
      log('localAuthStatusAtom: State is "loading".');
      return { loading: true, statusMessage: "Loading...", isAuthenticated: false, expired_access_token_call_refresh: false };
    case 'hasError':
      log('localAuthStatusAtom: State is "hasError".', loadableState.error);
      const errorData = (loadableState.error as any)?.data || (loadableState.error as any)?.error || loadableState.error;
      return { loading: false, ...parseSimpleAuthResponse(null, errorData), rawResponse: errorData };
    case 'hasData':
      log('localAuthStatusAtom: State is "hasData".', loadableState.data);
      return { loading: false, ...loadableState.data };
    default:
      log('localAuthStatusAtom: State is "unknown".');
      return { loading: true, statusMessage: "Unknown loadable state", isAuthenticated: false, expired_access_token_call_refresh: false };
  }
});

// eagerAuthStatusAtom is omitted as per findings about dev stability
// export const eagerAuthStatusAtom = eagerAtom((get) => ...);

const localPendingRedirectAtom = atom<string | null>(null);

// This atom uses localStorage to signal auth state changes across browser tabs.
// When its value is changed (e.g., on login/logout), the `storage` event notifies other tabs.
// An effect in `LocalAppInitializer` listens for these changes and triggers a refresh of the core auth status atom.
const authChangeTriggerAtom = atomWithStorage<number>('localAuthChangeTrigger', 0); // Constant initial value

// This atom tracks the timestamp of the last auth change that this tab processed.
// It's used to prevent the tab that initiated a change from re-fetching its own state.
// It starts as `null` to signify that the initial check has not yet occurred.
const lastSyncTimestampAtom = atom<number | null>(null);

// This action atom provides a race-condition-proof way to update both the local
// and cross-tab sync timestamps together.
const updateSyncTimestampAtom = atom(null, (get, set, newTimestamp: number) => {
  log('updateSyncTimestampAtom: Updating local and cross-tab sync timestamps.', { newTimestamp });
  set(lastSyncTimestampAtom, newTimestamp);
  set(authChangeTriggerAtom, newTimestamp);
});

const fetchAuthStatusAtom = atom(null, async (get, set) => {
  log('fetchAuthStatusAtom: Action triggered.');
  const client = get(localRestClientAtom);
  if (!client) {
    log('fetchAuthStatusAtom: Client not ready, setting pending promise.');
    set(localAuthStatusCoreAtom, new Promise(() => {}));
    return;
  }

  const fetchPromise = (async () => {
    log('fetchAuthStatusAtom: Client ready, fetching /rpc/auth_status...');
    const { data, error } = await client.rpc('auth_status');
    const parsedAuth = parseSimpleAuthResponse(data, error);
    return { ...parsedAuth, rawResponse: data || error };
  })();

  set(localAuthStatusCoreAtom, fetchPromise);
  await fetchPromise; // Wait for it to complete for stabilization
});

const lastIntentionalPathAtom = atom<string | null>(null);

const localLoginAtom = atom<null, [{ credentials: LocalLoginCredentials; pathname: string }], Promise<void>>(
  null,
  async (get, set, { credentials: { email, password }, pathname }) => {
    log('localLoginAtom: Attempting login with email:', email, 'for pathname:', pathname);
    const client = get(localRestClientAtom);
    if (!client) throw new Error("Login failed: Client not available.");
    try {
      // The login RPC now returns the full auth status response.
      const { data, error: rpcError } = await client.rpc('login', { email, password });

      // The response body is the new source of truth.
      const responseBody = rpcError || data;
      const newAuthStatus = parseSimpleAuthResponse(responseBody, rpcError ? responseBody : null);

      // Update state with the response from login RPC
      const oldAuthStatus = await get(localAuthStatusCoreAtom);
      set(localAuthStatusCoreAtom, Promise.resolve({ ...newAuthStatus, rawResponse: responseBody }));
      await get(localAuthStatusCoreAtom); // Stabilize

      if (newAuthStatus.isAuthenticated) {
        log('localLoginAtom: Login successful. State updated directly.');
        if (oldAuthStatus.isAuthenticated !== newAuthStatus.isAuthenticated) {
          set(updateSyncTimestampAtom, Date.now());
        }
        set(localPendingRedirectAtom, `${pathname}?event=login_success&ts=${Date.now()}`);
      } else {
        // Login failed, throw error for the form to catch.
        throw new Error(newAuthStatus.statusMessage || 'Login failed');
      }
    } catch (error) {
      log('localLoginAtom: Error during login process for pathname:', pathname, error);
      // On any error, re-fetch the auth status to be safe.
      await set(fetchAuthStatusAtom);
      throw error;
    }
  }
);

const localLogoutAtom = atom<null, [pathname: string], Promise<void>>(
  null,
  async (get, set, pathname) => {
    log('localLogoutAtom: Attempting logout for pathname:', pathname);
    const client = get(localRestClientAtom);
    if (!client) throw new Error("Logout failed: Client not available.");
    try {
      // The logout RPC now returns the full auth status response.
      const { data, error: rpcError } = await client.rpc('logout');
      
      const responseBody = rpcError || data;
      const newAuthStatus = parseSimpleAuthResponse(responseBody, rpcError ? responseBody : null);

      const oldAuthStatus = await get(localAuthStatusCoreAtom);
      set(localAuthStatusCoreAtom, Promise.resolve({ ...newAuthStatus, rawResponse: responseBody }));
      await get(localAuthStatusCoreAtom); // Stabilize

      log('localLogoutAtom: Auth state updated. Setting redirect.');
      if (oldAuthStatus.isAuthenticated !== newAuthStatus.isAuthenticated) {
        set(updateSyncTimestampAtom, Date.now());
      }
      set(localPendingRedirectAtom, `${pathname}?event=logout_success&ts=${Date.now()}`);
    } catch (error) {
      log('localLogoutAtom: Error during logout process for pathname:', pathname, error);
      // On any error, re-fetch the auth status to be safe.
      await set(fetchAuthStatusAtom);
      throw error;
    }
  }
);

const removeAccessTokenCookieAtom = atom<null, [], Promise<void>>(
  null,
  async (get, set) => {
    log('removeAccessTokenCookieAtom: Attempting to expire access token cookie.');
    const client = get(localRestClientAtom);
    if (!client) throw new Error("Client not available.");
    try {
      // This RPC call is designed for testing. It invalidates the current access token
      // but leaves the refresh token intact, simulating an expired session.
      const { error } = await client.rpc('auth_expire_access_keep_refresh');
      if (error) throw new Error(error.message || 'RPC to expire access token failed');
      log('removeAccessTokenCookieAtom: RPC success. Fetching new auth status.');
      
      await set(fetchAuthStatusAtom); // This fetches and stabilizes
      
      // No need to call updateSyncTimestampAtom here. The subsequent auto-refresh
      // will handle the sync if the auth state changes from unauthenticated to authenticated.
      
      log('removeAccessTokenCookieAtom: Auth status stabilized. AppInitializer will now attempt refresh.');
    } catch (error) {
      log('removeAccessTokenCookieAtom: Error during process:', error);
      // On error, we just re-throw. The auth state hasn't changed.
      // The UI component's catch block will handle displaying the error.
      throw error;
    }
  }
);

const refreshTokenAtom = atom<null, [], Promise<void>>(
  null,
  async (get, set) => {
    log('refreshTokenAtom: Attempting to refresh token.');
    const client = get(localRestClientAtom);
    if (!client) {
      const errorState = parseSimpleAuthResponse(null, { message: "Client not available." });
      set(localAuthStatusCoreAtom, Promise.resolve({ ...errorState, rawResponse: { error: "Client not available." } }));
      log('refreshTokenAtom: Client not available. Updated auth state to error.');
      return;
    }
    
    // Get the current auth status BEFORE the refresh call to compare later.
    const currentAuth = await get(localAuthStatusCoreAtom);

    const { data, error } = await client.rpc('refresh');
    log('refreshTokenAtom: RPC call completed.', { data, error });

    // The response body is the new source of truth.
    // For a failed RPC, the body is in the `error` object. For success, it's in `data`.
    const responseBody = error || data;
    const newAuthStatus = parseSimpleAuthResponse(responseBody, error ? responseBody : null);
    
    set(localAuthStatusCoreAtom, Promise.resolve({ ...newAuthStatus, rawResponse: responseBody }));
    
    // If the authentication status has changed (e.g., from logged out to logged in),
    // then it's a significant event that other tabs should be notified about.
    if (currentAuth.isAuthenticated !== newAuthStatus.isAuthenticated) {
      log('refreshTokenAtom: Auth status changed. Triggering cross-tab sync.');
      set(updateSyncTimestampAtom, Date.now());
    } else {
      log('refreshTokenAtom: Auth status did not change. No cross-tab sync needed.');
    }
    
    log('refreshTokenAtom: Auth state updated.');
  }
);

// --- React Components (Self-Contained) ---

const MiniFeatureFlagToggleSkeleton: React.FC<{ label: string }> = ({ label }) => {
  return (
    <div className="flex items-center space-x-2 animate-pulse">
      <label className="text-xs font-medium bg-gray-700 rounded-sm">
        <span className="opacity-0">{label}</span>
      </label>
      <div
        className="relative inline-flex h-4 w-8 flex-shrink-0 cursor-wait rounded-full border-2 border-transparent bg-gray-600"
      >
        <span
          aria-hidden="true"
          className="inline-block h-3 w-3 transform rounded-full bg-gray-500 shadow ring-0"
        />
      </div>
    </div>
  );
};

const MiniFeatureFlagToggle: React.FC<{
  atom: ReturnType<typeof atomWithStorage<boolean>>;
  label: string;
}> = ({ atom, label }) => {
  const [enabled, setEnabled] = useAtom(atom);
  return (
    <div className="flex items-center space-x-2">
      <label htmlFor="mini-auto-refresh-toggle" className="text-xs font-medium text-gray-300">
        {label}
      </label>
      <button
        id="mini-auto-refresh-toggle"
        onClick={() => setEnabled(!enabled)}
        className={`relative inline-flex h-4 w-8 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 ${
          enabled ? 'bg-indigo-500' : 'bg-gray-600'
        }`}
        role="switch"
        aria-checked={enabled}
      >
        <span
          aria-hidden="true"
          className={`inline-block h-3 w-3 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out ${
            enabled ? 'translate-x-4' : 'translate-x-0'
          }`}
        />
      </button>
    </div>
  );
};

const AuthStatusDisplay: React.FC<{ title: string; authData: SimpleAuthStatus | Omit<SimpleAuthStatus, 'loading'>; isLoading?: boolean }> = ({ title, authData, isLoading }) => {
  const currentStatus = 'loading' in authData ? (authData as SimpleAuthStatus) : { loading: isLoading ?? false, ...authData };
  return (
    <div className="p-4 border rounded mb-4">
      <h2 className="font-bold text-lg">{title}</h2>
      <p>Loading: {currentStatus.loading ? 'Yes' : 'No'}</p>
      <p>Authenticated: {currentStatus.isAuthenticated ? 'Yes' : 'No'}</p>
      <p>Status: {currentStatus.statusMessage}</p>
      <pre className="text-xs bg-gray-100 p-2 rounded mt-2 overflow-auto max-h-32">
        Raw: {JSON.stringify(currentStatus.rawResponse, null, 2)}
      </pre>
    </div>
  );
};

const AuthStatusDisplayDirect: React.FC = () => {
  const authStatus = useAtomValue(localAuthStatusAtom);
  log('AuthStatusDisplayDirect: Render. Auth status:', authStatus);
  return <AuthStatusDisplay title="Auth Status (Direct Read - Derived)" authData={authStatus} />;
};

const LocalLoginFormSkeleton: React.FC = () => {
  return (
    <div className="p-4 border rounded mb-4 space-y-3 animate-pulse">
      <div className="h-5 w-1/4 bg-gray-300 rounded" />
      <div>
        <div className="h-4 w-1/5 bg-gray-300 rounded mb-1" />
        <div className="h-8 w-full bg-gray-300 rounded" />
      </div>
      <div>
        <div className="h-4 w-1/4 bg-gray-300 rounded mb-1" />
        <div className="h-8 w-full bg-gray-300 rounded" />
      </div>
      <div className="h-8 w-20 bg-gray-300 rounded" />
    </div>
  );
};

const LocalLogoutButtonSkeleton: React.FC = () => {
  return (
    <div className="p-4 border rounded mb-4 animate-pulse">
      <div className="h-5 w-1/4 bg-gray-300 rounded mb-2" />
      <div className="h-8 w-24 bg-gray-300 rounded" />
    </div>
  );
};

const LocalRedirectHandler: React.FC = () => {
  const [redirectPath, setRedirectPath] = useAtom(localPendingRedirectAtom);
  const setLastIntentionalPath = useSetAtom(lastIntentionalPathAtom);
  const router = useRouter();
  useGuardedEffect(() => {
    if (redirectPath) {
      log(`LocalRedirectHandler: Detected redirectPath: "${redirectPath}". Navigating...`);
      setLastIntentionalPath(redirectPath);
      router.push(redirectPath);
      setRedirectPath(null);
    }
  }, [redirectPath, router, setRedirectPath, setLastIntentionalPath], 'JotaiRefPage:LocalRedirectHandler');
  return null;
};

const LocalLoginForm: React.FC = () => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const performLogin = useSetAtom(localLoginAtom);
  const pathname = usePathname();
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault(); setError(null); setIsLoading(true);
    try {
      await performLogin({ credentials: { email, password }, pathname });
      setEmail(''); setPassword('');
    } catch (err: any) { setError(err.message || 'Login failed.'); }
    finally { setIsLoading(false); }
  };
  return (
    <form onSubmit={handleSubmit} className="p-4 border rounded mb-4 space-y-3">
      <h3 className="font-semibold text-md">Login</h3>
      <div>
        <label htmlFor="ref-email" className="block text-sm font-medium">Email</label>
        <input id="ref-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required className="mt-1 block w-full px-2 py-1.5 border rounded" />
      </div>
      <div>
        <label htmlFor="ref-password" className="block text-sm font-medium">Password</label>
        <input id="ref-password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required className="mt-1 block w-full px-2 py-1.5 border rounded" />
      </div>
      {error && <p className="text-red-500 text-sm">{error}</p>}
      <button type="submit" disabled={isLoading} className="px-3 py-1.5 bg-green-500 text-white rounded hover:bg-green-600 disabled:opacity-50">
        {isLoading ? 'Logging in...' : 'Login'}
      </button>
    </form>
  );
};

const LocalLogoutButton: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const performLogout = useSetAtom(localLogoutAtom);
  const pathname = usePathname();
  const handleClick = async () => {
    setError(null); setIsLoading(true);
    try { await performLogout(pathname); }
    catch (err: any) { setError(err.message || 'Logout failed.'); }
    finally { setIsLoading(false); }
  };
  return (
    <div className="p-4 border rounded mb-4">
      <h3 className="font-semibold text-md">Logout</h3>
      {error && <p className="text-red-500 text-sm mb-2">{error}</p>}
      <button onClick={handleClick} disabled={isLoading} className="px-3 py-1.5 bg-red-500 text-white rounded hover:bg-red-600 disabled:opacity-50">
        {isLoading ? 'Logging out...' : 'Logout'}
      </button>
    </div>
  );
};

const RemoveAccessTokenButton: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const performRemove = useSetAtom(removeAccessTokenCookieAtom);
  const handleClick = async () => {
    setError(null); setIsLoading(true);
    try { await performRemove(); }
    catch (err: any) { setError(err.message || 'Failed to remove cookie.'); }
    finally { setIsLoading(false); }
  };
  return (
    <div className="flex items-center space-x-2">
      <button onClick={handleClick} disabled={isLoading} className="px-3 py-1.5 bg-yellow-500 text-white rounded hover:bg-yellow-600 disabled:opacity-50 text-sm">
        {isLoading ? 'Expiring...' : 'Expire Access Token'}
      </button>
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </div>
  );
};

const RefreshTokenButton: React.FC = () => {
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const performRefresh = useSetAtom(refreshTokenAtom);
  const handleClick = async () => {
    setError(null); setIsLoading(true);
    try { await performRefresh(); }
    catch (err: any) { setError(err.message || 'Failed to refresh token.'); }
    finally { setIsLoading(false); }
  };
  return (
    <div className="flex items-center space-x-2">
      <button onClick={handleClick} disabled={isLoading} className="px-3 py-1.5 bg-purple-500 text-white rounded hover:bg-purple-600 disabled:opacity-50 text-sm">
        {isLoading ? 'Refreshing...' : 'Refresh Auth Token'}
      </button>
      {error && <p className="text-red-500 text-sm">{error}</p>}
    </div>
  );
};

const CheckAuthStatusButton: React.FC = () => {
  const fetchAuthStatus = useSetAtom(fetchAuthStatusAtom);
  const handleClick = () => {
    log('CheckAuthStatusButton: Clicked. Triggering auth fetch.');
    fetchAuthStatus();
  };
  return (
    <button onClick={handleClick} className="px-3 py-1.5 bg-blue-500 text-white rounded hover:bg-blue-600 text-sm" title="Check Authentication Status">
      Check Auth Status
    </button>
  );
};

const LocalAppInitializer: React.FC<{ children: ReactNode }> = ({ children }) => {
  const setLocalRestClient = useSetAtom(localRestClientAtom);
  const setLocalClientInitFailed = useSetAtom(localRestClientInitFailedAtom);
  const fetchAuthStatus = useSetAtom(fetchAuthStatusAtom);
  const setClientMounted = useSetAtom(clientMountedAtom);

  // Hooks for auto-refresh logic
  const authStatus = useAtomValue(localAuthStatusAtom);
  const [initialAuthFlowCompleted, setInitialAuthFlowCompleted] = useAtom(initialAuthFlowCompletedAtom);
  const autoRefreshEnabled = useAtomValue(autoRefreshOnLoadAtom);
  const performRefresh = useSetAtom(refreshTokenAtom);
  const clientMounted = useAtomValue(clientMountedAtom);

  // Hooks for cross-tab sync
  const authChangeTimestamp = useAtomValue(authChangeTriggerAtom);
  const [lastSyncTs, setLastSyncTs] = useAtom(lastSyncTimestampAtom);

  // Effect to initialize the REST client
  useGuardedEffect(() => {
    log('LocalAppInitializer: Mount/Effect for client initialization.');
    let mounted = true;
    const initialize = async () => {
      try {
        log('LocalAppInitializer: Importing and getting browser REST client...');
        const { getBrowserRestClient } = await import('@/context/RestClientStore');
        const client = await getBrowserRestClient();
        if (mounted) {
          log('LocalAppInitializer: Client initialized successfully.');
          setLocalRestClient(client);
          setLocalClientInitFailed(false);
        }
      } catch (error) {
        if (mounted) {
          log('LocalAppInitializer: Client initialization failed.', error);
          setLocalClientInitFailed(true);
          setLocalRestClient(null);
        }
      } finally {
        if (mounted) {
          log('LocalAppInitializer: Setting clientMounted to true.');
          setClientMounted(true);
        }
      }
    };
    initialize();

    return () => {
      log('LocalAppInitializer: Unmount/Cleanup for client initialization.');
      mounted = false;
    };
  }, [setLocalRestClient, setLocalClientInitFailed, setClientMounted], 'JotaiRefPage:initializeClient');

  // useEffect for auto-refresh logic
  useGuardedEffect(() => {
    if (!clientMounted || authStatus.loading || initialAuthFlowCompleted) {
      log('LocalAppInitializer: Auto-refresh check skipped.', { clientMounted, loading: authStatus.loading, initialAuthFlowCompleted });
      return;
    }

    setInitialAuthFlowCompleted(true);

    // New refresh flow: if not authenticated but a refresh is possible, try it.
    if (!authStatus.isAuthenticated && authStatus.expired_access_token_call_refresh && autoRefreshEnabled) {
      log('LocalAppInitializer: Access token expired, refresh possible. Attempting auto-refresh...');
      performRefresh().catch(e => {
        log('LocalAppInitializer: Auto-refresh failed.', e);
      });
    }
  }, [clientMounted, authStatus, autoRefreshEnabled, initialAuthFlowCompleted, setInitialAuthFlowCompleted, performRefresh], 'JotaiRefPage:autoRefreshLogic');

  // useEffect for initial fetch and cross-tab synchronization
  useGuardedEffect(() => {
    // Don't run until the client is mounted, to ensure authChangeTimestamp is hydrated from storage.
    if (!clientMounted) {
      return;
    }
    log('LocalAppInitializer: Cross-tab sync effect triggered.', { lastSyncTs, currentTs: authChangeTimestamp });

    // This condition now handles both the initial fetch (when lastSyncTs is null)
    // and subsequent updates from other tabs.
    if (lastSyncTs === null || lastSyncTs !== authChangeTimestamp) {
      log(`LocalAppInitializer: Refreshing status. Reason: ${lastSyncTs === null ? 'Initial Load' : 'Timestamp changed'}.`);
      fetchAuthStatus();
      setLastSyncTs(authChangeTimestamp);
    } else {
      log('LocalAppInitializer: Timestamp is the same, no action needed.');
    }
  }, [clientMounted, authChangeTimestamp, lastSyncTs, setLastSyncTs, fetchAuthStatus], 'JotaiRefPage:crossTabSync');

  return <>{children}</>;
};

const UrlCleaner: React.FC = () => {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [lastIntentionalPath, setLastIntentionalPath] = useAtom(lastIntentionalPathAtom);
  useGuardedEffect(() => {
    const eventParam = searchParams.get('event');
    const tsParam = searchParams.get('ts');
    const currentQueryString = searchParams.toString();
    const currentActualPath = pathname + (currentQueryString ? `?${currentQueryString}` : '');
    if (eventParam && tsParam) {
      if (currentActualPath !== lastIntentionalPath) {
        router.replace(pathname, { scroll: false });
        setLastIntentionalPath(pathname);
      }
    } else {
      if (currentActualPath !== lastIntentionalPath) {
        setLastIntentionalPath(currentActualPath);
      }
    }
  }, [pathname, searchParams, lastIntentionalPath, setLastIntentionalPath, router], 'JotaiRefPage:UrlCleaner');
  return null;
};

// --- Main Page Component ---
const ReferencePageContent: React.FC = () => {
  log('ReferencePageContent: Render.');
  const clientMounted = useAtomValue(clientMountedAtom);

  const searchParams = useSearchParams(); // For redirect event display
  const redirectEvent = searchParams.get('event');
  const redirectTimestamp = searchParams.get('ts');

  const localClient = useAtomValue(localRestClientAtom);
  const localClientFailed = useAtomValue(localRestClientInitFailedAtom);
  const authStatus = useAtomValue(localAuthStatusAtom);

  return (
    <LocalAppInitializer>
      <LocalRedirectHandler />
      {clientMounted && <UrlCleaner />}
      <div className="container mx-auto p-4">
        {/* Status Bar */}
        <div className="bg-gray-800 text-white p-1 text-xs w-full flex justify-between items-center mb-4">
          <span>
            Local Client: {localClient ? 'INITIALIZED' : 'NOT INITIALIZED'} | Init Failed: {localClientFailed ? 'YES' : 'NO'}
          </span>
          <div className="flex items-center space-x-4">
            {clientMounted ? (
              <MiniFeatureFlagToggle
                atom={autoRefreshOnLoadAtom}
                label="Auto-Refresh on Load"
              />
            ) : (
              <MiniFeatureFlagToggleSkeleton label="Auto-Refresh on Load" />
            )}
            <CheckAuthStatusButton />
          </div>
        </div>

        <header className="mb-6">
          <h1 className="text-2xl font-bold">Jotai State Management Reference</h1>
        </header>

        {redirectEvent && (
          <div className="mb-4 p-3 bg-yellow-100 border border-yellow-300 text-yellow-700 rounded">
            Redirect event: <strong>{redirectEvent}</strong> (ts: {redirectTimestamp})
          </div>
        )}


        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          <div className="md:col-span-1">
            {authStatus.loading ? (
              <LocalLoginFormSkeleton />
            ) : authStatus.isAuthenticated ? (
              <LocalLogoutButton />
            ) : (
              <LocalLoginForm />
            )}
          </div>
          <div className="md:col-span-2">
             <AuthStatusDisplayDirect />
          </div>
        </div>

        <div className="my-6 p-4 border rounded">
          <h3 className="text-md font-semibold mb-3">Token Management for Testing</h3>
          <div className="flex flex-wrap gap-4 items-start">
            <RemoveAccessTokenButton />
            <RefreshTokenButton />
          </div>
          <p className="text-xs mt-3 text-gray-600">
            Use &apos;Expire Access Token&apos; to simulate an expired token. The next call to &apos;Check Auth Status&apos; will reveal that a refresh is needed.
            The system should then automatically use the refresh token to get a new access token.
            You can also manually trigger this with &apos;Refresh Auth Token&apos;.
          </p>
        </div>

        <div className="my-6 p-4 border rounded bg-blue-50 border-blue-200">
          <h3 className="text-md font-semibold mb-2">Test Cross-Tab Synchronization</h3>
          <p className="text-sm mb-2">
            Click the link below to open this same reference page in a new browser tab.
            If you log in or out in one tab, the authentication status (and login/logout form)
            should automatically update in the other tab. This is handled by the <code>authChangeTriggerAtom</code>
            (an <code>atomWithStorage</code> using <code>localStorage</code>) and the listening logic in <code>LocalAppInitializer</code>.
          </p>
          <a
            href="/jotai-state-management-reference"
            target="_blank"
            rel="noopener noreferrer"
            className="text-blue-600 hover:text-blue-800 underline font-medium"
          >
            Open this page in a new tab
          </a>
        </div>

        <main>
          {/* Descriptive Text from original reference page */}
          <div>
            <h2 className="text-xl font-semibold mb-4 mt-6">Jotai Reference: Direct Read Pattern & Best Practices</h2>
            <p className="mb-2 text-sm">
              This page serves as a reference implementation, demonstrating the most stable patterns
              identified through testing for handling asynchronous Jotai state, client-side effects,
              and complex UI interactions like login/logout, redirects, and cross-tab synchronization.
            </p>
            <div className="prose prose-sm mt-4 p-4 border rounded bg-gray-50">
              <h3>Core Pattern: Direct Read of Derived Loadable State</h3>
              <p>
                The <code>AuthStatusDisplayDirect</code> component (defined within this file) uses <code>localAuthStatusAtom</code>.
                This <code>localAuthStatusAtom</code> is a simple derived atom: <code>atom((get) =&gt; ...)</code>.
                It reads from <code>localAuthStatusLoadableAtom</code>, which is <code>loadable(localAuthStatusCoreAtom)</code>.
                <code>localAuthStatusCoreAtom</code> is a simple promise atom: <code>atom&lt;Promise&lt;...&gt;&gt;(...)</code>.
                It holds the promise for the current auth status. It is not an async atom itself; instead, it is written to by the <code>fetchAuthStatusAtom</code> action atom, which performs the actual asynchronous fetch.
              </p>
              <p><em>Why this pattern is preferred:</em></p>
              <ol>
                <li><strong>Stability:</strong> This &quot;direct read&quot; approach has proven to be the most stable across
                   both development (<code>pnpm dev</code>) and production-like environments during our tests.</li>
                <li><strong>Simplicity:</strong> It avoids the complexities and potential pitfalls of React Suspense
                   when the underlying promises or atom states have subtle interactions with
                   development tooling (HMR, Fast Refresh), which were observed to cause hangs or infinite loading spinners.</li>
                <li><strong>Explicit State Handling:</strong> The <code>loadable</code> utility provides clear <code>loading</code>, <code>hasData</code>,
                   and <code>hasError</code> states. These are then explicitly handled in <code>localAuthStatusAtom</code>
                   and can be consumed directly by UI components like <code>AuthStatusDisplayDirect</code> without needing Suspense boundaries for this specific piece of state.</li>
              </ol>

              <h3>Key Supporting Mechanisms (all self-contained in this file)</h3>
              <p>
                This page is self-contained. All necessary atoms and components are defined within this file.
                The key mechanisms are:
              </p>
              <ul>
                <li><strong>Client Initialization (<code>LocalAppInitializer</code>):</strong>
                  Handles asynchronous setup of client-side resources (e.g., REST client).
                  <code>localAuthStatusCoreAtom</code> depends on this client and will suspend (return a
                  non-resolving promise via <code>new Promise(() =&gt; &#123;&#125;)</code>) until the client is available. This is crucial for correct initial loading behavior.</li>
                <li><strong>Login/Logout Logic (<code>LocalLoginForm</code>, <code>LocalLogoutButton</code>, action atoms <code>localLoginAtom</code>, <code>localLogoutAtom</code>):</strong>
                  Action atoms encapsulate API calls and subsequent state updates.
                  <em>IMPORTANT:</em> After an action that changes auth state (like login or logout), these atoms call <code>await set(fetchAuthStatusAtom)</code>.
                  This action atom is responsible for both fetching the new status and waiting for the fetch to complete,
                  ensuring the core auth state is fully refreshed and stable before proceeding with side effects like setting a redirect path. This prevents acting on stale state.</li>
                <li><strong>Controlled Client-Side Redirects (<code>LocalRedirectHandler</code>, <code>localPendingRedirectAtom</code>):</strong>
                  Actions set <code>localPendingRedirectAtom</code> with the target path.
                  <code>LocalRedirectHandler</code> (a simple component) observes this atom using <code>useAtom</code> and performs navigation using <code>router.push()</code>.
                  This centralizes redirect logic and makes it a controlled, testable reaction to state changes.</li>
                <li><strong>URL Parameter Cleaning (<code>UrlCleaner</code>, <code>lastIntentionalPathAtom</code>):</strong>
                  Manages transient URL parameters (like <code>event</code>, <code>ts</code> from login/logout redirects). It removes them on page load/refresh if they
                  are &quot;stale&quot; (i.e., not from an immediately preceding client-side event), but preserves them right after an event.
                  <code>lastIntentionalPathAtom</code> tracks the &quot;intended&quot; URL state (either clean or with fresh event params).
                  This component is conditionally rendered using an <code>isClient</code> state flag to ensure its router hooks only run client-side.</li>
                <li><strong>Cross-Tab Synchronization (<code>authChangeTriggerAtom</code>, logic in <code>LocalAppInitializer</code>):</strong>
                  <code>authChangeTriggerAtom</code> is an <code>atomWithStorage</code> using <code>localStorage</code>. It stores a timestamp that is updated upon login, logout, or manual refresh.
                  <code>LocalAppInitializer</code> in each tab listens to this atom. If the timestamp changes (indicating an action in another tab), it calls <code>fetchAuthStatus()</code>
                  to update its local view of the auth state.
                  To prevent re-fetching on the tab that initiated the change, a separate state atom (<code>lastSyncTimestampAtom</code>) tracks the last timestamp this tab processed. The fetch is only triggered if the timestamp from storage is different.</li>
              </ul>

              <h3>Pitfalls and Anti-Patterns Observed (and Solutions Implemented Here)</h3>
              <ul>
                <li><strong>React Suspense with <code>key</code> prop (previously in <code>/test/suspense-key</code>):</strong>
                  <p><em>Problem:</em> Caused infinite loading spinners in the browser tab in the dev environment,
                  even with dynamic keys (e.g., <code>key=&#123;loadableAuth.state + Date.now()&#125;</code>).</p>
                  <p><em>Reason:</em> Likely due to interactions between Suspense, <code>atomWithRefresh</code>, <code>loadable</code>,
                  and development server tooling (HMR/Fast Refresh) causing rapid state changes or
                  unstable promise identities that confuse the Suspense boundary.</p>
                  <p><em>Solution:</em> The direct read pattern used here avoids Suspense for the auth display itself.</p>
                </li>
                <li><strong><code>jotai-eager</code> (previously in <code>/test/eager</code>):</strong>
                  <p><em>Problem:</em> In the dev environment, this page would hang indefinitely. Critically, its
                  presence would stall all other test tabs, preventing them from loading or completing
                  login/logout until the <code>/test/eager</code> tab was closed.</p>
                  <p><em>Reason:</em> <code>eagerAtom</code>&apos;s mechanism for managing sync/async transitions, especially with
                  <code>atomWithRefresh</code>, seemed to create severe contention or deadlocks under the conditions
                  of the development server, possibly related to HMR or how it handles shared state
                  across multiple &quot;instances&quot; or refreshes of the atom graph.</p>
                  <p><em>Solution:</em> Avoid <code>eagerAtom</code> for this core authentication flow if such dev environment
                  instability is observed. The direct read pattern is more predictable.</p>
                </li>
                <li><strong>Hydration Errors:</strong>
                  <p><em>Problem:</em> Mismatches between server-rendered HTML and client-side React rendering.</p>
                  <p><em>Causes & Solutions:</em></p>
                  <ul>
                    <li><code>atomWithStorage</code> initial value: Using <code>Date.now()</code> as the default initial value for
                       <code>atomWithStorage(&apos;key&apos;, Date.now())</code> caused mismatches because <code>Date.now()</code> differs
                       between server and client. Solution: Use a constant initial value (e.g., <code>0</code> for <code>authChangeTriggerAtom</code>).</li>
                    <li><code>className</code> mismatches: Ensure CSS classes are consistent between server and client renders. (Not an issue in this self-contained page, but observed in earlier test layouts).</li>
                    <li>Client-only hooks (<code>useRouter</code>, <code>usePathname</code>, <code>useSearchParams</code>): Components using these
                       (like <code>UrlCleaner</code>, <code>LocalLoginForm</code>, <code>LocalLogoutButton</code>, <code>LocalRedirectHandler</code>) must be part of a client component tree (marked with <code>&quot;use client&quot;;</code>). If they are part of a component that might be server-rendered initially (like a layout child), they might need to be conditionally rendered to only execute on the client
                       (e.g., using an <code>isClient</code> state set in <code>useEffect</code>, as done for <code>UrlCleaner</code> in this reference).</li>
                  </ul>
                </li>
                <li><strong>Jotai Provider Scope:</strong>
                  <p><em>Problem:</em> Components (even layout components) trying to read atom state before or outside
                  the scope of the <code>&lt;Provider&gt;</code> that manages that state will get default/incorrect values.</p>
                  <p><em>Solution:</em> Ensure the component consuming atoms is a descendant of the relevant <code>&lt;Provider&gt;</code>.
                  This page demonstrates this by having a root <code>JotaiStateManagementReferencePage</code> component that sets up the <code>&lt;Provider&gt;</code>,
                  and an inner <code>ReferencePageContent</code> component (rendered by the root) that contains all the actual layout structure
                  and atom consumption logic.</p>
                </li>
              </ul>
            </div>
          </div>
        </main>
      </div>
    </LocalAppInitializer>
  );
};

export default function JotaiStateManagementReferencePage() {
  log('JotaiStateManagementReferencePage: Setting up Provider.');
  return (
    <Provider>
      <ReferencePageContent />
    </Provider>
  );
}
