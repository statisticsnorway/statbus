"use client";

/**
 * General Application State Atoms and Hooks
 *
 * This file contains atoms and hooks for managing high-level application state,
 * such as the REST client instance, time context, initialization status, and readiness.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable, createJSONStorage } from 'jotai/utils'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useEffect } from 'react'
import { atomEffect } from 'jotai-effect'

import type { Tables } from '@/lib/database.types'

import { isAuthenticatedStrictAtom, authStatusAtom, authStatusUnstableDetailsAtom, isUserConsideredAuthenticatedForUIAtom } from './auth'
import { baseDataAtom, defaultTimeContextAtom, timeContextsAtom, refreshBaseDataAtom, useBaseData } from './base-data'
import { activityCategoryStandardSettingAtomAsync, numberOfRegionsAtomAsync } from './getting-started'
import { refreshWorkerStatusAtom, useWorkerStatus, type WorkerStatusType } from './worker_status'
import { restClientAtom } from './rest-client'
import { selectedUnitsAtom, searchStateAtom } from './search'
import { selectAtom } from 'jotai/utils'

// ============================================================================
// TIME CONTEXT ATOMS & HOOKS - Replace TimeContext
// ============================================================================

// Persistent selected time context
export const selectedTimeContextAtom = atomWithStorage<Tables<"time_context"> | null>(
  'selectedTimeContext',
  null
)

export const useTimeContext = () => {
  const [selectedTimeContext, setSelectedTimeContext] = useAtom(selectedTimeContextAtom)
  const timeContexts = useAtomValue(timeContextsAtom)
  const defaultTimeContext = useAtomValue(defaultTimeContextAtom)
  
  // Auto-select default if none selected and default exists
  useEffect(() => {
    if (!selectedTimeContext && defaultTimeContext) {
      setSelectedTimeContext(defaultTimeContext)
    }
  }, [selectedTimeContext, defaultTimeContext, setSelectedTimeContext])
  
  return {
    selectedTimeContext,
    setSelectedTimeContext,
    timeContexts,
    defaultTimeContext,
  }
}

// ============================================================================
// APP INITIALIZATION STATE ATOMS & HOOKS
// ============================================================================

// Atom to track if search state has been initialized from URL params
export const searchStateInitializedAtom = atom(false);

// Atom to track if the client is mounted. Useful for preventing hydration issues.
export const clientMountedAtom = atom(false);

// Atom to signal a redirect required by application setup state (e.g., missing regions)
export const requiredSetupRedirectAtom = atom<string | null>(null);

// Atom to track if the initial auth check has completed successfully. This is used
// by RedirectGuard to prevent premature redirects during app startup or auth flaps.
export const initialAuthCheckCompletedAtom = atom(false);

// Unstable atom that performs the core logic for checking setup redirects.
// It is kept private to prevent components from depending on an unstable value.
const setupRedirectCheckAtomUnstable = atom((get) => {
  // Depend on the strict `isAuthenticatedAtom`. If it's false (due to logout or refresh),
  // we cannot and should not perform setup checks.
  const isAuthenticated = get(isAuthenticatedStrictAtom);
  const authStatus = get(authStatusUnstableDetailsAtom);

  if (!isAuthenticated) {
    // If not strictly authenticated, we are either logged out or refreshing.
    // In either case, setup checks cannot proceed.
    // We report `isLoading: true` if the auth state is still in flux to ensure
    // consumers like LoginClientBoundary will wait.
    return { path: null, isLoading: authStatus.loading };
  }

  // Only if strictly authenticated, proceed to trigger dependency fetches.
  const activityStandardLoadable = get(loadable(activityCategoryStandardSettingAtomAsync));
  const numberOfRegionsLoadable = get(loadable(numberOfRegionsAtomAsync));
  const baseData = get(baseDataAtom);

  const isLoading =
    activityStandardLoadable.state === 'loading' ||
    numberOfRegionsLoadable.state === 'loading' ||
    baseData.loading;

  if (isLoading) {
    return { path: null, isLoading: true };
  }

  // At this point, all data is loaded and stable.
  const currentActivityStandard = activityStandardLoadable.state === 'hasData' ? activityStandardLoadable.data : null;
  const currentNumberOfRegions = numberOfRegionsLoadable.state === 'hasData' ? numberOfRegionsLoadable.data : null;

  let path: string | null = null;

  if (currentActivityStandard === null) {
    path = '/getting-started/activity-standard';
  } else if (currentNumberOfRegions === null || currentNumberOfRegions === 0) {
    path = '/getting-started/upload-regions';
  } else if (baseData.statDefinitions.length > 0 && !baseData.hasStatisticalUnits) {
    path = '/import';
  }

  return { path, isLoading: false };
});

/**
 * Atom to calculate the required setup redirect path, if any.
 * It also exposes a loading state so consumers can wait for the check to complete.
 * This is the public, STABLE version of the atom. It uses `selectAtom` with a
 * deep equality check to prevent returning a new object reference on every
 * render, which would cause an infinite loop.
 */
export const setupRedirectCheckAtom = selectAtom(
  setupRedirectCheckAtomUnstable,
  (state) => state,
  (a, b) => JSON.stringify(a) === JSON.stringify(b)
);

// Combined authentication and base data status
export const appReadyAtom = atom((get) => {
  const authStatus = get(authStatusUnstableDetailsAtom);
  const baseData = get(baseDataAtom);

  const isAuthLoading = authStatus.loading;
  const isLoadingBaseData = baseData.loading;

  const isAuthProcessComplete = !isAuthLoading;
  // Use the UI-stabilized atom for overall readiness checks. This makes the app's
  // concept of "readiness" resilient to transient auth-state flaps. Data readiness
  // is handled by the `isBaseDataProcessComplete` flag.
  const isAuthenticatedUser = get(isUserConsideredAuthenticatedForUIAtom);
  const currentUser = !authStatus.loading ? authStatus.user : null;

  // Base data is considered ready if it's finished loading without errors.
  const isBaseDataProcessComplete = !baseData.loading && !baseData.error;

  // The dashboard is ready to render if auth is complete and base data is loaded.
  const isReadyToRenderDashboard =
    isAuthProcessComplete &&
    isAuthenticatedUser &&
    isBaseDataProcessComplete;

  return {
    isLoadingAuth: isAuthLoading,
    isLoadingBaseData: isLoadingBaseData,
    isAuthProcessComplete,
    isAuthenticated: isAuthenticatedUser,
    isBaseDataLoaded: isBaseDataProcessComplete,
    isReadyToRenderDashboard,
    user: currentUser,
  };
});

export const useAppReady = () => {
  return useAtomValue(appReadyAtom)
}

const redirectRelevantStateAtomUnstable = atom((get) => {
  const authStatus = get(authStatusUnstableDetailsAtom);
  const baseData = get(baseDataAtom);
  const activityStandardLoadable = get(loadable(activityCategoryStandardSettingAtomAsync));
  const numberOfRegionsLoadable = get(loadable(numberOfRegionsAtomAsync));
  const restClient = get(restClientAtom);

  const baseDataState = baseData.loading ? 'loading' : baseData.error ? 'hasError' : 'hasData';
  
  return {
    initialAuthCheckCompleted: get(initialAuthCheckCompletedAtom),
    authCheckDone: !authStatus.loading,
    isRestClientReady: !!restClient,
    activityStandard: activityStandardLoadable.state === 'hasData' ? activityStandardLoadable.data : null,
    numberOfRegions: numberOfRegionsLoadable.state === 'hasData' ? numberOfRegionsLoadable.data : null,
    baseDataHasStatisticalUnits: baseDataState === 'hasData' ? baseData.hasStatisticalUnits : 'BaseDataNotLoaded',
    baseDataStatDefinitionsLength: baseDataState === 'hasData' ? baseData.statDefinitions.length : 'BaseDataNotLoaded'
  }
});

// Create a memoized/stabilized version of the state object.
// This prevents the StateInspector from re-rendering infinitely.
export const redirectRelevantStateAtom = selectAtom(
  redirectRelevantStateAtomUnstable,
  (state) => state,
  (a, b) => JSON.stringify(a) === JSON.stringify(b) // Simple but effective equality check for this object
);


// ============================================================================
// DEBUG/DEVELOPMENT ATOMS
// ============================================================================

export interface EventJournalEntry {
  timestamp_epoch: number; // For machine sorting and calculations
  timestamp_iso: string;   // For human readability in logs and debugging
  machine: 'auth' | 'nav' | 'login' | 'system' | 'inspector';
  from: any; // JSON-serializable state value
  to: any;   // JSON-serializable state value
  event: any; // JSON-serializable event
  reason: string;
}

const EVENT_JOURNAL_MAX_LENGTH = 50; // Keep the last 50 transitions.

/**
 * The State Inspector Event Journal.
 * A persistent, session-only atom that stores a capped history of state machine
 * transitions. This serves as our stateful battle journal, surviving page
 * reloads to provide a complete debugging narrative.
 */
/**
 * A private, in-memory-only atom to capture state transitions that occur *before*
 * the main persistent journal has been hydrated from sessionStorage. This prevents
 * the loss of initial events due to the hydration race condition.
 */
const transientEventJournalAtom = atom<EventJournalEntry[]>([]);
const journalUnifiedAtom = atom(false);

/**
 * The State Inspector Event Journal.
 * A persistent, session-only atom that stores a capped history of state machine
 * transitions. This serves as our stateful battle journal, surviving page
 * reloads to provide a complete debugging narrative.
 */
export const eventJournalAtom = atomWithStorage<EventJournalEntry[]>('eventJournal', [], createJSONStorage(() => sessionStorage));

/**
 * A read-only derived atom that provides a unified view of both the persistent
 * and transient journals. The StateInspector should use this to display a
 * complete and chronologically-correct history at all times.
 */
export const combinedJournalViewAtom = atom(get => {
  const persistent = get(eventJournalAtom);
  const transient = get(transientEventJournalAtom);
  const combined = [...persistent, ...transient];
  combined.sort((a, b) => a.timestamp_epoch - b.timestamp_epoch);
  return combined.slice(-EVENT_JOURNAL_MAX_LENGTH);
});

/**
 * Write-only atom for adding entries to the State Inspector Event Journal.
 * It intelligently writes to a transient in-memory journal before the app is
 * unified with persisted state, and to the persistent journal afterwards.
 */
export const addEventJournalEntryAtom = atom(
  null,
  (get, set, entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'>) => {
    const unificationComplete = get(journalUnifiedAtom);
    const now = new Date();
    const newEntry = {
      ...entry,
      timestamp_epoch: now.getTime(),
      timestamp_iso: now.toISOString(),
    };

    if (unificationComplete) {
      const currentJournal = get(eventJournalAtom);
      const newJournal = [...currentJournal, newEntry].slice(-EVENT_JOURNAL_MAX_LENGTH);
      set(eventJournalAtom, newJournal);
    } else {
      set(transientEventJournalAtom, (prev) => [...prev, newEntry]);
    }
  }
);

/**
 * Action atom to be called once on initial client mount to unify the transient
 * and persistent event journals.
 */
export const unifyEventJournalsAtom = atom(
  null,
  (get, set) => {
    // This action is now internal. The trigger is the effect below.
    const isUnified = get(journalUnifiedAtom);
    if (isUnified) return;

    const transientCrumbs = get(transientEventJournalAtom);
    const persistentHistory = get(eventJournalAtom);

    const unifiedJournal = [...persistentHistory, ...transientCrumbs];
    unifiedJournal.sort((a, b) => a.timestamp_epoch - b.timestamp_epoch);

    set(eventJournalAtom, unifiedJournal.slice(-EVENT_JOURNAL_MAX_LENGTH));
    set(transientEventJournalAtom, []);
    set(journalUnifiedAtom, true);
  }
);

/**
 * A single, atomic action to clear the journal and leave a marker.
 * This prevents the race conditions caused by multiple `set` calls in a
 * single event handler.
 */
export const clearAndMarkJournalAtom = atom(
  null,
  (get, set) => {
    set(transientEventJournalAtom, []);
    const now = new Date();
    const markerEntry: EventJournalEntry = {
        machine: 'inspector',
        from: 'system',
        to: 'state',
        event: { type: 'JOURNAL_CLEARED' },
        reason: 'Journal cleared by user action.',
        timestamp_epoch: now.getTime(),
        timestamp_iso: now.toISOString(),
    };
    set(eventJournalAtom, [markerEntry]);
    // Also assert that the journal is now considered unified.
    set(journalUnifiedAtom, true);
  }
);

/**
 * Action atom to be called once on initial client mount to log a page reload event
 * to the journal if one occurred.
 */
export const logReloadToJournalAtom = atom(
  null,
  (get, set) => {
    if (typeof window === 'undefined') return;
    // Check if a reload occurred.
    if (sessionStorage.getItem('statbus_unloading') === 'true') {
      if (get(stateInspectorVisibleAtom)) { // Only log if inspector is active
        const entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'> = {
          machine: 'system',
          from: 'unloaded',
          to: 'loaded',
          event: { type: 'RELOAD' },
          reason: 'Page reloaded or refreshed.'
        };
        set(addEventJournalEntryAtom, entry);
      }
      sessionStorage.removeItem('statbus_unloading');
    }
  }
);

/**
 * An effect that sets a flag in sessionStorage before the page unloads.
 * This allows the app to detect a page refresh on the next load.
 */
export const journalUnificationEffectAtom = atomEffect((get, set) => {
  // This sentinel watches the persistent journal.
  get(eventJournalAtom); // Subscribe to changes.

  const isUnified = get(journalUnifiedAtom);
  const isMounted = get(clientMountedAtom);

  // If the journal is not yet unified AND the app has mounted,
  // it means we are ready for the unification ritual. This effect will
  // fire when eventJournalAtom is hydrated by atomWithStorage, at which
  // point it is safe to unify.
  if (!isUnified && isMounted) {
    set(unifyEventJournalsAtom);
  }
});

export const pageUnloadDetectorEffectAtom = atomEffect((get) => {
  if (typeof window === 'undefined') return;

  const handleBeforeUnload = () => {
    if (get(stateInspectorVisibleAtom)) {
      sessionStorage.setItem('statbus_unloading', 'true');
    }
  };

  window.addEventListener('beforeunload', handleBeforeUnload);
  return () => {
    window.removeEventListener('beforeunload', handleBeforeUnload);
  };
});


export const stateInspectorVisibleAtom = atomWithStorage('stateInspectorVisible', false);
export const stateInspectorExpandedAtom = atomWithStorage('stateInspectorExpanded', false);
export const stateInspectorJournalVisibleAtom = atomWithStorage('stateInspectorJournalVisible', true);
export const stateInspectorStateVisibleAtom = atomWithStorage('stateInspectorStateVisible', true);
export const stateInspectorCanaryExpandedAtom = atomWithStorage('stateInspectorCanaryExpanded', false);
export const stateInspectorAuthStatusExpandedAtom = atomWithStorage('stateInspectorAuthStatusExpanded', false);
export const stateInspectorRefreshExpandedAtom = atomWithStorage('stateInspectorRefreshExpanded', false);

// Dev Tools State
export const isTokenManuallyExpiredAtom = atom(false);

// ============================================================================
// DEBUG HOOKS
// ============================================================================

/**
 * Hook for debugging atom values in development
 */
export const useAtomDebug = (atomName: string, atomValue: any) => {
  useEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      console.log(`[Atom Debug] ${atomName}:`, atomValue)
    }
  }, [atomName, atomValue])
}

export const useDebugInfo = () => {
  const authStatus = useAtomValue(authStatusAtom)
  const baseData = useBaseData()
  const workerStatus = useWorkerStatus()
  const selectedUnits = useAtomValue(selectedUnitsAtom)
  const searchState = useAtomValue(searchStateAtom)
  
  return {
    auth: authStatus,
    baseData: {
      statDefinitionsCount: baseData.statDefinitions.length,
      externalIdentTypesCount: baseData.externalIdentTypes.length,
      statbusUsersCount: baseData.statbusUsers.length,
      timeContextsCount: baseData.timeContexts.length,
      hasDefaultTimeContext: !!baseData.defaultTimeContext,
      hasStatisticalUnits: baseData.hasStatisticalUnits,
    },
    workerStatus,
    selection: {
      count: selectedUnits.length,
      units: selectedUnits,
    },
    search: searchState,
  }
}
