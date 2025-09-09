"use client";

/**
 * Authentication State Machine (authMachine)
 *
 * This file defines the core state machine for managing user authentication.
 * It is the single source of truth for the user's authentication status,
 * including whether they are authenticated, unauthenticated, or in a transient
 * state like checking credentials, refreshing a token, or logging in/out.
 *
 * Responsibilities:
 * - Interacting with the authentication API (auth_status, login, logout, refresh).
 * - Maintaining the user's session state and user object.
 * - Handling the complete lifecycle of authentication from initialization to logout.
 *
 * Interactions:
 * - It is consumed by the `navigationMachine` to make application-wide routing decisions.
 * - It is consumed by page-level UI components and state machines (like `loginMachine`)
 *   to determine what content to display.
 * - It does NOT perform navigation itself. All redirect logic is centralized in `navigationMachine`.
 */

import { atom } from 'jotai'
import { atomEffect } from 'jotai-effect'
import { createMachine, assign, setup, fromPromise, type SnapshotFrom } from 'xstate'
import { atomWithMachine } from 'jotai-xstate'

import { type User, type AuthStatus as CoreAuthStatus, _parseAuthStatusRpcResponseToAuthStatus } from '@/lib/auth.types';
import { addEventJournalEntryAtom, stateInspectorVisibleAtom } from './app';

const authMachine = setup({
  types: {
    context: {} as CoreAuthStatus & { client: any | null; justLoggedOut?: boolean; lastCanaryResponse?: any; lastAuthStatusResponse?: any; lastRefreshResponse?: any },
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
      const rawResponseWithTimestamp = { ...data, timestamp: new Date().toISOString() };
      return { outcome, status, rawResponse: rawResponseWithTimestamp };
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

      let canaryData = null;
      // NEMESIS BUG FIX: After a successful refresh, the browser needs a moment
      // to process the Set-Cookie header. A subsequent navigation fetch might
      // use the old, stale cookie, causing a redirect loop with the server.
      // To solve this, we make a trivial "canary" request to `auth_status`.
      // This lightweight RPC will succeed even if unauthenticated, but it forces
      // the browser to use its latest cookie state for the request, acting as
      // our synchronization point. By awaiting it, we pause the state machine
      // until it's safe to navigate.
      try {
        const { data, error: canaryError } = await input.client.rpc('auth_test');
        if (canaryError) {
          console.error('refreshToken actor: Canary request to auth_test failed after refresh.', canaryError);
          // If the canary fails, something is fundamentally wrong with the API. Treat as a failed refresh.
          throw new Error('Canary request failed after refresh.');
        }
        canaryData = data;
      } catch (e) {
        console.error('refreshToken actor: Exception during canary request.', e);
        throw new Error('Exception during canary request.');
      }

      const parsedStatus = _parseAuthStatusRpcResponseToAuthStatus(responseData);
      const rawResponseWithTimestamp = { ...responseData, timestamp: new Date().toISOString() };
      return { parsedStatus, canaryData, rawResponse: rawResponseWithTimestamp };
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
    lastCanaryResponse: null,
    lastAuthStatusResponse: null,
    lastRefreshResponse: null,
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
          actions: assign(({ event, context }) => ({
            ...event.output.status,
            client: context.client,
            lastAuthStatusResponse: event.output.rawResponse,
          })),
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
          actions: assign(({ event, context }) => ({
            ...event.output.parsedStatus,
            client: context.client,
            lastCanaryResponse: event.output.canaryData,
            lastRefreshResponse: event.output.rawResponse,
          })),
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
                actions: assign(({ event, context }) => ({
                  ...event.output.status,
                  client: context.client,
                  lastAuthStatusResponse: event.output.rawResponse,
                })),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => event.output.outcome === 'ok' && !event.output.status.isAuthenticated,
                actions: assign(({ event, context }) => ({
                  ...event.output.status,
                  client: context.client,
                  lastAuthStatusResponse: event.output.rawResponse,
                })),
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
                guard: ({ event }) => event.output.parsedStatus.isAuthenticated,
                actions: assign(({ event, context }) => ({
                  ...event.output.parsedStatus,
                  client: context.client,
                  lastCanaryResponse: event.output.canaryData,
                  lastRefreshResponse: event.output.rawResponse,
                })),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => !event.output.parsedStatus.isAuthenticated,
                actions: assign(({ event, context }) => ({
                  ...event.output.parsedStatus,
                  client: context.client,
                  lastCanaryResponse: event.output.canaryData,
                  lastRefreshResponse: event.output.rawResponse,
                })),
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
 * transition to the Event Journal and the browser console, providing a detailed
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

  const currentSnapshot = get(authMachineAtom);
  const prevSnapshot = get(prevAuthMachineSnapshotAtom);
  set(prevAuthMachineSnapshotAtom, currentSnapshot); // Update for next run

  if (!prevSnapshot) {
    return; // Don't log on the first run.
  }

  // A more robust check to see if a meaningful change has occurred.
  // This prevents infinite loops caused by new object references for unchanged state.
  const valueChanged = JSON.stringify(currentSnapshot.value) !== JSON.stringify(prevSnapshot.value);
  const contextChanged = JSON.stringify(currentSnapshot.context) !== JSON.stringify(prevSnapshot.context);

  if (valueChanged || contextChanged) {
    const event = (currentSnapshot as any).event ?? { type: 'unknown' };
    const reasonSuffix = event.type === 'unknown'
      ? 'due to an automatic transition.'
      : `on event ${event.type}`;
    const reason = `Transitioned from ${JSON.stringify(prevSnapshot.value)} to ${JSON.stringify(currentSnapshot.value)} ${reasonSuffix}`;
    const entry = {
      machine: 'auth' as const,
      from: prevSnapshot.value,
      to: currentSnapshot.value,
      event: event,
      reason: reason,
    };
    set(addEventJournalEntryAtom, entry);
    console.log(`[Scribe:Auth]`, entry.reason, { from: entry.from, to: entry.to, event: entry.event });

    // After logging the main transition, check if a canary request just completed.
    // This is safer than a separate effect atom.
    const currentCanary = currentSnapshot.context.lastCanaryResponse;
    const prevCanary = prevSnapshot?.context.lastCanaryResponse;
    if (currentCanary && JSON.stringify(currentCanary) !== JSON.stringify(prevCanary)) {
      const canaryEntry = {
        machine: 'system' as const,
        from: 'canary_request',
        to: 'canary_response',
        event: { type: 'AUTH_TEST' },
        reason: `Canary check completed successfully, confirming browser cookie synchronization.`
      };
      set(addEventJournalEntryAtom, canaryEntry);
    }
  }
});
