"use client";

/**
 * Auth Atoms and Hooks
 *
 * This file contains atoms and hooks related to user authentication,
 * session management, and identity.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable, createJSONStorage, selectAtom } from 'jotai/utils'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { createMachine, assign, setup, fromPromise, type SnapshotFrom } from 'xstate'
import { atomWithMachine } from 'jotai-xstate'
import { atomEffect } from 'jotai-effect'
import type { Loadable } from 'jotai/vanilla/utils/loadable'

import { type User, type AuthStatus as CoreAuthStatus, _parseAuthStatusRpcResponseToAuthStatus } from '@/lib/auth.types';
import type { Database, Tables, TablesInsert } from '@/lib/database.types'
import { addEventJournalEntryAtom, stateInspectorVisibleAtom } from './app';
import {
  importStateAtom,
  initialImportState,
  unitCountsAtom,
} from './import'
import { refreshBaseDataAtom } from './base-data'
import { gettingStartedUIStateAtom } from './getting-started'
import {
  searchStateAtom,
  initialSearchStateValues,
  searchResultAtom,
  selectedUnitsAtom,
  tableColumnsAtom,
} from './search'
import { refreshWorkerStatusAtom } from './worker_status'
import { restClientAtom } from './rest-client'

// ============================================================================
// AUTH STATE MACHINE
// ============================================================================

export { _parseAuthStatusRpcResponseToAuthStatus };
export type { User };

export interface ClientAuthStatus extends CoreAuthStatus {
  loading: boolean;
}

const authMachine = setup({
  types: {
    context: {} as CoreAuthStatus & { client: any | null; justLoggedOut?: boolean },
    events: {} as
      | { type: 'CLIENT_READY'; client: any }
      | { type: 'CLIENT_UNREADY' }
      | { type: 'CHECK' }
      | { type: 'REFRESH' }
      | { type: 'LOGIN'; credentials: { email: string; password: string } }
      | { type: 'LOGOUT' }
      | { type: 'ACK_LOGOUT_CLEANUP' },
  },
  actors: {
    checkAuthStatus: fromPromise(async ({ input }: { input: { client: any }}) => {
      const { data, error } = await input.client.rpc("auth_status");
      if (error) throw error;
      const status = _parseAuthStatusRpcResponseToAuthStatus(data);
      const outcome = status.expired_access_token_call_refresh ? 'refresh_needed' : 'ok';
      return { outcome, status };
    }),
    refreshToken: fromPromise(async ({ input }: { input: { client: any }}) => {
      // Re-implement the core logic of _performClientSideRefresh here for the actor.
      const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
      const refreshUrl = `${apiUrl}/rest/rpc/refresh`;
      const response = await fetch(refreshUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        credentials: 'include'
      });
      const responseData = await response.json();
      if (!response.ok) {
        console.error('refreshToken actor: Refresh API call failed.', responseData);
        // We must throw here to trigger the onError handler of the invoke.
        throw new Error('Refresh API call failed');
      }

      // NEMESIS BUG FIX: After a successful refresh, the browser needs a moment
      // to process the Set-Cookie header. A subsequent navigation fetch might
      // use the old, stale cookie, causing a redirect loop with the server.
      // To solve this, we make a trivial "canary" request to `auth_status`.
      // This lightweight RPC will succeed even if unauthenticated, but it forces
      // the browser to use its latest cookie state for the request, acting as
      // our synchronization point. By awaiting it, we pause the state machine
      // until it's safe to navigate.
      try {
        const { error: canaryError } = await input.client.rpc('auth_status');
        if (canaryError) {
          console.error('refreshToken actor: Canary request to auth_status failed after refresh.', canaryError);
          // If the canary fails, something is fundamentally wrong with the API. Treat as a failed refresh.
          throw new Error('Canary request failed after refresh.');
        }
      } catch (e) {
        console.error('refreshToken actor: Exception during canary request.', e);
        throw new Error('Exception during canary request.');
      }

      return _parseAuthStatusRpcResponseToAuthStatus(responseData);
    }),
    login: fromPromise(async ({ input }: { input: { client: any, credentials: { email: string; password: string } } }) => {
      const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
      const loginUrl = `${apiUrl}/rest/rpc/login`;
      const response = await fetch(loginUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({ email: input.credentials.email, password: input.credentials.password }),
        credentials: 'include',
      });
      const responseData = await response.json();
      if (!response.ok || (responseData && responseData.is_authenticated === false)) {
        throw responseData; // Throw the error response data to be caught by onError
      }
      return _parseAuthStatusRpcResponseToAuthStatus(responseData);
    }),
    logout: fromPromise(async ({ input }: { input: { client: any }}) => {
      const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
      const logoutUrl = `${apiUrl}/rest/rpc/logout`;
      const response = await fetch(logoutUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        credentials: 'include'
      });
      const responseData = await response.json();
      if (!response.ok) throw new Error(responseData.message || 'Server returned an error during logout.');
      return _parseAuthStatusRpcResponseToAuthStatus(responseData);
    })
  }
}).createMachine({
  id: 'auth',
  initial: 'uninitialized',
  context: {
    client: null,
    isAuthenticated: false,
    user: null,
    expired_access_token_call_refresh: false,
    error_code: null,
    justLoggedOut: false,
  },
  states: {
    re_initializing: {
      on: {
        CLIENT_READY: {
          target: 'checking',
          actions: assign({ client: ({ event }) => event.client })
        },
      }
    },
    uninitialized: {
      on: {
        CLIENT_READY: {
          target: 'checking',
          actions: assign({ client: ({ event }) => event.client })
        },
        CLIENT_UNREADY: {
          // Explicitly handle this event to stay in the uninitialized state.
          // This makes the machine's behavior more declarative.
        }
      }
    },
    checking: {
      invoke: {
        id: 'checkAuthStatus',
        src: 'checkAuthStatus',
        input: ({ context }) => ({ client: context.client }),
        onDone: {
          actions: assign(({ event, context }) => ({ ...event.output.status, client: context.client })),
          target: 'evaluating_initial_session'
        },
        onError: {
          target: 'idle_unauthenticated',
          actions: assign({ error_code: 'RPC_ERROR' })
        }
      }
    },
    evaluating_initial_session: {
      always: [
        { target: 'initial_refreshing', guard: ({ context }) => context.expired_access_token_call_refresh },
        { target: 'idle_authenticated', guard: ({ context }) => context.isAuthenticated },
        { target: 'idle_unauthenticated' }
      ]
    },
    initial_refreshing: {
      invoke: {
        id: 'refreshToken',
        src: 'refreshToken',
        input: ({ context }) => ({ client: context.client }),
        onDone: {
          actions: assign(({ event, context }) => ({ ...event.output, client: context.client })),
          // After a successful initial refresh, we are authenticated.
          target: 'idle_authenticated'
        },
        onError: {
          target: 'idle_unauthenticated',
          actions: assign({ isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'REFRESH_FETCH_ERROR' })
        }
      }
    },
    idle_authenticated: {
      id: 'idle_authenticated',
      on: {
        CHECK: '.revalidating',
        REFRESH: '.background_refreshing',
        LOGOUT: 'loggingOut',
        // If the client becomes unready, move to a safe "re-initializing" state
        // that is still considered authenticated by the UI, preventing a state flap.
        CLIENT_UNREADY: 're_initializing',
      },
      initial: 'stable',
      states: {
        stable: {},
        revalidating: {
          invoke: {
            id: 'checkAuthStatus',
            src: 'checkAuthStatus',
            input: ({ context }) => ({ client: context.client }),
            onDone: [
              {
                // If a refresh is needed, go to the background refresh state.
                // CRUCIALLY: Do NOT update the context here. The current context is still
                // valid from a UI perspective. We let the refresh actor provide the new context.
                // This completely prevents the "context flap".
                target: 'background_refreshing',
                guard: ({ event }) => event.output.outcome === 'refresh_needed',
              },
              {
                target: 'stable',
                guard: ({ event }) => event.output.outcome === 'ok' && event.output.status.isAuthenticated,
                actions: assign(({ event, context }) => ({ ...event.output.status, client: context.client })),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => event.output.outcome === 'ok' && !event.output.status.isAuthenticated,
                actions: assign(({ event, context }) => ({ ...event.output.status, client: context.client })),
              }
            ],
            onError: {
              target: '#auth.idle_unauthenticated',
              actions: assign({ error_code: 'RPC_ERROR' })
            }
          }
        },
        background_refreshing: {
          invoke: {
            id: 'refreshTokenInBackground',
            src: 'refreshToken',
            input: ({ context }) => ({ client: context.client }),
            onDone: [
              {
                target: 'stable',
                guard: ({ event }) => event.output.isAuthenticated,
                actions: assign(({ event, context }) => ({ ...event.output, client: context.client })),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => !event.output.isAuthenticated,
                actions: assign(({ event, context }) => ({ ...event.output, client: context.client })),
              },
            ],
            onError: {
              target: '#auth.idle_unauthenticated',
              actions: assign({ isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'REFRESH_FETCH_ERROR' })
            }
          }
        }
      }
    },
    idle_unauthenticated: {
      on: {
        CHECK: 'checking',
        LOGIN: {
          target: 'loggingIn',
          // Clear any previous login error when a new attempt starts.
          actions: assign({ error_code: null }),
        },
        CLIENT_UNREADY: 'uninitialized',
        ACK_LOGOUT_CLEANUP: {
          actions: assign({ justLoggedOut: false }), // Clear the flag.
        }
      }
    },
    loggingIn: {
      invoke: {
        id: 'login',
        src: 'login',
        input: ({ context, event }) => {
          if (event.type !== 'LOGIN') throw new Error('Invalid event');
          return { client: context.client, credentials: event.credentials }
        },
        onDone: {
          target: 'idle_authenticated',
          actions: [
            assign(({ event, context }) => ({ ...event.output, client: context.client })),
            // When login succeeds, clear any previous login error.
            assign({ error_code: null })
          ]
        },
        onError: {
          target: 'idle_unauthenticated',
          actions: assign({
            // Prepend "LOGIN_" to distinguish this from other errors.
            error_code: ({ event }) => `LOGIN_${(event.error as any)?.error_code || 'UNKNOWN_FAILURE'}`
          })
        }
      }
    },
    loggingOut: {
      invoke: {
        id: 'logout',
        src: 'logout',
        input: ({ context }) => ({ client: context.client }),
        onDone: {
          target: 'idle_unauthenticated',
          actions: assign(({ event, context }) => ({
            ...event.output,
            client: context.client,
            justLoggedOut: true, // Set flag for the effect atom to consume.
          })),
        },
        onError: {
          // If logout fails, we are still authenticated.
          target: 'idle_authenticated',
          actions: assign({ error_code: 'LOGOUT_ERROR' })
        }
      }
    }
  }
});

export const authMachineAtom = atomWithMachine(authMachine);

const prevAuthMachineSnapshotAtom = atom<SnapshotFrom<typeof authMachine> | null>(null);

/**
 * Scribe Effect for the Authentication State Machine.
 *
 * When the StateInspector is visible, this effect will log every state
 * transition to the state saga and the browser console, providing a detailed
 * trace of the authentication flow for debugging purposes. It remains dormant
 * otherwise to avoid any performance overhead.
 */
export const authMachineScribeEffectAtom = atomEffect((get, set) => {
  const isInspectorVisible = get(stateInspectorVisibleAtom);
  if (!isInspectorVisible) {
    if (get(prevAuthMachineSnapshotAtom) !== null) {
      set(prevAuthMachineSnapshotAtom, null); // Reset when not visible to avoid stale "from" state on re-open.
    }
    return;
  }

  const machine = get(authMachineAtom);
  const prevMachine = get(prevAuthMachineSnapshotAtom);
  set(prevAuthMachineSnapshotAtom, machine); // Update for next run

  if (prevMachine && machine.value !== prevMachine.value) {
    const event = (machine as any).event ?? { type: 'unknown' };
    const entry = {
      machine: 'auth' as const,
      from: prevMachine.value,
      to: machine.value,
      event: event,
      reason: `Transitioned from ${JSON.stringify(prevMachine.value)} to ${JSON.stringify(machine.value)} on event ${event.type}`
    };
    set(addEventJournalEntryAtom, entry);
    console.log(`[Scribe:Auth]`, entry.reason, { from: entry.from, to: entry.to, event: entry.event });
  }
});

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
    
    if (get(stateInspectorVisibleAtom)) {
      // Add detailed logging to trace the nemesis bug
      console.log(
        `[authStatusUnstableDetailsAtom] re-evaluating. Machine state: ${JSON.stringify(machine.value)}, context.isAuthenticated: ${coreStatus.isAuthenticated}, derived isLoading: ${isLoading}`
      );
    }

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
  // User is considered authenticated for UI purposes if they are in a stable authenticated state,
  // or if the machine is in a transient state that will likely lead back to an
  // authenticated state. This prevents data cascades (the "nemesis" bug).
  const result = state.matches('idle_authenticated') || state.matches('checking') || state.matches('evaluating_initial_session') || state.matches('initial_refreshing') || state.matches('re_initializing');
  
  if (get(stateInspectorVisibleAtom)) {
    // Add detailed logging to trace the nemesis bug
    console.log(
      `[isUserConsideredAuthenticatedForUIAtom] re-evaluating. Machine state: ${JSON.stringify(state.value)}, result: ${result}`
    );
  }

  return result;
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

    if (get(stateInspectorVisibleAtom)) {
      // Add detailed logging to trace the nemesis bug
      console.log(
        `[authStateForDataFetchingAtom] re-evaluating. Machine state: ${JSON.stringify(state.value)}, result: ${result}`
      );
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
    console.error(`[loginErrorAtom] ${message}`, { code, context: machine.context });
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

    // Reset all relevant application state.
    set(refreshWorkerStatusAtom);
    set(searchStateAtom, initialSearchStateValues);
    set(searchResultAtom, { data: [], total: 0, loading: false, error: null });
    set(selectedUnitsAtom, []);
    set(tableColumnsAtom, []);
    set(gettingStartedUIStateAtom, { currentStep: 0, completedSteps: [], isVisible: true });
    set(importStateAtom, initialImportState);
    set(unitCountsAtom, { legalUnits: null, establishmentsWithLegalUnit: null, establishmentsWithoutLegalUnit: null });
    set(lastKnownPathBeforeAuthChangeAtom, null);

    // Acknowledge that cleanup is done so we don't run it again.
    set(authMachineAtom, { type: 'ACK_LOGOUT_CLEANUP' });
  }
});


export const logoutAtom = atom(
  null,
  (get, set) => {
    set(authMachineAtom, { type: 'LOGOUT' });
  }
);

// ============================================================================
// LOGIN PAGE UI STATE MACHINE
// ============================================================================

export const loginPageMachine = setup({
  types: {
    context: {} as {
      isAuthenticated: boolean;
      isLoggingIn: boolean;
      isOnLoginPage: boolean;
    },
    events: {} as
      | { type: 'EVALUATE'; context: { isAuthenticated: boolean; isLoggingIn: boolean; isOnLoginPage: boolean; } },
  },
}).createMachine({
  id: 'loginPage',
  initial: 'idle',
  context: {
    isAuthenticated: false,
    isLoggingIn: false,
    isOnLoginPage: false,
  },
  states: {
    idle: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    },
    evaluating: {
      always: [
        { target: 'finalizing', guard: ({ context }) => context.isOnLoginPage && (context.isAuthenticated || context.isLoggingIn) },
        { target: 'showingForm', guard: ({ context }) => context.isOnLoginPage && !context.isAuthenticated },
        { target: 'idle' } // If not on login page, do nothing.
      ]
    },
    showingForm: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    },
    finalizing: {
      on: {
        EVALUATE: {
          target: 'evaluating',
          actions: assign(({ event }) => event.context)
        }
      }
    }
  }
});

export const loginPageMachineAtom = atomWithMachine(loginPageMachine);

const prevLoginPageMachineSnapshotAtom = atom<SnapshotFrom<typeof loginPageMachine> | null>(null);

/**
 * Scribe Effect for the Login Page UI State Machine.
 *
 * When the StateInspector is visible, this effect will log every state
 * transition to the state saga and the browser console.
 */
export const loginPageMachineScribeEffectAtom = atomEffect((get, set) => {
  const isInspectorVisible = get(stateInspectorVisibleAtom);
  if (!isInspectorVisible) {
    if (get(prevLoginPageMachineSnapshotAtom) !== null) {
      set(prevLoginPageMachineSnapshotAtom, null); // Reset when not visible.
    }
    return;
  }

  const machine = get(loginPageMachineAtom);
  const prevMachine = get(prevLoginPageMachineSnapshotAtom);
  set(prevLoginPageMachineSnapshotAtom, machine); // Update for next run

  if (prevMachine && machine.value !== prevMachine.value) {
    const event = (machine as any).event ?? { type: 'unknown' };
    const entry = {
      machine: 'login' as const,
      from: prevMachine.value,
      to: machine.value,
      event: event,
      reason: `Transitioned from ${JSON.stringify(prevMachine.value)} to ${JSON.stringify(machine.value)} on event ${event.type}`
    };
    set(addEventJournalEntryAtom, entry);
    console.log(`[Scribe:Login]`, entry.reason, { from: entry.from, to: entry.to, event: entry.event });
  }
});

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
  return useAtomValue(isUserConsideredAuthenticatedForUIAtom)
}
