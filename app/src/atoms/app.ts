"use client";

/**
 * General Application State Atoms and Hooks
 *
 * This file contains atoms and hooks for managing high-level application state,
 * such as the REST client instance, time context, initialization status, and readiness.
 */

import { atom } from 'jotai'
import { atomWithStorage, loadable } from 'jotai/utils'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useEffect } from 'react'

import type { Tables } from '@/lib/database.types'

import { authStatusLoadableAtom, isAuthenticatedAtom, authStatusAtom } from './auth'
import { baseDataAtom, defaultTimeContextAtom, timeContextsAtom, refreshBaseDataAtom, useBaseData } from './base-data'
import { activityCategoryStandardSettingAtomAsync, numberOfRegionsAtomAsync } from './getting-started'
import { refreshWorkerStatusAtom, useWorkerStatus, type WorkerStatusType } from './worker_status'
import { selectedUnitsAtom, searchStateAtom } from './search'

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

// Atom for programmatic redirects
export const pendingRedirectAtom = atom<string | null>(null);

// Atom to signal a redirect required by application setup state (e.g., missing regions)
export const requiredSetupRedirectAtom = atom<string | null>(null);

// Atom to track if the initial auth check has completed successfully. This is used
// by RedirectGuard to prevent premature redirects during app startup or auth flaps.
export const initialAuthCheckCompletedAtom = atom(false);

// Atom to calculate the required setup redirect path, if any.
// It also exposes a loading state so consumers can wait for the check to complete.
export const setupRedirectCheckAtom = atom((get) => {
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
  const authLoadable = get(authStatusLoadableAtom);
  const baseData = get(baseDataAtom);

  const isAuthLoading = authLoadable.state === 'loading';
  const isLoadingBaseData = baseData.loading;

  const isAuthProcessComplete = !isAuthLoading;
  // Use the stabilized isAuthenticatedAtom for readiness checks. This makes the app's
  // concept of "readiness" resilient to transient auth-state flaps.
  const isAuthenticatedUser = get(isAuthenticatedAtom);
  const currentUser = authLoadable.state === 'hasData' ? authLoadable.data.user : null;

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

// ============================================================================
// DEBUG/DEVELOPMENT ATOMS
// ============================================================================

export const stateInspectorVisibleAtom = atomWithStorage('stateInspectorVisible', false);

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
