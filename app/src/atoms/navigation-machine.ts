import { atom } from 'jotai';
import { atomWithMachine } from 'jotai-xstate';
import { createMachine, assign, setup, type SnapshotFrom } from 'xstate';
import { atomEffect } from 'jotai-effect';
import { inspector } from './inspector';

/**
 * Navigation State Machine (navigationMachine)
 *
 * This file defines the state machine that governs all programmatic navigation,
 * acting as the central authority for application-level redirects. It prevents
 * race conditions and complex, scattered routing logic by centralizing decisions.
 *
 * Responsibilities:
 * - Redirecting unauthenticated users from protected pages to the login page.
 * - Redirecting authenticated users away from the login page.
 * - Handling redirects for required setup flows (e.g., to /getting-started).
 * - Commanding navigation side-effects, which are then executed by the `NavigationManager`.
 *
 * Interactions:
 * - It consumes context about the user's authentication state (from `authMachine`),
 *   setup status (`setupPath`), and the current URL path (`pathname`).
 * - It produces `sideEffect` commands in its context, but does not execute them directly.
 * - It does NOT manage authentication state or UI state for individual pages.
 */
export interface NavigationContext {
  pathname: string;
  isAuthenticated: boolean;
  isAuthLoading: boolean;
  isAuthStable: boolean;
  isSetupLoading: boolean;
  setupPath: string | null;
  lastKnownPath: string | null;
  sideEffect?: {
    action: 'savePath' | 'clearLastKnownPath' | 'revalidateAuth' | 'navigateAndSaveJournal';
    targetPath?: string;
  };
}

const publicPaths = ['/login'];
const isPublicPath = (path: string) => publicPaths.some(p => path.startsWith(p));

type NavigationEvent = { type: 'CONTEXT_UPDATED'; value: Partial<Omit<NavigationContext, 'sideEffect'>> };

export const navigationMachine = setup({
  types: {
    context: {} as NavigationContext,
    events: {} as NavigationEvent,
  },
}).createMachine({
  id: 'navigation',
  initial: 'booting',
  on: {
    CONTEXT_UPDATED: [
      {
        target: '.evaluating',
        // This is the guarded "re-evaluate" transition. It will only be taken if
        // the machine has not commanded a side-effect. If a side-effect is active,
        // the machine will wait in its current state, allowing local `on.CONTEXT_UPDATED`
        // handlers to watch for the side-effect's completion. This is the core
        // mechanism that prevents infinite loops.
        guard: ({ context }) => !context.sideEffect,
        actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
      },
      {
        // This is the fallback "just update context" action. It runs if the guard
        // above returns false. This ensures the machine's context is always kept
        // up-to-date, even when it's not re-evaluating its state.
        actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
      },
    ],
  },
  context: {
    pathname: '',
    isAuthenticated: false,
    isAuthLoading: true,
    isAuthStable: false,
    isSetupLoading: true,
    setupPath: null,
    lastKnownPath: null,
    sideEffect: undefined,
  },
  states: {
    /**
     * The initial state on machine creation. It waits for the initial authentication
     * and setup checks to complete before moving to 'evaluating'.
     */
    booting: {
      // Immediately transition to evaluating. The evaluating state will handle the logic
      // of what to do based on the loading status.
      always: 'evaluating',
    },
    /**
     * The central decision-making state. It has no duration; its `always` transitions
     * immediately move the machine to the correct state based on the current context
     * (e.g., isAuthenticated, current path, setup requirements).
     */
    evaluating: {
      entry: assign({ sideEffect: undefined }),
      always: [
        {
          target: 'savingPathForLoginRedirect',
          guard: ({ context }) =>
            !context.isAuthenticated &&
            !context.isAuthLoading && // Only redirect if we are sure they are not logged in, not just loading.
            !isPublicPath(context.pathname),
        },
        {
          target: 'revalidatingOnLoginPage',
          guard: ({ context }) => context.isAuthenticated && !context.isAuthLoading && context.pathname === '/login',
        },
        {
          target: 'redirectingToSetup',
          guard: ({ context }) =>
            context.isAuthenticated &&
            !context.isAuthLoading && // Wait for auth check to complete.
            context.pathname === '/' && // Only check for setup redirect when user is on the dashboard.
            !!context.setupPath,
        },
        { target: 'idle' },
      ],
    },
    /**
     * A stable state where no navigation action is required. The machine waits here
     * for a CONTEXT_UPDATED event that changes the conditions, which will trigger a
     * transition back to 'evaluating'. It also handles post-login cleanup.
     */
    idle: {
      tags: 'stable',
      // BATTLE WISDOM: Always clear side-effects upon entering a stable state.
      // This prevents a stale side-effect from a previous navigation flow (like
      // redirecting TO login) from blocking the machine from re-evaluating its
      // state when a new context update arrives (like a successful login).
      entry: assign({ sideEffect: undefined }),
      // This state is now stable. The cleanup logic has been moved to be part
      // of the `redirectingFromLogin` flow, making it more robust.
    },
    /**
     * An intermediate state that commands an auth re-validation when an authenticated
     * user lands on the login page. This is a crucial step to break redirect loops
     * caused by server-side redirects with stale tokens.
     */
    revalidatingOnLoginPage: {
      entry: assign({ sideEffect: { action: 'revalidateAuth' } }),
      on: {
        CONTEXT_UPDATED: {
          target: 'redirectingFromLogin',
          // Guard: Wait only for the auth re-validation to complete. The `redirectingFromLogin`
          // state will then use the latest `setupPath` from the context to make its final
          // navigation decision. Waiting for `isSetupLoading` here can cause a deadlock.
          // BATTLE WISDOM: The guard must inspect the incoming event's value, not the
          // machine's current context. The context is not updated until after the guard
          // passes, creating a race condition. This explicitly checks for the `false`
          // signal from the event payload.
          guard: ({ event }) => event.value.isAuthLoading === false,
          actions: assign(({ context, event }) => ({ ...context, ...event.value })),
        }
      }
    },
    /**
     * An intermediate state that triggers the 'savePath' side-effect to store the
     * user's current location before redirecting them to the login page.
     */
    savingPathForLoginRedirect: {
      entry: assign({ sideEffect: { action: 'savePath' } }),
      always: 'redirectingToLogin',
    },
    /**
     * A state that triggers a 'navigate' side-effect to send the user to /login.
     */
    redirectingToLogin: {
      entry: assign({
        sideEffect: { action: 'navigateAndSaveJournal', targetPath: '/login' },
      }),
      on: {
        CONTEXT_UPDATED: {
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      },
      always: [
        {
          // Escape hatch: If we become authenticated while redirecting to login
          // (e.g., via another tab), stop waiting and re-evaluate immediately.
          target: 'evaluating',
          guard: ({ context }) => context.isAuthenticated === true,
        },
        {
          target: 'idle',
          guard: ({ context }) => context.pathname === '/login',
        },
      ]
    },
    /**
     * A state that triggers a 'navigate' side-effect to send the user to the
     * required setup page (e.g., /getting-started or /import). This is only
     * triggered when the user is at the root path ('/').
     */
    redirectingToSetup: {
      entry: assign({
        sideEffect: ({ context }) => ({
          action: 'navigateAndSaveJournal',
          targetPath: context.setupPath!,
        }),
      }),
      on: {
        CONTEXT_UPDATED: {
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      },
      always: [
        {
          // Escape hatch: If we become unauthenticated while redirecting to setup,
          // stop waiting and re-evaluate immediately.
          target: 'evaluating',
          guard: ({ context }) => context.isAuthenticated === false,
        },
        {
          target: 'evaluating',
          // Guard: Only transition once we are no longer on the root path.
          guard: ({ context }) => context.pathname !== '/',
        },
      ]
    },
    /**
     * A state that triggers a 'navigate' side-effect to redirect the user away
     * from the login page after they have successfully authenticated. The destination
     * is prioritized: setup page, last known path, or dashboard.
     */
    redirectingFromLogin: {
      entry: assign({
        sideEffect: ({ context }) => {
          const targetPath = context.setupPath || context.lastKnownPath || '/';
          return {
            action: 'navigateAndSaveJournal',
            targetPath: targetPath === '/login' ? '/' : targetPath,
          };
        }
      }),
      on: {
        // When a context update happens, just apply it. The `always` transition
        // will then re-evaluate the state based on the new context.
        CONTEXT_UPDATED: {
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      },
      always: [
        {
          // Escape hatch: If we become unauthenticated while redirecting away from login,
          // stop waiting and re-evaluate immediately. This prevents a deadlock.
          target: 'evaluating',
          guard: ({ context }) => context.isAuthenticated === false,
        },
        {
          target: 'cleanupAfterRedirect',
          // Guard: Only transition once we are no longer on the login page.
          guard: ({ context }) => context.pathname !== '/login',
        },
      ]
    },
    /**
     * This state cleans up artifacts of the login/redirect process. It runs
     * after any redirect away from the login page.
     */
    cleanupAfterRedirect: {
      entry: assign({
        // BATTLE WISDOM: Conditionally dispatch the side-effect. If the path is
        // already null, we do nothing. This prevents an unnecessary state update
        // and allows the `always` transition below to handle the case immediately.
        sideEffect: ({ context }) => context.lastKnownPath !== null ? { action: 'clearLastKnownPath' } : undefined
      }),
      // If lastKnownPath was already null, no side-effect was dispatched.
      // We can immediately re-evaluate, preventing a deadlock.
      always: {
        target: 'evaluating',
        guard: ({ context }) => context.lastKnownPath === null,
      },
      on: {
        CONTEXT_UPDATED: {
          target: 'evaluating',
          // If a side-effect was dispatched, we wait for the context update
          // that confirms it has completed.
          guard: ({ event }) => event.value.lastKnownPath === null,
          actions: assign(({ context, event }) => ({ ...context, ...event.value })),
        }
      }
    }
  },
});

export const navigationMachineAtom = atomWithMachine(navigationMachine, {
  inspect: inspector,
});
