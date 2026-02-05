import { atom } from 'jotai';
import { atomWithMachine } from 'jotai-xstate';
import { createMachine, assign, setup, type SnapshotFrom } from 'xstate';
import { atomEffect } from 'jotai-effect';
import { inspector } from './inspector';
import { logger } from '@/lib/client-logger';

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
  // Timing fields for robust navigation polling (declarative state, not mutable refs)
  sideEffectStartTime?: number;    // timestamp when sideEffect was set
  sideEffectStartPathname?: string; // pathname when sideEffect was set (for polling comparison)
}

const publicPaths = ['/login'];
const isPublicPath = (path: string) => publicPaths.some(p => path.startsWith(p));

type NavigationEvent = 
  | { type: 'CONTEXT_UPDATED'; value: Partial<Omit<NavigationContext, 'sideEffect'>> }
  | { type: 'CLEAR_SIDE_EFFECT'; reason: 'polling_detected_completion' | 'timeout' };

/**
 * INTENT: Handle TWO timing scenarios that can cause navigation hangs:
 * 
 * TOO SLOW DETECTION (handled here):
 * - sideEffect executes but navigation fails/hangs beyond reasonable time
 * - After 3 seconds (10 × 300ms keystroke intervals), assume failure
 * - Clear sideEffect and force transition back to safe 'evaluating' state
 * - Machine will re-evaluate current conditions and determine correct action
 * 
 * TOO FAST DETECTION (handled in NavigationManager polling):
 * - sideEffect executes and navigation completes before React can update
 * - Polling detects pathname changes that weren't captured by normal flow
 * - Immediately sends CONTEXT_UPDATED to trigger sideEffect clearing
 * 
 * Both ensure sideEffect is eventually cleared to prevent infinite hangs
 */
function handleSideEffectTimeout(
  context: NavigationContext, 
  event: Extract<NavigationEvent, { type: 'CONTEXT_UPDATED' }>,
  stateName: string
): NavigationContext {
  const updatedContext = { ...context, ...event.value };
  
  // TOO SLOW DETECTION: sideEffect has been active beyond reasonable time (3 seconds)
  if (context.sideEffectStartTime && 
      Date.now() - context.sideEffectStartTime > 3000) {
    
    // JS ERROR level logging with full diagnostic info for Seq analysis
    console.error('Navigation sideEffect TIMEOUT (too slow) - resetting to safe state', {
      intent: 'TOO_SLOW_DETECTION',
      duration: Date.now() - context.sideEffectStartTime,
      sideEffect: context.sideEffect,
      currentContext: context,
      eventValue: event.value,
      machineState: stateName,
      timestamp: new Date().toISOString(),
      reason: 'sideEffect_timeout_recovery_too_slow'
    });
    
    // SAFE RECOVERY: Clear sideEffect and force transition back to evaluating state
    // Machine will re-determine correct action based on current conditions
    return { 
      ...updatedContext, 
      sideEffect: undefined, 
      sideEffectStartTime: undefined,
      sideEffectStartPathname: undefined,
    };
  }
  
  return updatedContext;
}

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
      entry: [
        assign({ sideEffect: undefined, sideEffectStartTime: undefined, sideEffectStartPathname: undefined }),
        ({ context }) => logger.debug('nav-machine:evaluating', `path: ${context.pathname}`, {
          isAuthenticated: context.isAuthenticated,
          isAuthLoading: context.isAuthLoading,
          setupPath: context.setupPath,
        }),
      ],
      always: [
        {
          target: 'savingPathForLoginRedirect',
          guard: ({ context }) =>
            !context.isAuthenticated &&
            !context.isAuthLoading && // Only redirect if we are sure they are not logged in, not just loading.
            !isPublicPath(context.pathname),
        },
        {
          // FAIL FAST: If authenticated, on /login, auth is stable, and setup data is loaded,
          // skip verification and redirect immediately. This avoids the 4+ second delay
          // waiting for setup data to load after a token refresh.
          target: 'clearingLastKnownPathBeforeRedirect',
          guard: ({ context }) =>
            context.isAuthenticated &&
            context.pathname === '/login' &&
            context.isAuthStable &&
            !context.isAuthLoading &&
            !context.isSetupLoading, // Only redirect once setup check is complete
        },
        {
          // DECLARATIVE STALE AUTH DETECTION:
          // If isAuthenticated && pathname === '/login' && auth is stable (not loading),
          // BUT setup is still loading, wait in idle. Once setup loading completes,
          // the above guard will trigger and redirect immediately.
          // 
          // This is a fallback for edge cases where the client thinks it's authenticated
          // but setup data suggests otherwise. In practice, after initial_refreshing,
          // we know auth is valid, so this is mostly defensive.
          target: 'verifyingAuthBeforeLoginRedirect',
          guard: ({ context }) => 
            context.isAuthenticated && 
            context.pathname === '/login' && 
            context.isAuthStable && 
            !context.isAuthLoading &&
            context.isSetupLoading, // Only verify if setup is still loading (rare case)
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
      entry: [
        assign({ sideEffect: undefined, sideEffectStartTime: undefined, sideEffectStartPathname: undefined }),
        () => logger.debug('nav-machine:idle', 'Reached stable state.'),
      ],
      // This state is now stable. The cleanup logic has been moved to be part
      // of the `redirectingFromLogin` flow, making it more robust.
    },
    /**
     * An intermediate state that triggers the 'savePath' side-effect to store the
     * user's current location before redirecting them to the login page.
     */
    savingPathForLoginRedirect: {
      entry: [
        assign(({ context }) => ({ 
          sideEffect: { action: 'savePath' },
          sideEffectStartTime: Date.now(),
          sideEffectStartPathname: context.pathname,
        })),
        ({ context }) => logger.debug('nav-machine:savingPathForLoginRedirect', `Saving path ${context.pathname} before redirect to /login`),
      ],
      always: 'redirectingToLogin',
    },
    /**
     * A state that triggers a 'navigate' side-effect to send the user to /login.
     */
     redirectingToLogin: {
       entry: [
         assign(({ context }) => ({
           sideEffect: { action: 'navigateAndSaveJournal', targetPath: '/login' },
           sideEffectStartTime: Date.now(),
           sideEffectStartPathname: context.pathname,
         })),
         () => logger.debug('nav-machine:redirectingToLogin', 'Redirecting to /login'),
       ],
       on: {
          CONTEXT_UPDATED: {
            actions: assign(( { context, event } ) => 
              // TOO SLOW DETECTION: Apply timeout handling for redirectingToLogin
              handleSideEffectTimeout(context, event, 'redirectingToLogin')
            ),
          },
          CLEAR_SIDE_EFFECT: [
            {
              // TIMEOUT RECOVERY: Transition to evaluating to retry navigation.
              target: 'evaluating',
              guard: ({ event }) => event.reason === 'timeout',
              actions: assign(({ context }) => ({
                ...context,
                sideEffect: undefined,
                sideEffectStartTime: undefined,
                sideEffectStartPathname: undefined,
              })),
            },
            {
              // FAST DETECTION: Just clear sideEffect, let always guards handle transition.
              actions: assign(({ context }) => ({
                ...context,
                sideEffect: undefined,
                sideEffectStartTime: undefined,
                sideEffectStartPathname: undefined,
              })),
            },
          ],
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
       entry: [
         assign(({ context }) => ({
           sideEffect: {
             action: 'navigateAndSaveJournal',
             targetPath: context.setupPath!,
           },
           sideEffectStartTime: Date.now(),
           sideEffectStartPathname: context.pathname,
         })),
         ({ context }) => logger.debug('nav-machine:redirectingToSetup', `Redirecting to setup path: ${context.setupPath}`),
       ],
       on: {
          CONTEXT_UPDATED: {
            actions: assign(( { context, event } ) => 
              // TOO SLOW DETECTION: Apply timeout handling for redirectingToSetup
              handleSideEffectTimeout(context, event, 'redirectingToSetup')
            ),
          },
          CLEAR_SIDE_EFFECT: [
            {
              // TIMEOUT RECOVERY: Transition to evaluating to retry navigation.
              target: 'evaluating',
              guard: ({ event }) => event.reason === 'timeout',
              actions: assign(({ context }) => ({
                ...context,
                sideEffect: undefined,
                sideEffectStartTime: undefined,
                sideEffectStartPathname: undefined,
              })),
            },
            {
              // FAST DETECTION: Just clear sideEffect, let always guards handle transition.
              actions: assign(({ context }) => ({
                ...context,
                sideEffect: undefined,
                sideEffectStartTime: undefined,
                sideEffectStartPathname: undefined,
              })),
            },
          ],
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
     * This state cleans up artifacts of the login/redirect process. It runs
     * before any redirect away from the login page.
     */
    clearingLastKnownPathBeforeRedirect: {
      entry: [
        assign(({ context }) => ({
          // BATTLE WISDOM: Conditionally dispatch the side-effect. If the path is
          // already null, we do nothing. This prevents an unnecessary state update
          // and allows the `always` transition below to handle the case immediately.
          sideEffect: context.lastKnownPath !== null ? { action: 'clearLastKnownPath' } : undefined,
          sideEffectStartTime: context.lastKnownPath !== null ? Date.now() : undefined,
          sideEffectStartPathname: context.lastKnownPath !== null ? context.pathname : undefined,
        })),
        ({ context }) => logger.debug('nav-machine:clearingLastKnownPathBeforeRedirect', `lastKnownPath: ${context.lastKnownPath}`),
      ],
      // If lastKnownPath was already null, no side-effect was dispatched.
      // We can immediately proceed to redirect, preventing a deadlock.
      always: {
        target: 'redirectingFromLogin',
        guard: ({ context }) => context.lastKnownPath === null,
      },
      on: {
        CONTEXT_UPDATED: {
          target: 'redirectingFromLogin',
          // If a side-effect was dispatched, we wait for the context update
          // that confirms it has completed before we redirect.
          guard: ({ event }) => event.value.lastKnownPath === null,
          actions: assign(({ context, event }) => ({ ...context, ...event.value })),
        }
      }
    },
    /**
     * DECLARATIVE STALE AUTH DETECTION:
     * This state triggers auth verification BEFORE attempting to redirect away from /login.
     * 
     * The condition (isAuthenticated && pathname === '/login' && isAuthStable) is SUSPICIOUS:
     * - An authenticated user shouldn't be on /login unless the server put them there
     * - This happens when JWT expires server-side but client still thinks isAuthenticated=true
     * - Instead of trying to redirect and detecting failure via timeout, we PROACTIVELY verify
     * 
     * LIFECYCLE:
     * 1. Enter with sideEffect: { action: 'revalidateAuth' }
     * 2. NavigationManager sees revalidateAuth, calls sendAuth({ type: 'CHECK' })
     * 3. Auth machine goes to checking state, isAuthStable becomes false
     * 4. When auth completes, isAuthStable becomes true again
     * 5. Transition back to evaluating with fresh auth state
     * 6. evaluating now makes the correct decision based on actual auth status
     */
    verifyingAuthBeforeLoginRedirect: {
      entry: [
        assign(({ context }) => ({
          sideEffect: { action: 'revalidateAuth' },
          sideEffectStartTime: Date.now(),
          sideEffectStartPathname: context.pathname,
        })),
        () => logger.debug('nav-machine:verifyingAuthBeforeLoginRedirect', 'Suspicious state detected: authenticated but on /login. Verifying auth status before redirect.'),
      ],
      on: {
        CONTEXT_UPDATED: {
          actions: assign(({ context, event }) => {
            const newContext = { ...context, ...event.value };
            
            // When auth becomes unstable (checking started), clear sideEffect
            // The auth machine has taken over - we just wait for it to finish
            if (context.sideEffect?.action === 'revalidateAuth' && newContext.isAuthStable === false) {
              logger.debug('nav-machine:verifyingAuthBeforeLoginRedirect', 'Auth revalidation in progress, clearing sideEffect');
              return {
                ...newContext,
                sideEffect: undefined,
                sideEffectStartTime: undefined,
                sideEffectStartPathname: undefined,
              };
            }
            return newContext;
          }),
        },
        CLEAR_SIDE_EFFECT: {
          // Ignore polling timeouts - we're waiting for auth machine, not navigation
          actions: assign(({ context, event }) => {
            logger.debug('nav-machine:verifyingAuthBeforeLoginRedirect:CLEAR_SIDE_EFFECT', 'Ignoring while waiting for auth', {
              reason: event.reason,
            });
            return context;
          }),
        },
      },
      always: [
        {
          // Auth verification complete AND still authenticated - proceed to redirect
          // We go directly to clearingLastKnownPathBeforeRedirect to avoid re-triggering
          // the verifyingAuthBeforeLoginRedirect guard in evaluating
          target: 'clearingLastKnownPathBeforeRedirect',
          guard: ({ context }) => 
            !context.sideEffect && // sideEffect cleared when auth started
            context.isAuthStable === true && // auth has finished
            context.isAuthenticated === true, // still authenticated - token was valid or refresh succeeded
        },
        {
          // Auth verification complete AND NOT authenticated - go to evaluating
          // evaluating will see !isAuthenticated on /login and go to idle
          target: 'evaluating',
          guard: ({ context }) => 
            !context.sideEffect && // sideEffect cleared when auth started
            context.isAuthStable === true && // auth has finished
            context.isAuthenticated === false, // no longer authenticated - token expired and refresh failed
        },
      ],
    },
    /**
     * A state that triggers a 'navigate' side-effect to redirect the user away
     * from the login page after they have successfully authenticated. The destination
     * is prioritized: setup page, last known path, or dashboard.
     * 
     * NOTE: By the time we reach this state, auth has already been verified by
     * verifyingAuthBeforeLoginRedirect, so we can trust isAuthenticated is accurate.
     */
    redirectingFromLogin: {
      entry: [
        assign(({ context }) => {
          const targetPath = context.setupPath || context.lastKnownPath || '/';
          return {
            sideEffect: {
              action: 'navigateAndSaveJournal',
              targetPath: targetPath === '/login' ? '/' : targetPath,
            },
            sideEffectStartTime: Date.now(),
            sideEffectStartPathname: context.pathname,
          };
        }),
        ({ context }) => {
          const targetPath = context.setupPath || context.lastKnownPath || '/';
          logger.debug('nav-machine:redirectingFromLogin', `Redirecting away from /login to ${targetPath === '/login' ? '/' : targetPath}`);
        },
      ],
      on: {
        CONTEXT_UPDATED: {
          actions: assign(({ context, event }) => 
            // Standard timeout handling - auth has already been verified
            handleSideEffectTimeout(context, event, 'redirectingFromLogin')
          ),
        },
        CLEAR_SIDE_EFFECT: [
          {
            // TIMEOUT RECOVERY: If navigation timed out, transition to evaluating to retry.
            // This prevents the machine from getting stuck when router.push() succeeds
            // but the pathname doesn't update (e.g., due to Next.js App Router issues).
            target: 'evaluating',
            guard: ({ event }) => event.reason === 'timeout',
            actions: assign(({ context }) => ({
              ...context,
              sideEffect: undefined,
              sideEffectStartTime: undefined,
              sideEffectStartPathname: undefined,
            })),
          },
          {
            // FAST DETECTION: Navigation completed quickly, just clear sideEffect.
            // The always guards will handle the transition to idle.
            actions: assign(({ context }) => ({
              ...context,
              sideEffect: undefined,
              sideEffectStartTime: undefined,
              sideEffectStartPathname: undefined,
            })),
          },
        ],
      },
      always: [
        {
          // Escape hatch: If we become unauthenticated while redirecting away from login,
          // stop waiting and re-evaluate immediately. This prevents a deadlock.
          target: 'evaluating',
          guard: ({ context }) => context.isAuthenticated === false,
        },
        {
          target: 'idle',
          // Guard: Only transition once we are no longer on the login page.
          guard: ({ context }) => context.pathname !== '/login',
        },
      ],
    }
  },
});

export const navigationMachineAtom = atomWithMachine(navigationMachine, {
  inspect: inspector,
});
