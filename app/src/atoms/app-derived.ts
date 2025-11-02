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
  timeContextsAtom,
  useBaseData,
} from './base-data';
import { numberOfRegionsAtomAsync, settingsAtomAsync } from "./getting-started";
import { restClientAtom } from './rest-client';
import { useWorkerStatus } from './worker_status';
import { selectedUnitsAtom, queryAtom, filtersAtom } from './search';

// Imports from the main app atom file
import {
  selectedTimeContextAtom,
  initialAuthCheckCompletedAtom,
} from './app';

// ============================================================================
// TIME CONTEXT ATOMS & HOOKS - DEPENDENT ON BASE DATA
// ============================================================================

export const defaultTimeContextAtom = selectAtom(baseDataAtom, (data) => data.defaultTimeContext, isEqual);

/**
 * An effect atom that ensures a default time context is selected if none is
 * already set. This is architecturally superior to placing this logic in a
 * hook, as it decouples the side effect from component render cycles.
 */
export const timeContextAutoSelectEffectAtom = atomEffect((get, set) => {
  const selected = get(selectedTimeContextAtom);
  const defaultTC = get(defaultTimeContextAtom);
  if (!selected && defaultTC) {
    set(selectedTimeContextAtom, defaultTC);
  }
});

export const useTimeContext = () => {
  const [selectedTimeContext, setSelectedTimeContext] = useAtom(selectedTimeContextAtom);
  const timeContexts = useAtomValue(timeContextsAtom);
  const defaultTimeContext = useAtomValue(defaultTimeContextAtom);
  
  return {
    selectedTimeContext,
    setSelectedTimeContext,
    timeContexts,
    defaultTimeContext,
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
      timeContextsCount: baseData.timeContexts.length,
      hasDefaultTimeContext: !!baseData.defaultTimeContext,
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
