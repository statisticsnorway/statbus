"use client";

/**
 * Auth Atoms and Hooks
 *
 * This file contains atoms and hooks related to user authentication,
 * session management, and identity.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable, createJSONStorage } from 'jotai/utils'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { createMachine, assign } from 'xstate'
import { atomWithMachine } from 'jotai-xstate'
import { atomEffect } from 'jotai-effect'
import type { Loadable } from 'jotai/vanilla/utils/loadable'

import { type User, type AuthStatus as CoreAuthStatus, _parseAuthStatusRpcResponseToAuthStatus } from '@/lib/auth.types';
import type { Database, Tables, TablesInsert } from '@/lib/database.types'
import {
  importStateAtom,
  initialImportState,
  unitCountsAtom,
} from './import'
import { gettingStartedUIStateAtom } from './getting-started'
import {
  searchStateAtom,
  initialSearchStateValues,
  searchResultAtom,
  selectedUnitsAtom,
  tableColumnsAtom,
} from './search'
import { refreshWorkerStatusAtom } from './worker_status'
import { pendingRedirectAtom } from './app'
import { restClientAtom } from './rest-client'

// ============================================================================
// AUTH ATOMS - Replace AuthStore + AuthContext
// ============================================================================

export { _parseAuthStatusRpcResponseToAuthStatus };
export type { User };

export interface ClientAuthStatus extends CoreAuthStatus {
  loading: boolean;
}

// Base auth atom - holds the promise for the current auth status.
// It starts with a non-resolving promise to represent the initial "loading" state.
export const authStatusPromiseAtom = atom<Promise<CoreAuthStatus>>(
  new Promise<CoreAuthStatus>(() => {})
);

// Action atom to fetch the auth status. This is the ONLY place the API call is made.
export const fetchAuthStatusAtom = atom(null, async (get, set) => {
  const client = get(restClientAtom);
  const isClientSide = typeof window !== 'undefined';

  // Get the current auth status *before* fetching to compare later.
  // We read the synchronous derived atom `authStatusUnstableDetailsAtom` to get the current state
  // without blocking, which is crucial on initial load when `authStatusPromiseAtom` is an
  // unresolved promise.
  const oldAuthStatus = get(authStatusUnstableDetailsAtom);

  if (!client) {
    if (isClientSide) {
      set(authStatusPromiseAtom, new Promise(() => {}));
    } else {
      set(authStatusPromiseAtom, Promise.resolve({ isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'CLIENT_NOT_READY_SSR' }));
    }
    return;
  }

  const fetchPromise = (async () => {
    try {
      const { data, error, status, statusText } = await client.rpc("auth_status");

      if (error) {
        const errorMessage = (error as any)?.message || "No error message";
        console.error(`fetchAuthStatusAtom: Auth status check RPC failed. Status: ${status}, StatusText: ${statusText}, ErrorMessage: ${errorMessage}`, error);
        return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'RPC_ERROR' };
      }
      return _parseAuthStatusRpcResponseToAuthStatus(data);
    } catch (e) {
      console.error("fetchAuthStatusAtom: Exception during auth status fetch:", e);
      return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'FETCH_ERROR' };
    }
  })();

  set(authStatusPromiseAtom, fetchPromise);
  const newAuth = await fetchPromise; // Wait for it to complete for stabilization before the action resolves.

  // After stabilizing, compare old and new auth states and trigger sync if needed.
  // We check that the old status was not loading to avoid triggering on the very first load.
  if (!oldAuthStatus.loading && oldAuthStatus.isAuthenticated !== newAuth.isAuthenticated) {
    set(updateSyncTimestampAtom, Date.now());
  }
});

export const authStatusLoadableAtom = loadable(authStatusPromiseAtom);

// Derived atoms for easier access

// Unstable details atom that correctly interprets the loadable state, including stale data.
export const authStatusUnstableDetailsAtom = atom<ClientAuthStatus>(
  (get): ClientAuthStatus => {
    const loadableState = get(authStatusLoadableAtom);
    if (loadableState.state === 'loading') {
      // Preserve stale data if available to prevent UI flapping during re-fetches.
      const staleData = (loadableState as { data?: CoreAuthStatus }).data;
      if (staleData) {
        return { loading: true, ...staleData };
      }
      return { loading: true, isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: null };
    }
    if (loadableState.state === 'hasError') {
      // Assuming the error in loadableState.error might be relevant, but AuthStatus needs a specific error_code field.
      // For simplicity, setting a generic error_code here.
      return { loading: false, isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'LOADABLE_ERROR' };
    }
    const data: CoreAuthStatus = loadableState.data; // No need for ?? if hasData implies data exists
    return { loading: false, ...data };
  }
);

// A derived atom that provides a "stabilized" authentication status.
// It prevents rapid "flapping" from true -> false -> true during token refresh.
// This is the primary atom to use for checking authentication status.
export const isAuthenticatedAtom = atom(get => {
    const unstableStatus = get(authStatusUnstableDetailsAtom);
    // This atom now provides the "stabilized" status by deriving from authStatusUnstableDetailsAtom,
    // which correctly handles stale data during loading.
    return unstableStatus.isAuthenticated || unstableStatus.expired_access_token_call_refresh;
});

/**
 * The primary, recommended atom for auth state.
 * It combines the detailed status (user, loading state, etc.) with the
 * STABILIZED `isAuthenticated` boolean, providing the best of both worlds.
 * This should be the default choice for most UI components.
 */
export const authStatusAtom = atom((get) => {
  const unstableStatus = get(authStatusUnstableDetailsAtom);
  const isAuthenticated = get(isAuthenticatedAtom); // The stabilized version
  return {
    ...unstableStatus,
    isAuthenticated, // Overwrite the raw value with the stable one
  };
});
export const currentUserAtom = atom((get) => get(authStatusUnstableDetailsAtom).user);
export const expiredAccessTokenAtom = atom((get) => get(authStatusUnstableDetailsAtom).expired_access_token_call_refresh);

// ============================================================================
// AUTH-RELATED APP STATE ATOMS
// ============================================================================

// Atom to signal that a login action is in progress. This helps coordinate
// state cleanup after a successful login redirect.
export const isLoginActionInProgressAtom = atom(false);

// Atom to signal auth events across tabs
export const authChangeTriggerAtom = atomWithStorage('authChangeTrigger', 0);

// Atom to track the last timestamp this specific tab has processed.
export const lastSyncTimestampAtom = atom<number | null>(null);

// Action atom to update both local and cross-tab sync timestamps together.
export const updateSyncTimestampAtom = atom(null, (get, set, newTimestamp: number) => {
  set(lastSyncTimestampAtom, newTimestamp);
  set(authChangeTriggerAtom, newTimestamp);
});

// Atom to store the last known path before an auth change forced a redirect to /login
// Using sessionStorage to make it per-tab and survive hard reloads.
export const lastKnownPathBeforeAuthChangeAtom = atomWithStorage<string | null>(
  'lastKnownPathBeforeAuthChange',
  null,
  createJSONStorage(() => sessionStorage)
);

// State machine for the login page boundary logic.
export const loginPageMachine = createMachine({
  id: 'loginPageBoundary',
  initial: 'idle',
  // The context will hold the data needed for decisions.
  context: {
    isAuthenticated: false,
    isOnLoginPage: false,
  },
  states: {
    idle: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign({
            isAuthenticated: ({ event }) => event.context.isAuthenticated,
            isOnLoginPage: ({ event }) => event.context.isOnLoginPage,
          }),
        },
      },
    },
    evaluating: {
      always: [
        {
          target: 'finalizing',
          guard: ({ context }) => context.isAuthenticated && context.isOnLoginPage,
        },
        {
          target: 'showingForm',
        },
      ],
    },
    finalizing: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign({
            isAuthenticated: ({ event }) => event.context.isAuthenticated,
            isOnLoginPage: ({ event }) => event.context.isOnLoginPage,
          }),
        },
      },
    },
    showingForm: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign({
            isAuthenticated: ({ event }) => event.context.isAuthenticated,
            isOnLoginPage: ({ event }) => event.context.isOnLoginPage,
          }),
        },
      },
    },
  },
  // A global RESET event can bring the machine back to 'idle' from any state.
  on: {
    RESET: {
      target: '.idle',
    },
  },
});

export const loginPageMachineAtom = atomWithMachine((get) => {
  // The machine is re-created if its dependencies change, but its state is preserved by Jotai.
  // We don't need any dependencies from `get` for this machine's definition.
  return loginPageMachine;
});

// ============================================================================
// ASYNC AUTH ACTION ATOMS
// ============================================================================

export const loginAtom = atom(
  null,
  async (get, set, { credentials, nextPath }: { credentials: { email: string; password: string }, nextPath: string | null }) => {
    const oldAuthStatus = get(authStatusUnstableDetailsAtom);
    // No need to manually set loading states on authStatusUnstableDetailsAtom now.
    // Components will observe authStatusLoadableAtom.
    const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
    const loginUrl = `${apiUrl}/rest/rpc/login`;

    try {
      const response = await fetch(loginUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ email: credentials.email, password: credentials.password }),
        credentials: 'include' // Crucial for Set-Cookie to be processed by the browser
      });

      let responseData: any;
      try {
        responseData = await response.json();
      } catch (jsonError) {
        // Handle cases where response body is not JSON or empty
        if (!response.ok) {
          // If the request failed (e.g. 401) and body is not JSON
          const errorMsg = `Login failed: Server error ${response.status}. Non-JSON response.`;
          console.error(`[loginAtom] ${errorMsg}`);
          throw new Error(errorMsg, { cause: 'SERVER_NON_JSON_ERROR' });
        }
        // If response.ok but body is not JSON (unexpected for /rpc/login)
        const errorMsg = 'Login failed: Invalid non-JSON response from server despite OK status.';
        console.error('[loginAtom] Login response OK, but failed to parse JSON body:', jsonError, errorMsg);
        throw new Error(errorMsg, { cause: 'CLIENT_INVALID_JSON_RESPONSE' });
      }

      if (!response.ok) {
        // response.ok is false (e.g., 401). responseData should contain error_code.
        const serverMessage = responseData?.message; // Optional: if backend provides a human-readable message
        const errorCode = responseData?.error_code;
        // Use server message if available, otherwise a generic message.
        // LoginForm.tsx will use loginErrorMessages based on errorCode for user display.
        const displayMessage = serverMessage || `Login failed with status: ${response.status}`;

        console.error(`[loginAtom] Login fetch not OK: ${displayMessage}`, errorCode ? `Error Code: ${errorCode}` : '');
        throw new Error(displayMessage, { cause: errorCode || 'UNKNOWN_LOGIN_FAILURE' });
      }

      // If response.ok (HTTP 200)
      // According to docs, responseData should have is_authenticated: true and error_code: null.
      // This block handles a deviation: 200 OK but payload indicates failure.
      if (responseData && responseData.is_authenticated === false && responseData.error_code) {
        const errorCode = responseData.error_code;
        const serverMessage = responseData.message;
        // Use loginErrorMessages from LoginForm.tsx, or server message, or default.
        // This requires loginErrorMessages to be accessible here or duplicated.
        // For simplicity, we'll use a generic message and rely on the cause.
        const displayMessage = serverMessage || `Login indicated failure despite 200 OK. Error: ${errorCode}`;
        console.warn(`[loginAtom] Login response OK (200), but payload indicates failure. Error Code: ${errorCode}. Message: ${displayMessage}`);
        throw new Error(displayMessage, { cause: errorCode });
      }

      // Successfully authenticated (200 OK and is_authenticated: true implied or explicit from responseData)
      // After successful login, the backend sets cookies.

      // Signal that a login action is in progress. This is read by LoginClientBoundary
      // and RedirectHandler to orchestrate a clean redirect and state cleanup after
      // the auth state has been updated.
      set(isLoginActionInProgressAtom, true);

      // Update auth status directly from login response. The redirect will be triggered
      // reactively by LoginClientBoundary when it sees the auth state change.
      const newAuthStatus = _parseAuthStatusRpcResponseToAuthStatus(responseData);
      set(authStatusPromiseAtom, Promise.resolve(newAuthStatus));
      await get(authStatusPromiseAtom); // Stabilize

      // Trigger cross-tab sync if we transitioned from unauthenticated to authenticated.
      if (!oldAuthStatus.loading && !oldAuthStatus.isAuthenticated && newAuthStatus.isAuthenticated) {
        set(updateSyncTimestampAtom, Date.now());
      }

    } catch (error) {
      console.error('[loginAtom] Login attempt failed.'); // Less verbose for production
      // Refresh to ensure we have the latest (likely unauthenticated) status.
      await set(fetchAuthStatusAtom); // Also await here for consistency on error path
      throw error; // Re-throw to be caught by LoginForm.tsx
    }
  }
)

export const clientSideRefreshAtom = atom<null, [], Promise<void>>(
  null,
  async (get, set) => {
    const client = get(restClientAtom);
    if (!client) {
      const errorState = _parseAuthStatusRpcResponseToAuthStatus({ error_code: "CLIENT_NOT_AVAILABLE" });
      set(authStatusPromiseAtom, Promise.resolve(errorState));
      return;
    }

    const oldAuthStatus = get(authStatusUnstableDetailsAtom);

    // Bypassing PostgREST client for refresh, as it sends an expired Authorization
    // header that gets rejected before our RPC can run. Refresh is auth'd by httpOnly cookie.
    const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
    const refreshUrl = `${apiUrl}/rest/rpc/refresh`;

    const refreshPromise = (async () => {
      try {
        const response = await fetch(refreshUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          },
          // No body is needed for refresh RPC
          credentials: 'include' // Crucial for sending the refresh_token cookie
        });

        const responseData = await response.json();

        if (!response.ok) {
          console.error('clientSideRefreshAtom: Refresh API call failed.', responseData);
          // Even on failure, the response body from the RPC is what we should use
          // as it might contain specific error codes.
        }

        return _parseAuthStatusRpcResponseToAuthStatus(responseData);
      } catch (e) {
        console.error("clientSideRefreshAtom: Exception during refresh fetch:", e);
        return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'REFRESH_FETCH_ERROR' };
      }
    })();

    set(authStatusPromiseAtom, refreshPromise);
    const newAuthStatus = await refreshPromise; // Stabilize

    if (!oldAuthStatus.loading && oldAuthStatus.isAuthenticated !== newAuthStatus.isAuthenticated) {
      set(updateSyncTimestampAtom, Date.now());
    }
  }
);

export const logoutAtom = atom(
  null,
  async (get, set) => {
    const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
    const logoutUrl = `${apiUrl}/rest/rpc/logout`;

    try {
      const response = await fetch(logoutUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        credentials: 'include'
      });
      const responseData = await response.json();
      
      if (!response.ok) {
        throw new Error(responseData.message || 'Server returned an error during logout.');
      }

      // The logout RPC returns the new (unauthenticated) auth status.
      // Update state directly.
      const oldAuthStatus = get(authStatusUnstableDetailsAtom);
      const newAuthStatus = _parseAuthStatusRpcResponseToAuthStatus(responseData);
      set(authStatusPromiseAtom, Promise.resolve(newAuthStatus));
      await get(authStatusPromiseAtom); // Stabilize

      // Trigger cross-tab sync if we were previously authenticated.
      if (oldAuthStatus.isAuthenticated) {
        set(updateSyncTimestampAtom, Date.now());
      }

      // Reset all relevant application state that doesn't reset automatically
      // by reacting to the new unauthenticated state.
      set(refreshWorkerStatusAtom); // Resets worker status to non-authenticated state
      set(searchStateAtom, initialSearchStateValues);
      set(searchResultAtom, { data: [], total: 0, loading: false, error: null });
      set(selectedUnitsAtom, []);
      set(tableColumnsAtom, []);
      set(gettingStartedUIStateAtom, { currentStep: 0, completedSteps: [], isVisible: true });
      set(importStateAtom, initialImportState);
      set(unitCountsAtom, { legalUnits: null, establishmentsWithLegalUnit: null, establishmentsWithoutLegalUnit: null });
  
      // Also clear any lingering navigation state from session storage.
      set(lastKnownPathBeforeAuthChangeAtom, null);
  
      // Redirect to login.
      set(pendingRedirectAtom, '/login');

    } catch (error) {
      console.error('Error during logout. State will not be cleared. User may need to refresh.', error);
      // Re-throw the error so the UI layer (e.g., LogoutForm) can catch it and display a message.
      throw error;
    }
  }
)

// ============================================================================
// AUTH HOOKS - Replace useAuth and AuthContext patterns
// ============================================================================

export const useAuth = () => {
  const authStatusValue = useAtomValue(authStatusAtom); // The new, composed atom with stable isAuthenticated
  const login = useSetAtom(loginAtom);
  const logout = useSetAtom(logoutAtom);
  const refreshToken = useSetAtom(clientSideRefreshAtom);

  return {
    ...authStatusValue,
    login,
    logout,
    refreshToken,
  };
}

export const useUser = (): User | null => {
  return useAtomValue(currentUserAtom)
}

export const useIsAuthenticated = (): boolean => {
  return useAtomValue(isAuthenticatedAtom)
}
