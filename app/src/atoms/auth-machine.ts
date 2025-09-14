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
import { inspector } from './inspector';

const addAndPurgeLog = (log: Record<number, any> | undefined, type: string, response: any, timestamp: number): Record<number, any> => {
  if (!response) {
    return log || {};
  }
  const newLog = log ? { ...log } : {};
  const sixtySecondsAgo = timestamp - 60000;
  // Purge old entries
  for (const key in newLog) {
    if (parseInt(key, 10) < sixtySecondsAgo) {
      delete newLog[key];
    }
  }
  // Add new entry
  newLog[timestamp] = { type, response };
  return newLog;
};

const authMachine = setup({
  types: {
    context: {} as CoreAuthStatus & { client: any | null; justLoggedOut?: boolean; authApiResponseLog?: Record<number, { type: string; response: any; }>; },
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
      console.log("[auth-machine:checkAuthStatus] Actor invoked.");
      const { data, error } = await input.client.rpc("auth_status");
      if (error) {
        console.error("[auth-machine:checkAuthStatus] Error from auth_status RPC:", error);
        throw error;
      }
      console.log("[auth-machine:checkAuthStatus] Raw response from auth_status:", data);

      const status = _parseAuthStatusRpcResponseToAuthStatus(data);
      const outcome = status.expired_access_token_call_refresh ? 'refresh_needed' : 'ok';
      console.log(`[auth-machine:checkAuthStatus] Final outcome determined: '${outcome}'.`);

      const rawResponseWithTimestamp = { ...data, timestamp: new Date().toISOString() };
      return { outcome, status, rawResponse: rawResponseWithTimestamp };
    }),
    refreshToken: fromPromise(async ({ input }: { input: { client: any }}) => {
      console.log("[auth-machine:refreshToken] Actor invoked.");
      // Re-implement the core logic of _performClientSideRefresh here for the actor.
      const apiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL || '';
      const refreshUrl = `${apiUrl}/rest/rpc/refresh`;
      const response = await fetch(refreshUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        credentials: 'include'
      });
      const responseData = await response.json();
      console.log("[auth-machine:refreshToken] Raw response from refresh:", responseData);
      if (!response.ok) {
        console.error('refreshToken actor: Refresh API call failed.', responseData);
        // We must throw here to trigger the onError handler of the invoke.
        // BATTLE WISDOM: Throw the actual response data. This allows the onError
        // handler to parse it and transition the machine to a consistent state
        // that reflects the server's view, rather than a generic error state.
        throw responseData;
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
        console.log("[auth-machine:refreshToken] Raw response from auth_test canary:", canaryData);
      } catch (e) {
        console.error('refreshToken actor: Exception during canary request.', e);
        throw new Error('Exception during canary request.');
      }

      const parsedStatus = _parseAuthStatusRpcResponseToAuthStatus(responseData);
      const rawResponseWithTimestamp = { ...responseData, timestamp: new Date().toISOString() };
      const canaryResponseWithTimestamp = canaryData ? { ...canaryData, timestamp: new Date().toISOString() } : null;
      
      console.log("[auth-machine:refreshToken] Refresh and canary successful. Returning data.");
      return { parsedStatus, rawResponse: rawResponseWithTimestamp, canaryResponse: canaryResponseWithTimestamp };
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

      // NEMESIS BUG FIX: After a successful login, force cookie synchronization
      // with a canary request before proceeding. See `refreshToken` actor for details.
      let canaryData = null;
      try {
        const { data, error: canaryError } = await input.client.rpc('auth_test');
        if (canaryError) {
          console.error('login actor: Canary request to auth_test failed after login.', canaryError);
          throw new Error('Canary request failed after login.');
        }
        canaryData = data;
      } catch (e) {
        console.error('login actor: Exception during canary request.', e);
        throw new Error('Exception during canary request.');
      }

      const status = _parseAuthStatusRpcResponseToAuthStatus(responseData);
      const rawResponseWithTimestamp = { ...responseData, timestamp: new Date().toISOString() };
      const canaryResponseWithTimestamp = canaryData ? { ...canaryData, timestamp: new Date().toISOString() } : null;

      return { status, rawResponse: rawResponseWithTimestamp, canaryResponse: canaryResponseWithTimestamp };
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
    authApiResponseLog: {},
  },
  states: {
    re_initializing: {
      tags: 'ui-authenticated',
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
      tags: 'ui-authenticated',
      invoke: {
        id: 'checkAuthStatus',
        src: 'checkAuthStatus',
        input: ({ context }) => ({ client: context.client }),
        onDone: {
          actions: assign(({ event, context }) => {
            const now = Date.now();
            return {
              ...event.output.status,
              client: context.client,
              authApiResponseLog: addAndPurgeLog(context.authApiResponseLog, 'auth_status', event.output.rawResponse, now),
            }
          }),
          target: 'evaluating_initial_session'
        },
        onError: {
          target: 'idle_unauthenticated',
          actions: assign({ error_code: 'RPC_ERROR' })
        }
      }
    },
    evaluating_initial_session: {
      tags: 'ui-authenticated',
      always: [
        {
          target: 'initial_refreshing',
          guard: ({ context }) => context.expired_access_token_call_refresh
        },
        { target: 'idle_authenticated', guard: ({ context }) => context.isAuthenticated },
        { target: 'idle_unauthenticated' }
      ]
    },
    initial_refreshing: {
      tags: 'ui-authenticated',
      invoke: {
        id: 'refreshToken',
        src: 'refreshToken',
        input: ({ context }) => ({ client: context.client }),
        onDone: {
          actions: assign(({ event, context }) => {
            const now = Date.now();
            let log = addAndPurgeLog(context.authApiResponseLog, 'refresh', event.output.rawResponse, now);
            log = addAndPurgeLog(log, 'post_refresh_canary', event.output.canaryResponse, now + 1);
            return {
              ...event.output.parsedStatus,
              client: context.client,
              authApiResponseLog: log,
            }
          }),
          // After a successful initial refresh, we are authenticated.
          target: 'idle_authenticated'
        },
        onError: {
          target: 'idle_unauthenticated',
          actions: assign(({ event, context }) => {
            const now = Date.now();
            // The actor throws the raw response on failure, so we parse it here.
            const parsedStatus = _parseAuthStatusRpcResponseToAuthStatus(event.error);
            const rawResponseWithTimestamp = { ...(event.error as object), timestamp: new Date().toISOString() };
            return {
              ...parsedStatus,
              client: context.client,
              authApiResponseLog: addAndPurgeLog(context.authApiResponseLog, 'refresh_error', rawResponseWithTimestamp, now),
              error_code: 'INITIAL_REFRESH_FAILED'
            };
          })
        }
      }
    },
    idle_authenticated: {
      tags: 'ui-authenticated',
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
        stable: {
          tags: 'auth-stable',
        },
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
                actions: assign(({ event, context }) => {
                  const now = Date.now();
                  return {
                    ...event.output.status,
                    client: context.client,
                    authApiResponseLog: addAndPurgeLog(context.authApiResponseLog, 'auth_status', event.output.rawResponse, now),
                  }
                }),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => event.output.outcome === 'ok' && !event.output.status.isAuthenticated,
                actions: assign(({ event, context }) => {
                  const now = Date.now();
                  return {
                    ...event.output.status,
                    client: context.client,
                    authApiResponseLog: addAndPurgeLog(context.authApiResponseLog, 'auth_status', event.output.rawResponse, now),
                  }
                }),
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
                actions: assign(({ event, context }) => {
                  const now = Date.now();
                  let log = addAndPurgeLog(context.authApiResponseLog, 'refresh', event.output.rawResponse, now);
                  log = addAndPurgeLog(log, 'post_refresh_canary', event.output.canaryResponse, now + 1);
                  return {
                    ...event.output.parsedStatus,
                    client: context.client,
                    authApiResponseLog: log,
                  }
                }),
              },
              {
                target: '#auth.idle_unauthenticated',
                guard: ({ event }) => !event.output.parsedStatus.isAuthenticated,
                actions: assign(({ event, context }) => {
                  const now = Date.now();
                  let log = addAndPurgeLog(context.authApiResponseLog, 'refresh', event.output.rawResponse, now);
                  log = addAndPurgeLog(log, 'post_refresh_canary', event.output.canaryResponse, now + 1);
                  return {
                    ...event.output.parsedStatus,
                    client: context.client,
                    authApiResponseLog: log,
                  }
                }),
              },
            ],
            onError: {
              target: '#auth.idle_unauthenticated',
              actions: assign(({ event, context }) => {
                const now = Date.now();
                // The actor throws the raw response on failure, so we parse it here.
                const parsedStatus = _parseAuthStatusRpcResponseToAuthStatus(event.error);
                const rawResponseWithTimestamp = { ...(event.error as object), timestamp: new Date().toISOString() };
                return {
                  ...parsedStatus,
                  client: context.client,
                  authApiResponseLog: addAndPurgeLog(context.authApiResponseLog, 'background_refresh_error', rawResponseWithTimestamp, now),
                  error_code: 'BACKGROUND_REFRESH_FAILED'
                };
              })
            }
          }
        }
      }
    },
    idle_unauthenticated: {
      tags: 'auth-stable',
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
            assign(({ event, context }) => {
              const now = Date.now();
              let log = addAndPurgeLog(context.authApiResponseLog, 'login', event.output.rawResponse, now);
              log = addAndPurgeLog(log, 'post_login_canary', event.output.canaryResponse, now + 1);
              return {
                ...event.output.status,
                client: context.client,
                authApiResponseLog: log,
              };
            }),
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

export const authMachineAtom = atomWithMachine(authMachine, {
  inspect: inspector,
});
