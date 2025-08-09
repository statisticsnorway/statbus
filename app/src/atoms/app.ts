"use client";

/**
 * General Application State Atoms and Hooks
 *
 * This file contains atoms and hooks for managing high-level application state,
 * such as the REST client instance, time context, initialization status, and readiness.
 */

import { atom } from 'jotai'
import { atomWithStorage } from 'jotai/utils'
import { useAtom, useAtomValue, useSetAtom } from 'jotai'
import { useEffect } from 'react'

import type { Database, Tables } from '@/lib/database.types'
import type { PostgrestClient } from '@supabase/postgrest-js'

import { authStatusLoadableAtom, isAuthenticatedAtom, authStatusAtom } from './auth'
import { baseDataAtom, baseDataLoadableAtom, defaultTimeContextAtom, timeContextsAtom, refreshBaseDataAtom, useBaseData } from './base-data'
import { refreshWorkerStatusAtom, useWorkerStatus, type WorkerStatusType } from './worker_status'
import { selectedUnitsAtom, searchStateAtom } from './search'

// ============================================================================
// REST CLIENT ATOM - Replace RestClientStore
// ============================================================================

export const restClientAtom = atom<PostgrestClient<Database> | null>(null)

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

// Combined authentication and base data status
export const appReadyAtom = atom((get) => {
  const authLoadable = get(authStatusLoadableAtom);
  const baseDataLoadable = get(baseDataLoadableAtom);
  const baseD = get(baseDataAtom);

  const isLoadingBaseD = baseDataLoadable.state === 'loading';
  const isAuthLoading = authLoadable.state === 'loading';
  
  // If auth is not loading, its "process" is complete for readiness purposes.
  const isAuthProcessComplete = !isAuthLoading; 
  const isAuthenticatedUser = authLoadable.state === 'hasData' && authLoadable.data.isAuthenticated;
  const currentUser = authLoadable.state === 'hasData' ? authLoadable.data.user : null;

  // Base data is considered ready if not loading and has essential data (e.g., stat definitions).
  const isBaseDataProcessComplete = !isLoadingBaseD && baseD.statDefinitions.length > 0;

  // The dashboard is ready to render if auth is complete and base data is loaded.
  const isReadyToRenderDashboard = 
    isAuthProcessComplete &&
    isAuthenticatedUser &&
    isBaseDataProcessComplete;
    
  // isSetupComplete is removed from this global atom. 
  // If a global "is the very basic setup done (e.g. units exist)" flag is needed,
  // it could be derived from baseDataAtom.hasStatisticalUnits, but it won't gate the dashboard rendering here.

  return {
    isLoadingAuth: isAuthLoading,
    isLoadingBaseData: isLoadingBaseD,

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

/**
 * Hook to initialize the app state when component mounts
 * This replaces the complex useEffect chains in your Context providers
 */
export const useAppInitialization = () => {
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  const refreshWorkerStatus = useSetAtom(refreshWorkerStatusAtom)
  const isAuthenticated = useAtomValue(isAuthenticatedAtom)
  const client = useAtomValue(restClientAtom) // Get the REST client state, renamed to avoid conflict
  
  useEffect(() => {
    let mounted = true
    
    const initializeApp = async () => {
      // Ensure both authentication is true and REST client is available
      if (!isAuthenticated) {
        // console.log("useAppInitialization: Not authenticated, skipping data initialization.");
        return;
      }
      if (!client) {
        // console.log("useAppInitialization: REST client not yet available, deferring data initialization.");
        return;
      }
      
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log("useAppInitialization: Authenticated and REST client ready, proceeding.");
      }
      try {
        // Initialize base data
        await refreshBaseData()
        
        // Initialize worker status
        await refreshWorkerStatus()
        
      } catch (error) {
        if (mounted) {
          console.error('App initialization failed:', error)
        }
      }
    }
    
    initializeApp()
    
    return () => {
      mounted = false
    }
  }, [isAuthenticated, client, refreshBaseData, refreshWorkerStatus]) // Add client to dependency array
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
