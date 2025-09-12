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
import { useGuardedEffect } from '@/hooks/use-guarded-effect'
import { atomEffect } from 'jotai-effect'

import type { Tables } from '@/lib/database.types'

import { isAuthenticatedStrictAtom, authStatusAtom, authStatusUnstableDetailsAtom, isUserConsideredAuthenticatedForUIAtom } from './auth'
import { activityCategoryStandardSettingAtomAsync, numberOfRegionsAtomAsync } from './getting-started'
import { refreshWorkerStatusAtom, useWorkerStatus, type WorkerStatusType } from './worker_status'
import { restClientAtom } from './rest-client'
import { selectedUnitsAtom, queryAtom, filtersAtom } from './search'
import { selectAtom } from 'jotai/utils'
import { isEqual } from 'moderndash'

// ============================================================================
// TIME CONTEXT ATOMS & HOOKS - Replace TimeContext
// ============================================================================

// Persistent selected time context
export const selectedTimeContextAtom = atomWithStorage<Tables<"time_context"> | null>(
  'selectedTimeContext',
  null
)

// NOTE: defaultTimeContextAtom, timeContextAutoSelectEffectAtom, and useTimeContext
// have been moved to app-derived.ts to break a circular dependency.

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

// NOTE: setupRedirectCheckAtom, appReadyAtom, useAppReady, and redirectRelevantStateAtom
// have been moved to app-derived.ts to break a circular dependency.


// ============================================================================
// DEBUG/DEVELOPMENT ATOMS
// ============================================================================

export enum MachineID {
  Auth = 'auth',
  Navigation = 'navigation',
  LoginUI = 'loginUi',
  System = 'system',
  Inspector = 'inspector',
}

export interface EventJournalEntry {
  timestamp_epoch: number; // For machine sorting and calculations
  timestamp_iso: string;   // For human readability in logs and debugging
  machine: MachineID;
  from: any; // JSON-serializable state value
  to: any;   // JSON-serializable state value
  event: any; // JSON-serializable event
  reason: string;
}

const EVENT_JOURNAL_MAX_LENGTH = 50; // Keep the last 50 transitions.

/**
 * A dedicated atom to hold a snapshot of the event journal, saved immediately
 * before a programmatic redirect. This solves the diagnostic race condition where
 * redirect events would be lost because the page unloads before the inspector's
 * UI can update.
 */
export const preRedirectJournalSnapshotAtom = atomWithStorage<EventJournalEntry[] | null>(
  'preRedirectJournalSnapshot',
  null,
  createJSONStorage(() => sessionStorage)
);

/**
 * Write-only atom to command the saving of the current journal state to the
 * pre-redirect snapshot storage. This is triggered by the NavigationManager.
 */
export const saveJournalSnapshotAtom = atom(
  null,
  (get, set) => {
    const currentJournal = get(combinedJournalViewAtom);
    set(preRedirectJournalSnapshotAtom, currentJournal);
  }
);

/**
 * The Debug Inspector Event Journal.
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
 * and transient journals. The DebugInspector should use this to display a
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
 * Write-only atom for adding entries to the Debug Inspector Event Journal.
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
    const preRedirectSnapshot = get(preRedirectJournalSnapshotAtom);

    let journalToUnify = persistentHistory;

    // If a snapshot from a previous page exists, it is the most complete history.
    // We use it as the base and clear it.
    if (preRedirectSnapshot) {
      journalToUnify = preRedirectSnapshot;
      set(preRedirectJournalSnapshotAtom, null);
    }

    const unifiedJournal = [...journalToUnify, ...transientCrumbs];
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
        machine: MachineID.Inspector,
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
      if (get(debugInspectorVisibleAtom)) { // Only log if inspector is active
        const entry: Omit<EventJournalEntry, 'timestamp_epoch' | 'timestamp_iso'> = {
          machine: MachineID.System,
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
    if (get(debugInspectorVisibleAtom)) {
      sessionStorage.setItem('statbus_unloading', 'true');
    }
  };

  window.addEventListener('beforeunload', handleBeforeUnload);
  return () => {
    window.removeEventListener('beforeunload', handleBeforeUnload);
  };
});


export const debugInspectorVisibleAtom = atomWithStorage('debugInspectorVisible', false);
export const debugInspectorExpandedAtom = atomWithStorage('debugInspectorExpanded', false);
export const debugInspectorJournalVisibleAtom = atomWithStorage('debugInspectorJournalVisible', true);
export const debugInspectorStateVisibleAtom = atomWithStorage('debugInspectorStateVisible', true);
export const debugInspectorApiLogExpandedAtom = atomWithStorage('debugInspectorApiLogExpanded', false);
export const debugInspectorEffectJournalVisibleAtom = atomWithStorage('debugInspectorEffectJournalVisible', false);
export const debugInspectorMountJournalVisibleAtom = atomWithStorage('debugInspectorMountJournalVisible', false);

// ============================================================================
// DEBUG HOOKS
// ============================================================================

/**
 * Hook for debugging atom values in development
 */
export const useAtomDebug = (atomName: string, atomValue: any) => {
  useGuardedEffect(() => {
    if (process.env.NODE_ENV === 'development') {
      console.log(`[Atom Debug] ${atomName}:`, atomValue)
    }
  }, [atomName, atomValue], `app.ts:useAtomDebug:${atomName}`)
}

// NOTE: useDebugInfo has been moved to app-derived.ts to break a circular dependency.
