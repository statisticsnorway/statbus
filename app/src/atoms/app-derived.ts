"use client";

/**
 * Derived Application State Atoms
 *
 * This file contains atoms that are derived from other core state atoms,
 * particularly those that depend on both app-level state (like auth) and
 * base data. Separating them here helps prevent circular dependency issues.
 */

import { atom } from 'jotai';
import { loadable, selectAtom } from 'jotai/utils';
import { useAtom, useAtomValue } from 'jotai';
import { atomEffect } from 'jotai-effect';
import { isEqual } from 'moderndash';

// Imports from other atom files
import {
  isAuthenticatedStrictAtom,
  authStatusAtom,
  authStatusUnstableDetailsAtom,
  isUserConsideredAuthenticatedForUIAtom,
} from './auth';
import {
  baseDataAtom,
  timeFramesAtom,
  useBaseData,
} from './base-data';
import { numberOfRegionsAtomAsync, settingsAtomAsync } from "./getting-started";
import { restClientAtom } from './rest-client';
import { useWorkerStatus } from './worker_status';
import { selectedUnitsAtom, queryAtom, filtersAtom } from './search';

// Imports from the main app atom file
import {
  selectedTimeFrameAtom,
  initialAuthCheckCompletedAtom,
} from './app';

// ============================================================================
// TIME FRAME ATOMS & HOOKS - DEPENDENT ON BASE DATA
// ============================================================================

export const defaultTimeFrameAtom = selectAtom(baseDataAtom, (data) => data.defaultTimeFrame, isEqual);

/**
 * Keeps a valid time frame selected (public.time_frame, lib/time-frame.ts).
 *
 * The selection is remembered by ident. live and prev keep their ident as the
 * calendar moves while their period and valid_on change (valid_on of the live
 * frame is today), so the stored row is replaced by the current row with the
 * same ident. A selection whose ident no longer exists (a retired frame from an
 * older version) falls back to the default frame, the live frame.
 */
export const timeFrameAutoSelectEffectAtom = atomEffect((get, set) => {
  const selected = get(selectedTimeFrameAtom);
  const timeFrames = get(timeFramesAtom);
  const defaultFrame = get(defaultTimeFrameAtom);

  if (!selected) {
    if (defaultFrame) set(selectedTimeFrameAtom, defaultFrame);
    return;
  }

  if (timeFrames.length > 0) {
    const current = timeFrames.find((tf) => tf.ident === selected.ident);
    if (!current) {
      if (defaultFrame) set(selectedTimeFrameAtom, defaultFrame);
    } else if (!isEqual(current, selected)) {
      set(selectedTimeFrameAtom, current);
    }
  }
});

export const useTimeFrame = () => {
  const [selectedTimeFrame, setSelectedTimeFrame] = useAtom(selectedTimeFrameAtom);
  const timeFrames = useAtomValue(timeFramesAtom);
  const defaultTimeFrame = useAtomValue(defaultTimeFrameAtom);

  return {
    selectedTimeFrame,
    setSelectedTimeFrame,
    timeFrames,
    defaultTimeFrame,
  };
};

// ============================================================================
// APP INITIALIZATION & REDIRECT LOGIC - DEPENDENT ON BASE DATA
// ============================================================================

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
  const settingsLoadable = get(loadable(settingsAtomAsync));
  const numberOfRegionsLoadable = get(loadable(numberOfRegionsAtomAsync));
  const baseData = get(baseDataAtom);

  const isLoading =
    settingsLoadable.state === "loading" ||
    numberOfRegionsLoadable.state === "loading" ||
    baseData.loading;

  if (isLoading) {
    return { path: null, isLoading: true };
  }

  // At this point, all data is loaded and stable.
  const currentSettings =
    settingsLoadable.state === "hasData" ? settingsLoadable.data : null;
  const currentNumberOfRegions =
    numberOfRegionsLoadable.state === "hasData"
      ? numberOfRegionsLoadable.data
      : null;

  let path: string | null = null;

  if (currentSettings === null) {
    path = "/getting-started";
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

  // BATTLE WISDOM: The UI-level "auth is loading" signal should only be true
  // during the very initial application load. Background activities like token
  // refreshes or re-validations should not cause the entire UI to flash a
  // loading screen. `initialAuthCheckCompletedAtom` provides this stable signal.
  const isAuthLoading = !get(initialAuthCheckCompletedAtom);
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
  return useAtomValue(appReadyAtom);
};

const redirectRelevantStateAtomUnstable = atom((get) => {
  const authStatus = get(authStatusUnstableDetailsAtom);
  const baseData = get(baseDataAtom);
  const settingsLoadable = get(loadable(settingsAtomAsync));
  const numberOfRegionsLoadable = get(loadable(numberOfRegionsAtomAsync));
  const restClient = get(restClientAtom);

  const baseDataState = baseData.loading ? 'loading' : baseData.error ? 'hasError' : 'hasData';
  
  return {
    initialAuthCheckCompleted: get(initialAuthCheckCompletedAtom),
    authCheckDone: !authStatus.loading,
    isRestClientReady: !!restClient,
    settings:
      settingsLoadable.state === "hasData" ? settingsLoadable.data : null,
    numberOfRegions:
      numberOfRegionsLoadable.state === "hasData"
        ? numberOfRegionsLoadable.data
        : null,
    baseDataHasStatisticalUnits:
      baseDataState === "hasData"
        ? baseData.hasStatisticalUnits
        : "BaseDataNotLoaded",
    baseDataStatDefinitionsLength:
      baseDataState === "hasData"
        ? baseData.statDefinitions.length
        : "BaseDataNotLoaded",
  };
});

// Create a memoized/stabilized version of the state object.
// This prevents the DebugInspector from re-rendering infinitely.
export const redirectRelevantStateAtom = selectAtom(
  redirectRelevantStateAtomUnstable,
  (state) => state,
  (a, b) => JSON.stringify(a) === JSON.stringify(b) // Simple but effective equality check for this object
);

// ============================================================================
// DEBUG HOOKS
// ============================================================================

export const useDebugInfo = () => {
  const authStatus = useAtomValue(authStatusAtom);
  const baseData = useBaseData();
  const workerStatus = useWorkerStatus();
  const selectedUnits = useAtomValue(selectedUnitsAtom);
  const query = useAtomValue(queryAtom);
  const filters = useAtomValue(filtersAtom);
  
  return {
    auth: authStatus,
    baseData: {
      statDefinitionsCount: baseData.statDefinitions.length,
      externalIdentTypesCount: baseData.externalIdentTypes.length,
      statbusUsersCount: baseData.statbusUsers.length,
      timeFramesCount: baseData.timeFrames.length,
      hasDefaultTimeFrame: !!baseData.defaultTimeFrame,
      hasStatisticalUnits: baseData.hasStatisticalUnits,
    },
    workerStatus,
    selection: {
      count: selectedUnits.length,
      units: selectedUnits,
    },
    search: { query, filters },
  };
};
