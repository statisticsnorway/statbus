"use client";

/**
 * Auth Atoms and Hooks
 *
 * This file contains atoms and hooks related to user authentication,
 * session management, and identity.
 */

import { atom } from 'jotai'
import { atomWithStorage, createJSONStorage, selectAtom } from 'jotai/utils'
import { useAtomValue, useSetAtom } from 'jotai'
import { atomEffect } from 'jotai-effect'

import { type User, type AuthStatus as CoreAuthStatus, _parseAuthStatusRpcResponseToAuthStatus } from '@/lib/auth.types';
import { logger } from '@/lib/client-logger';
import { authMachineAtom } from './auth-machine';
import { loginUiMachineAtom } from './login-ui-machine';
import {
  importStateAtom,
  initialImportState,
  unitCountsAtom,
} from './import'
import { refreshBaseDataAtom, invalidateHasStatisticalUnitsCache } from './base-data'
import { gettingStartedUIStateAtom } from './getting-started'
import {
  searchResultAtom,
  searchPageDataReadyAtom,
  selectedUnitsAtom,
  tableColumnsAtom,
  resetSearchStateAtom,
} from './search'
import { refreshWorkerStatusAtom } from './worker_status'
import { invalidateExactCountsCache, exactCountCacheGenerationAtom } from '@/components/estimated-count'
import { restClientAtom } from './rest-client'

// ============================================================================
// EXPORTS FROM MACHINE FILES
// ============================================================================
export { authMachineAtom };
export { loginUiMachineAtom };
export { _parseAuthStatusRpcResponseToAuthStatus };
export type { User };

// ============================================================================
// DERIVED AUTH ATOMS
// ============================================================================

export interface ClientAuthStatus extends CoreAuthStatus {
  loading: boolean;
}

const isExternalAuthActionRunningAtom = atom(false);

// Derived atoms for easier access
/**
 * An internal, unstable atom that directly reflects the current state of the
 * auth machine, including transient loading states.
 *
 * BATTLE WISDOM:
 * This atom is considered "unstable" because its value can change frequently
 * during authentication operations (e.g., loading: true -> false).
 * Most UI components should NOT use this atom directly. Instead, use one of
 * the derived, stable atoms below to prevent unnecessary re-renders and
 * state "flaps".
 */
export const authStatusUnstableDetailsAtom = atom<ClientAuthStatus>(
  (get): ClientAuthStatus => {
    const machine = get(authMachineAtom);
    const { client, ...coreStatus } = machine.context;
    // isLoading is true if the machine is in any state other than the two stable "idle" states.
    // This correctly captures transient states like 'revalidating' or 'manual_refreshing'
    // which are substates of 'idle_authenticated'.
    const isLoading = !machine.matches({ idle_authenticated: 'stable' }) && !machine.matches('idle_unauthenticated');
    
    return {
      ...coreStatus,
      loading: isLoading,
    };
  }
);

/**
 * A derived atom that provides a single boolean flag indicating if any
 * authentication-related action (machine transition, external RPC) is in progress.
 * This is the source of truth for disabling UI controls in the StateInspector.
 */
export const isAuthActionInProgressAtom = atom((get) => {
  const isMachineBusy = get(authStatusUnstableDetailsAtom).loading;
  const isExternalActionBusy = get(isExternalAuthActionRunningAtom);
  return isMachineBusy || isExternalActionBusy;
});

// Custom equality check for ClientAuthStatus
function areClientAuthStatusesEqual(a: ClientAuthStatus, b: ClientAuthStatus): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.loading !== b.loading) return false;
  if (a.isAuthenticated !== b.isAuthenticated) return false;
  if (a.expired_access_token_call_refresh !== b.expired_access_token_call_refresh) return false;
  if (a.error_code !== b.error_code) return false;
  if (a.user?.uid !== b.user?.uid) return false;
  if (a.user?.last_sign_in_at !== b.user?.last_sign_in_at) return false;
  if (a.token_expires_at !== b.token_expires_at) return false;
  return true;
}

/**
 * A memoized, stable version of the auth status details atom.
 * This atom should be used by UI components (like the StateInspector) to prevent
 * re-renders when the underlying data has not meaningfully changed. It returns
 * the same object reference if the status is semantically equal.
 */
export const authStatusDetailsAtom = selectAtom(authStatusUnstableDetailsAtom, (s) => s, areClientAuthStatusesEqual);

/**
 * A "stabilized" boolean indicating if the user should be considered authenticated
 * for UI rendering and navigation purposes.
 *
 * BATTLE WISDOM:
 * This atom is the shield that prevents UI flicker during background token refreshes.
 * It will remain `true` during transient states like `checking`, `revalidating`,
 * and `background_refreshing`. This ensures that protected layouts and components
 * do not unmount and remount, which was the cause of the original "nemesis bug".
 * Use this atom for any logic that controls what the user *sees* or for routing guards.
 */
export const isUserConsideredAuthenticatedForUIAtom = atom(get => {
  const state = get(authMachineAtom);
  // User is considered authenticated for UI purposes if the current state is tagged
  // with 'ui-authenticated'. This is a declarative way to define UI stability and
  // prevents UI flicker during transient auth states. This logic is now defined
  // directly within the state machine.
  return state.hasTag('ui-authenticated');
});

/**
 * An internal, derived atom that provides a simplified view of the auth state
 * specifically for data-fetching atoms. It returns a specific string enum that
 * allows atoms using it to `suspend` during critical auth states.
 *
 * BATTLE WISDOM:
 * This atom is the gatekeeper for our supply lines (API calls). By returning
 * `'checking'` or `'refreshing'`, it signals to data-fetching atoms like
 * `baseDataPromiseAtom` that they must pause (suspend) and wait for a definitive
 * authentication result. This prevents API calls from being made with stale or
 * invalid tokens. It is the strict counterpart to `isUserConsideredAuthenticatedForUIAtom`.
 */
export const authStateForDataFetchingAtom = atom(
  (get): 'unauthenticated' | 'authenticated' | 'refreshing' | 'checking' => {
    const state = get(authMachineAtom);
    let result: 'unauthenticated' | 'authenticated' | 'refreshing' | 'checking';
    // If we are refreshing as part of the initial load, report 'refreshing'.
    // This correctly suspends data atoms until a valid token is available.
    if (state.matches('initial_refreshing')) {
      result = 'refreshing';
    }
    // While checking, we are not yet authenticated for data fetching.
    else if (state.matches('checking')) {
      result = 'checking';
    }
    // For all other authenticated states, including re-evaluation and re-initialization,
    // report 'authenticated'. This keeps data atoms stable.
    else if (state.matches('idle_authenticated') || state.matches('evaluating_initial_session') || state.matches('re_initializing')) {
      result = 'authenticated';
    } else {
      result = 'unauthenticated';
    }

    return result;
  }
);

/**
 * A derived atom that provides a STRICT authentication status. It is `true` only
 * when the application has a valid session, even if that session is in the
 * process of an initial refresh.
 *
 * BATTLE WISDOM:
 * This atom is stricter than `isUserConsideredAuthenticatedForUIAtom`. It will be
 * `false` during the initial `checking` phase. This makes it suitable for gating
 * logic in `useEffect` hooks or for initializing systems that should only run
 * once a session is confirmed to exist, but that don't need to suspend.
 * For atoms that fetch data and can suspend, use `authStateForDataFetchingAtom` directly.
 */
export const isAuthenticatedStrictAtom = atom(get => {
  const state = get(authStateForDataFetchingAtom);
  return state === 'authenticated' || state === 'refreshing';
});

/**
 * A derived atom that is true only when the auth machine is in a final,
 * settled state (either authenticated or unauthenticated). This provides a clear
 * signal for other systems, like the navigation machine, to know when it is
 * safe to make decisions based on the authentication status.
 */
export const isAuthStableAtom = atom(get => get(authMachineAtom).hasTag('auth-stable'));

/**
 * The primary, recommended atom for auth state.
 * It combines the detailed status (user, loading state, etc.) with the
 * STABILIZED `isAuthenticated` boolean, providing the best of both worlds.
 * This should be the default choice for most UI components.
 * It combines the detailed user data with the stabilized UI authentication boolean.
 */
export const authStatusAtom = atom((get) => {
  const unstableStatus = get(authStatusUnstableDetailsAtom);
  const isAuthenticatedForUI = get(isUserConsideredAuthenticatedForUIAtom); // The stabilized UI version
  return {
    ...unstableStatus,
    isAuthenticated: isAuthenticatedForUI, // Overwrite the raw value with the stable one for UI consumers
  };
});
export const currentUserAtom = atom((get) => get(authStatusUnstableDetailsAtom).user);

/**
 * A derived atom exposing the token expiration time from the auth machine context.
 * Used by SSEConnectionManager to schedule proactive token refresh.
 */
export const tokenExpiresAtAtom = atom((get) => {
  const machine = get(authMachineAtom);
  return machine.context.token_expires_at as string | null;
});

/**
 * A derived boolean atom that is `true` if the server has indicated that the
 * access token is expired and a refresh is required.
 */
export const authNeedsRefreshAtom = atom((get) => get(authStatusUnstableDetailsAtom).expired_access_token_call_refresh);

// ============================================================================
// AUTH-RELATED APP STATE ATOMS
// ============================================================================

// Atom to hold the error state from the last login attempt.
// This atom is now highly specific to only report errors from a failed login transition.
export const loginErrorAtom = atom(get => {
  const machine = get(authMachineAtom);
  const errorCode = machine.context.error_code;

  // A "login error" is now identified by a specific prefix.
  if (machine.matches('idle_unauthenticated') && errorCode?.startsWith('LOGIN_')) {
    const code = errorCode.replace('LOGIN_', '');
    const message = `Login failed: ${code}`;
    // Log the error to the console for better debugging.
    logger.error('loginErrorAtom', message, { code, context: machine.context });
    return { code, message };
  }
  return null;
});


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

// Dev Tools State, moved from app.ts to break circular dependency
export const isTokenManuallyExpiredAtom = atom(false);

// Tracks whether app data initialization has run in this SPA session.
// Must be reset on logout so re-login triggers re-initialization.
export const appDataInitializedAtom = atom(false);


// ============================================================================
// ASYNC AUTH ACTION ATOMS
// ============================================================================

export const fetchAuthStatusAtom = atom(null, (get, set) => {
  set(authMachineAtom, { type: 'CHECK' });
});

export const loginAtom = atom(
  null,
  (get, set, { credentials }: { credentials: { email: string; password: string } }) => {
    // The machine's onError handler will populate the context with the error code.
    set(authMachineAtom, { type: 'LOGIN', credentials });
  }
);

/**
 * Action atom for developers to simulate an expired access token for testing purposes.
 * It calls an RPC that invalidates the current access token but leaves the refresh
 * token intact.
 *
 * BATTLE WISDOM:
 * This atom INTENTIONALLY does not update the client-side auth state after
 * execution. This allows developers to test how the application handles an
 * out-of-sync expired token on the next user action that requires authentication.
 * It is a key tool for testing the "nemesis bug" scenarios.
 */
export const expireAccessTokenAtom = atom<null, [], Promise<void>>(
  null,
  async (get, set) => {
    if (get(isExternalAuthActionRunningAtom)) {
      console.warn("expireAccessTokenAtom: Auth action already in progress. Aborting.");
      return;
    }
    set(isExternalAuthActionRunningAtom, true);

    try {
      const client = get(restClientAtom);
      if (!client) {
        console.error("expireAccessTokenAtom: Client not available.");
        throw new Error("Client not available.");
      }

      const { error } = await client.rpc('auth_expire_access_keep_refresh');
      if (error) {
        console.error("expireAccessTokenAtom: RPC failed.", error);
        throw new Error(error.message || 'RPC to expire access token failed');
      }
      // Set the flag to give the user immediate visual feedback in the inspector.
      set(isTokenManuallyExpiredAtom, true);
      // NOTE: We intentionally DO NOT refetch auth status here.
      // This allows testing the app's handling of a stale auth state.
    } catch (error) {
      console.error("expireAccessTokenAtom: Error during process:", error);
      // Re-throw so the UI can handle it if needed.
      throw error;
    } finally {
      set(isExternalAuthActionRunningAtom, false);
    }
  }
);

export const clientSideRefreshAtom = atom(null, (get, set) => {
  set(authMachineAtom, { type: 'REFRESH' });
});


// This effect handles the side-effects of logging out, like clearing app state.
export const logoutEffectAtom = atomEffect((get, set) => {
  const machine = get(authMachineAtom);

  // This condition is true only on the render immediately after a successful logout.
  if (machine.matches('idle_unauthenticated') && machine.context.justLoggedOut) {
    const oldAuthStatus = get(authStatusUnstableDetailsAtom);
    // Trigger cross-tab sync if we were previously authenticated.
    // We check oldAuthStatus because the machine context might already be unauthenticated.
    if (oldAuthStatus.isAuthenticated) {
      set(updateSyncTimestampAtom, Date.now());
    }

    // Reset all relevant application state. Any atom being reset here should be
    // self-contained and not produce side-effects that impact other atoms' storage.
    // The previous bug where the journal was cleared was caused by a faulty
    // side-effect in the definition of one of these reset atoms.
    set(appDataInitializedAtom, false);
    set(refreshWorkerStatusAtom);
    set(resetSearchStateAtom);
    set(selectedUnitsAtom, []);
    set(tableColumnsAtom, []);
    set(gettingStartedUIStateAtom, { currentStep: 0, completedSteps: [], isVisible: true });
    set(importStateAtom, initialImportState);
    set(unitCountsAtom, { legalUnits: null, establishmentsWithLegalUnit: null, establishmentsWithoutLegalUnit: null });
    set(lastKnownPathBeforeAuthChangeAtom, null);
    invalidateHasStatisticalUnitsCache();
    invalidateExactCountsCache();
    set(exactCountCacheGenerationAtom, (n) => n + 1);

    // Acknowledge that cleanup is done so we don't run it again.
    set(authMachineAtom, { type: 'ACK_LOGOUT_CLEANUP' });
  }
});


// Tracks whether the auth machine was recently in `background_refreshing` state.
// Used by `postRefreshCacheInvalidationEffectAtom` to detect the
// `background_refreshing → stable` transition.
const wasBackgroundRefreshingAtom = atom(false);

// Invalidates stale caches after a dormant session resumes.
// `background_refreshing` only fires when the token was expired (dormant session),
// meaning SSE events may have been missed. A valid token (CHECK → stable) means
// the session was live — no invalidation needed.
export const postRefreshCacheInvalidationEffectAtom = atomEffect((get, set) => {
  const machine = get(authMachineAtom);

  if (machine.matches({ idle_authenticated: 'background_refreshing' })) {
    if (!get(wasBackgroundRefreshingAtom)) set(wasBackgroundRefreshingAtom, true);
    return;
  }

  if (get(wasBackgroundRefreshingAtom) && machine.matches({ idle_authenticated: 'stable' })) {
    set(wasBackgroundRefreshingAtom, false);
    // Token was expired → session was dormant → invalidate stale caches
    invalidateHasStatisticalUnitsCache();
    invalidateExactCountsCache();
    set(exactCountCacheGenerationAtom, (n) => n + 1);
    set(searchPageDataReadyAtom, false);
    set(refreshWorkerStatusAtom);
  }
});

export const logoutAtom = atom(
  null,
  (get, set) => {
    set(authMachineAtom, { type: 'LOGOUT' });
  }
);


// ============================================================================
// AUTH HOOKS - Replace useAuth and AuthContext patterns
// ============================================================================

export const useAuth = () => {
  const authStatusValue = useAtomValue(authStatusAtom);
  const loginError = useAtomValue(loginErrorAtom);
  const login = useSetAtom(loginAtom);
  const logout = useSetAtom(logoutAtom);
  const refreshToken = useSetAtom(clientSideRefreshAtom);

  return {
    ...authStatusValue,
    login,
    logout,
    refreshToken,
    loginError,
  };
}

export const useUser = (): User | null => {
  return useAtomValue(currentUserAtom)
}

export const useIsAuthenticated = (): boolean => {
  // This hook is for UI consumption, so it uses the UI-stable atom.
  return useAtomValue(isUserConsideredAuthenticatedForUIAtom);
};

// ============================================================================
// PERMISSIONS
// ============================================================================

export type UserRole =
  | "admin_user"
  | "regular_user"
  | "restricted_user"
  | "external_user";

export const getUserPermissions = (role: UserRole | null | undefined) => {
  const permissions = {
    canEdit: false,
    canImport: false,
    canAccessGettingStarted: false,
    canAccessAdminTools: false,
  };
  switch (role) {
    case "admin_user":
      permissions.canEdit = true;
      permissions.canImport = true;
      permissions.canAccessGettingStarted = true;
      permissions.canAccessAdminTools = true;
      break;
    case "regular_user":
      permissions.canEdit = true;
      permissions.canImport = true;
      break;
    case "restricted_user":
      break;
    case "external_user":
      break;
  }
  return permissions;
};

export const userRoleAtom = atom(
  (get) => get(currentUserAtom)?.statbus_role as UserRole
);

export const permissionAtom = atom((get) => {
  const role = get(userRoleAtom);
  return getUserPermissions(role);
});

export const usePermission = () => {
  return useAtomValue(permissionAtom);
};                                         