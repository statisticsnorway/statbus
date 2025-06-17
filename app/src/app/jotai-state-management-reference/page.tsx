"use client";

import React, { Suspense, useEffect, ReactNode, useState, useRef } from 'react';
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
  statusMessage: string;
  rawResponse?: any;
}

interface LocalLoginCredentials {
  email: string;
  password: string;
}

const parseSimpleAuthResponse = (rpcResponseData: any, errorObj?: any): Omit<SimpleAuthStatus, 'loading' | 'rawResponse'> => {
  if (errorObj) {
    return { statusMessage: `Error: ${errorObj.message || 'Unknown fetch error'}` };
  }
  if (!rpcResponseData && !errorObj) {
    return { statusMessage: "Error: No data from server (RPC success, but null data)" };
  }
  const isAuthenticated = rpcResponseData?.is_authenticated ?? false;
  return {
    statusMessage: isAuthenticated
      ? `Authenticated (User: ${rpcResponseData.email || 'N/A'})`
      : (rpcResponseData?.error_code ? `Error: ${rpcResponseData.error_code}` : "Not Authenticated"),
  };
};

// --- Local Jotai Atoms (Simplified & Self-Contained) ---

const localRestClientAtom = atom<PostgrestClient<Database> | null>(null);
const localRestClientInitFailedAtom = atom<boolean>(false);

const localAuthStatusCoreAtom = atomWithRefresh<Promise<Omit<SimpleAuthStatus, 'loading'>>>(async (get) => {
  log('localAuthStatusCoreAtom: Evaluation triggered.');
  const client = get(localRestClientAtom);
  const clientInitFailed = get(localRestClientInitFailedAtom);

  if (!client) {
    if (clientInitFailed) {
      log('localAuthStatusCoreAtom: Local REST client initialization previously failed. Returning error state.');
      return { statusMessage: "Error: Local client init failed", rawResponse: { error: "Local client init failed" } };
    }
    log('localAuthStatusCoreAtom: No REST client (and not yet marked as failed). Suspending.');
    return new Promise(() => {});
  }

  log('localAuthStatusCoreAtom: Client available. Fetching /rpc/auth_status...');
  try {
    const { data, error } = await client.rpc('auth_status');
    log('localAuthStatusCoreAtom: RPC response:', { data, error });
    return { ...parseSimpleAuthResponse(data, error), rawResponse: data || error };
  } catch (e: any) {
    log('localAuthStatusCoreAtom: Exception during fetch:', e);
    return { statusMessage: `Error: ${e.message || 'Fetch exception'}`, rawResponse: { exception: e } };
  }
});

const localAuthStatusLoadableAtom = loadable(localAuthStatusCoreAtom);

const localAuthStatusAtom = atom<SimpleAuthStatus>((get) => {
  const loadableState = get(localAuthStatusLoadableAtom);
  switch (loadableState.state) {
    case 'loading':
      return { loading: true, statusMessage: "Loading..." };
    case 'hasError':
      log('localAuthStatusAtom: Loadable in error state.', loadableState.error);
      const errorData = (loadableState.error as any)?.data || (loadableState.error as any)?.error || loadableState.error;
      return { loading: false, ...parseSimpleAuthResponse(null, errorData), rawResponse: errorData };
    case 'hasData':
      return { loading: false, ...loadableState.data };
    default:
      return { loading: true, statusMessage: "Unknown loadable state" };
  }
});

// eagerAuthStatusAtom is omitted as per findings about dev stability
// export const eagerAuthStatusAtom = eagerAtom((get) => ...);

const localPendingRedirectAtom = atom<string | null>(null);

const authChangeTriggerAtom = atomWithStorage<number>('localAuthChangeTrigger', 0); // Constant initial value

const lastIntentionalPathAtom = atom<string | null>(null);

const localLoginAtom = atom<null, [{ credentials: LocalLoginCredentials; pathname: string }], Promise<void>>(
  null,
  async (get, set, { credentials: { email, password }, pathname }) => {
    log('localLoginAtom: Attempting login with email:', email, 'for pathname:', pathname);
    const client = get(localRestClientAtom);
    if (!client) throw new Error("Login failed: Client not available.");
    try {
      const { error: loginError } = await client.rpc('login', { email, password });
      if (loginError) throw new Error(loginError.message || 'Login RPC failed');
      set(localAuthStatusCoreAtom);
      await get(localAuthStatusCoreAtom);
      set(authChangeTriggerAtom, Date.now());
      set(localPendingRedirectAtom, `${pathname}?event=login_success&ts=${Date.now()}`);
    } catch (error) {
      log('localLoginAtom: Error during login process for pathname:', pathname, error);
      set(localAuthStatusCoreAtom); // Ensure status reflects reality
      await get(localAuthStatusCoreAtom);
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
      const { error: logoutError } = await client.rpc('logout');
      if (logoutError) throw new Error(logoutError.message || 'Logout RPC failed');
      await new Promise(resolve => setTimeout(resolve, 50)); // Allow cookie processing
      set(localAuthStatusCoreAtom);
      await get(localAuthStatusCoreAtom);
      set(authChangeTriggerAtom, Date.now());
      set(localPendingRedirectAtom, `${pathname}?event=logout_success&ts=${Date.now()}`);
    } catch (error) {
      log('localLogoutAtom: Error during logout process for pathname:', pathname, error);
      set(localAuthStatusCoreAtom); // Ensure status reflects reality
      await get(localAuthStatusCoreAtom);
      throw error;
    }
  }
);

// --- React Components (Self-Contained) ---

const AuthStatusDisplay: React.FC<{ title: string; authData: SimpleAuthStatus | Omit<SimpleAuthStatus, 'loading'>; isLoading?: boolean }> = ({ title, authData, isLoading }) => {
  const currentStatus = 'loading' in authData ? (authData as SimpleAuthStatus) : { loading: isLoading ?? false, ...authData };
  return (
    <div className="p-4 border rounded mb-4">
      <h2 className="font-bold text-lg">{title}</h2>
      <p>Loading: {currentStatus.loading ? 'Yes' : 'No'}</p>
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

const LocalRedirectHandler: React.FC = () => {
  const [redirectPath, setRedirectPath] = useAtom(localPendingRedirectAtom);
  const setLastIntentionalPath = useSetAtom(lastIntentionalPathAtom);
  const router = useRouter();
  useEffect(() => {
    if (redirectPath) {
      log(`LocalRedirectHandler: Detected redirectPath: "${redirectPath}". Navigating...`);
      setLastIntentionalPath(redirectPath);
      router.push(redirectPath);
      setRedirectPath(null);
    }
  }, [redirectPath, router, setRedirectPath, setLastIntentionalPath]);
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

const TriggerRefreshButton: React.FC = () => {
  const refreshAuth = useSetAtom(localAuthStatusCoreAtom);
  const setAuthTrigger = useSetAtom(authChangeTriggerAtom);
  const handleClick = () => {
    refreshAuth(); setAuthTrigger(Date.now());
  };
  return (
    <button onClick={handleClick} className="px-3 py-1.5 bg-blue-500 text-white rounded hover:bg-blue-600 text-sm" title="Refresh Authentication Status">
      Refresh Auth Status
    </button>
  );
};

const LocalAppInitializer: React.FC<{ children: ReactNode }> = ({ children }) => {
  const setLocalRestClient = useSetAtom(localRestClientAtom);
  const setLocalClientInitFailed = useSetAtom(localRestClientInitFailedAtom);
  const authChangeTimestamp = useAtomValue(authChangeTriggerAtom);
  const refreshAuthStatus = useSetAtom(localAuthStatusCoreAtom);
  const initialTimestampRef = useRef<number | null>(null);
  const hasMountedRef = useRef(false);

  useEffect(() => {
    let mounted = true;
    const initializeClient = async () => {
      try {
        const { getBrowserRestClient } = await import('@/context/RestClientStore');
        const client = await getBrowserRestClient();
        if (mounted) { setLocalRestClient(client); setLocalClientInitFailed(false); }
      } catch (error) {
        if (mounted) { setLocalClientInitFailed(true); setLocalRestClient(null); }
      }
    };
    initializeClient();
    return () => { mounted = false; };
  }, [setLocalRestClient, setLocalClientInitFailed]);

  useEffect(() => {
    if (!hasMountedRef.current) {
      initialTimestampRef.current = authChangeTimestamp;
      hasMountedRef.current = true;
      return;
    }
    if (initialTimestampRef.current !== authChangeTimestamp) {
      refreshAuthStatus();
      initialTimestampRef.current = authChangeTimestamp;
    }
  }, [authChangeTimestamp, refreshAuthStatus]);

  return <>{children}</>;
};

const UrlCleaner: React.FC = () => {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [lastIntentionalPath, setLastIntentionalPath] = useAtom(lastIntentionalPathAtom);
  useEffect(() => {
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
  }, [pathname, searchParams, lastIntentionalPath, setLastIntentionalPath, router]);
  return null;
};

// --- Main Page Component ---
const ReferencePageContent: React.FC = () => {
  log('ReferencePageContent: Render.');
  const [isClient, setIsClient] = useState(false);
  useEffect(() => { setIsClient(true); }, []);

  const searchParams = useSearchParams(); // For redirect event display
  const redirectEvent = searchParams.get('event');
  const redirectTimestamp = searchParams.get('ts');

  const localClient = useAtomValue(localRestClientAtom);
  const localClientFailed = useAtomValue(localRestClientInitFailedAtom);
  const authStatus = useAtomValue(localAuthStatusAtom);

  return (
    <LocalAppInitializer>
      <LocalRedirectHandler />
      {isClient && <UrlCleaner />}
      <div className="container mx-auto p-4">
        {/* Status Bar */}
        <div className="bg-gray-800 text-white p-1 text-xs w-full flex justify-between items-center mb-4">
          <span>
            Local Client: {localClient ? 'INITIALIZED' : 'NOT INITIALIZED'} | Init Failed: {localClientFailed ? 'YES' : 'NO'}
          </span>
          <TriggerRefreshButton />
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
            {authStatus.statusMessage.startsWith('Authenticated') ? (
              <LocalLogoutButton />
            ) : (
              <LocalLoginForm />
            )}
          </div>
          <div className="md:col-span-2">
             <AuthStatusDisplayDirect />
          </div>
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
                <code>localAuthStatusCoreAtom</code> is an <code>atomWithRefresh(async (get) =&gt; ...)</code>, responsible for the actual asynchronous fetch of authentication status.
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
                  <em>IMPORTANT:</em> After an action that changes auth state (like login or logout), these atoms first call <code>set(localAuthStatusCoreAtom)</code> to trigger a refresh,
                  AND then <code>await get(localAuthStatusCoreAtom)</code> to ensure the core auth state is fully refreshed
                  and stable before proceeding with side effects like setting a redirect path. This prevents acting on stale state.</li>
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
                  <code>LocalAppInitializer</code> in each tab listens to this atom. If the timestamp changes (indicating an action in another tab), it calls <code>refreshAuthStatus()</code>
                  (which is <code>set(localAuthStatusCoreAtom)</code>) to update its local view of the auth state.
                  <code>useRef</code> hooks (<code>hasMountedRef</code>, <code>initialTimestampRef</code>) are used to prevent this effect from firing on initial hydration from localStorage, only on subsequent changes.</li>
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
                 <li><strong>Initial Value of <code>atomWithStorage</code> and <code>useEffect</code> for Synchronization:</strong>
                  <p><em>Problem:</em> <code>useEffect</code> listening to an <code>atomWithStorage</code> might trigger on initial hydration
                  from <code>localStorage</code>, causing an unnecessary action (e.g., an extra auth refresh).</p>
                  <p><em>Solution:</em> Use <code>useRef</code> (e.g., <code>hasMountedRef</code>, <code>initialTimestampRef</code> in <code>LocalAppInitializer</code>)
                  to distinguish between the initial hydration of the atom&apos;s value from storage and subsequent
                  changes to that value (which should trigger the desired effect).</p>
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
