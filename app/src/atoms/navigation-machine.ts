import { atom } from 'jotai';
import { atomWithMachine } from 'jotai-xstate';
import { createMachine, assign, setup, type SnapshotFrom } from 'xstate';
import { atomEffect } from 'jotai-effect';
import { addEventJournalEntryAtom, stateInspectorVisibleAtom } from './app';

// This file defines the state machine that governs all programmatic navigation.
// It centralizes the complex logic previously spread across RedirectGuard and RedirectHandler.

export interface NavigationContext {
  pathname: string;
  isAuthenticated: boolean;
  isAuthLoading: boolean;
  isSetupLoading: boolean;
  setupPath: string | null;
  lastKnownPath: string | null;
  sideEffect?: {
    action: 'navigate' | 'savePath' | 'clearLastKnownPath' | 'revalidateAuth';
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
  id: 'navigationV2',
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
          // Guard: Wait for both auth and setup checks to complete before proceeding.
          // This prevents a race condition where the redirect happens before the
          // required setup path has been calculated.
          guard: ({ context }) => !context.isAuthLoading && !context.isSetupLoading,
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
        sideEffect: { action: 'navigate', targetPath: '/login' },
      }),
    },
    /**
     * A state that triggers a 'navigate' side-effect to send the user to the
     * required setup page (e.g., /getting-started or /import). This is only
     * triggered when the user is at the root path ('/').
     */
    redirectingToSetup: {
      entry: assign({
        sideEffect: ({ context }) => ({
          action: 'navigate',
          targetPath: context.setupPath!,
        }),
      }),
      // After commanding the navigation, wait for the context to update with a new path.
      on: {
        CONTEXT_UPDATED: {
          target: '#navigationV2.evaluating',
          // Guard: Only transition once we are no longer on the root path.
          guard: ({ event }) => event.value.pathname !== '/',
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      }
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
            action: 'navigate',
            targetPath: targetPath === '/login' ? '/' : targetPath,
          };
        }
      }),
      // After commanding navigation, wait for the context to update with a new path.
      on: {
        CONTEXT_UPDATED: {
          target: '#navigationV2.cleanupAfterRedirect',
          // Guard: Only transition once we are no longer on the login page.
          guard: ({ event }) => event.value.pathname !== '/login',
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      }
    },
    /**
     * This state cleans up artifacts of the login/redirect process. It runs
     * after any redirect away from the login page.
     */
    cleanupAfterRedirect: {
      tags: 'stable',
      entry: assign({
        sideEffect: { action: 'clearLastKnownPath' }
      }),
      // After commanding cleanup, wait for the context to update with the cleared path.
      on: {
        CONTEXT_UPDATED: {
          target: '#navigationV2.evaluating',
          // Guard: Only transition once the last known path has been cleared.
          guard: ({ event }) => event.value.lastKnownPath === null,
          actions: assign(( { context, event } ) => ({ ...context, ...event.value })),
        }
      }
    }
  },
});

export const navigationMachineAtom = atomWithMachine(navigationMachine);

const prevNavMachineSnapshotAtom = atom<SnapshotFrom<typeof navigationMachine> | null>(null);

/**
 * Scribe Effect for the Navigation State Machine.
 *
 * When the StateInspector is visible, this effect will log every state
 * transition to the Event Journal and the browser console, providing a detailed
 * trace of all programmatic navigation decisions. It remains dormant otherwise.
 */
export const navMachineScribeEffectAtom = atomEffect((get, set) => {
  const isInspectorVisible = get(stateInspectorVisibleAtom);
  if (!isInspectorVisible) {
    if (get(prevNavMachineSnapshotAtom) !== null) {
      set(prevNavMachineSnapshotAtom, null); // Reset when not visible.
    }
    return;
  }

  const currentSnapshot = get(navigationMachineAtom);
  const prevSnapshot = get(prevNavMachineSnapshotAtom);
  set(prevNavMachineSnapshotAtom, currentSnapshot);

  if (!prevSnapshot) {
    return; // Don't log on the first run.
  }
  
  // A more robust check to see if a meaningful change has occurred.
  // This prevents infinite loops caused by new object references for unchanged state.
  const valueChanged = JSON.stringify(currentSnapshot.value) !== JSON.stringify(prevSnapshot.value);
  const contextChanged = JSON.stringify(currentSnapshot.context) !== JSON.stringify(prevSnapshot.context);

  if (valueChanged || contextChanged) {
    const event = (currentSnapshot as any).event ?? { type: 'unknown' };
    const entry = {
      machine: 'nav' as const,
      from: prevSnapshot.value,
      to: currentSnapshot.value,
      event: event,
      reason: `Transitioned from ${JSON.stringify(prevSnapshot.value)} to ${JSON.stringify(currentSnapshot.value)} on event ${event.type}`
    };
    set(addEventJournalEntryAtom, entry);
    console.log(`[Scribe:Nav]`, entry.reason, { from: entry.from, to: entry.to, event: entry.event });
  }
});
