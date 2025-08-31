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

// Atom to calculate the required setup redirect path, if any.
// It also exposes a loading state so consumers can wait for the check to complete.
export const setupRedirectCheckAtom = atom((get) => {
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
export const eventJournalAtom = atomWithStorage<EventJournalEntry[]>('eventJournal', [], createJSONStorage(() => sessionStorage));

/**
 * Write-only atom for adding entries to the State Inspector Event Journal.
 * It automatically adds timestamps and enforces the maximum log length.
 */
export const addEventJournalEntryAtom = atom(
  null,
  (get, set, entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'>) => {
    // This action is only performed if the inspector is visible, so we don't
    // need to check the visibility flag here again.
    const now = new Date();
    const newEntry = {
      ...entry,
      timestamp_epoch: now.getTime(),
      timestamp_iso: now.toISOString(),
    };
    const currentJournal = get(eventJournalAtom);
    const newJournal = [...currentJournal, newEntry].slice(-EVENT_JOURNAL_MAX_LENGTH);
    set(eventJournalAtom, newJournal);
  }
);

/**
 * An effect that detects page reloads and logs them to the State Inspector Event Journal.
 * It uses sessionStorage to persist a flag across a reload.
 */
export const reloadEventJournalLoggerEffectAtom = atomEffect((_get, set) => {
  // This effect runs only on the client.
  if (typeof window === 'undefined') return;

  const get = _get; // Rename for clarity inside the effect

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
      console.log(`[Scribe:System]`, entry.reason);
    }
    sessionStorage.removeItem('statbus_unloading');
  }

  // Set up the listener for the next unload.
  const handleBeforeUnload = () => {
    // Only set the flag if the inspector is visible, to avoid unnecessary writes.
    if (get(stateInspectorVisibleAtom)) {
      sessionStorage.setItem('statbus_unloading', 'true');
    }
  };

  window.addEventListener('beforeunload', handleBeforeUnload);

  // Return a cleanup function to remove the listener.
  return () => {
    window.removeEventListener('beforeunload', handleBeforeUnload);
  };
});


export const stateInspectorVisibleAtom = atomWithStorage('stateInspectorVisible', false);
export const stateInspectorExpandedAtom = atomWithStorage('stateInspectorExpanded', false);

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
