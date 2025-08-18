"use client";

/**
 * Base Data Atoms and Hooks
 *
 * This file contains atoms and hooks for fetching and managing fundamental
 * application data that is relatively static and used across many features,
 * such as statistical definitions, external identifier types, and time contexts.
 */

import { atom } from 'jotai'
import { loadable } from 'jotai/utils'
import { useAtomValue, useSetAtom } from 'jotai'
import { atomWithRefresh } from 'jotai/utils'
import { useCallback } from 'react'

import type { Database, Tables } from '@/lib/database.types'
import { restClientAtom } from './app'
import { isAuthenticatedAtom } from './auth'

// ============================================================================
// BASE DATA ATOMS - Replace BaseDataStore + BaseDataContext
// ============================================================================

export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[]
  externalIdentTypes: Tables<"external_ident_type_active">[]
  statbusUsers: Tables<"user">[]
  timeContexts: Tables<"time_context">[]
  defaultTimeContext: Tables<"time_context"> | null
  hasStatisticalUnits: boolean
}

const initialBaseData: BaseData = {
  statDefinitions: [],
  externalIdentTypes: [],
  statbusUsers: [],
  timeContexts: [],
  defaultTimeContext: null,
  hasStatisticalUnits: false,
};

// Explicitly type the return of the async function for atomWithRefresh
export const baseDataCoreAtom = atomWithRefresh<Promise<BaseData>>(async (get): Promise<BaseData> => {
  const isAuthenticated = get(isAuthenticatedAtom);
  const client = get(restClientAtom);

  if (!isAuthenticated) return initialBaseData;

  if (!client) {
    if (typeof window !== 'undefined') {
      // Client-side, authenticated, but client is not ready. Return a promise that never resolves.
      return new Promise<BaseData>(() => {}); // Cast to expected Promise type
    }
    // Server-side, client not ready, or unauthenticated.
    return initialBaseData;
  }

  try {
    const [
      statDefinitionsResult,
      externalIdentTypesResult,
      statbusUsersResult,
      statisticalUnitResult,
      timeContextsResult
    ] = await Promise.all([
      client.from("stat_definition_active").select(),
      client.from("external_ident_type_active").select(),
      client.from("user").select(), // Consider if all users are needed or just current user's info
      client.from("statistical_unit").select("*", { count: "exact", head: true }), // Check existence efficiently
      client.from("time_context").select("*") // Fetches all, view is ordered by default
    ]);

    if (statDefinitionsResult.error) console.error('Error fetching stat definitions:', statDefinitionsResult.error);
    if (externalIdentTypesResult.error) console.error('Error fetching external ident types:', externalIdentTypesResult.error);
    if (statbusUsersResult.error) console.error('Error fetching statbus users:', statbusUsersResult.error);
    if (statisticalUnitResult.error) console.error('Error checking for statistical units:', statisticalUnitResult.error); // This error might still occur if other issues arise, but the query itself is fixed.
    if (timeContextsResult.error) console.error('Error fetching time contexts:', timeContextsResult.error);
    
    let defaultTimeContext: Tables<"time_context"> | null = null;
    if (timeContextsResult.data && timeContextsResult.data.length > 0) {
      // The time_context view is pre-ordered by priority, then valid_on descending.
      // The first one is the default.
      defaultTimeContext = timeContextsResult.data[0] as Tables<"time_context">;
    }

    return {
      statDefinitions: statDefinitionsResult.data || [],
      externalIdentTypes: externalIdentTypesResult.data || [],
      statbusUsers: statbusUsersResult.data || [],
      timeContexts: timeContextsResult.data || [],
      defaultTimeContext: defaultTimeContext,
      hasStatisticalUnits: !!statisticalUnitResult.count && statisticalUnitResult.count > 0,
    };
  } catch (error) {
    console.error("baseDataCoreAtom: Failed to fetch base data:", error);
    return initialBaseData;
  }
});

export const baseDataLoadableAtom = loadable(baseDataCoreAtom);

// Add a module-level variable to hold the last stable value.
// This is a pragmatic approach for client-side state to ensure object reference stability.
let lastStableBaseData: (BaseData & { loading: boolean; error: string | null }) | null = null;

/**
 * Performs a "good enough" deep comparison of two BaseData objects to check for meaningful changes.
 * It avoids full recursive comparison by creating a compound key from the array contents.
 */
function isBaseDataEqual(a: BaseData, b: BaseData): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.hasStatisticalUnits !== b.hasStatisticalUnits) return false;
  if (a.defaultTimeContext?.ident !== b.defaultTimeContext?.ident) return false;

  // Create a key from an array of objects using their primary identifiers.
  // This is more efficient than a full deep equal and robust enough for this data.
  const idKey = (arr: any[]) => arr.map((item) => item?.id ?? item?.code ?? item?.ident ?? JSON.stringify(item)).join(',');

  if (idKey(a.statDefinitions) !== idKey(b.statDefinitions)) return false;
  if (idKey(a.externalIdentTypes) !== idKey(b.externalIdentTypes)) return false;
  if (idKey(a.statbusUsers) !== idKey(b.statbusUsers)) return false;
  if (idKey(a.timeContexts) !== idKey(b.timeContexts)) return false;

  return true;
}


export const baseDataAtom = atom<BaseData & { loading: boolean; error: string | null }>(
  (get): BaseData & { loading: boolean; error: string | null } => {
    const loadableState = get(baseDataLoadableAtom);
    let result: BaseData & { loading: boolean; error: string | null };

    switch (loadableState.state) {
      case 'loading':
        // While loading, use the previous data if available (loadable provides this).
        // Fallback to initialBaseData if there's no previous data.
        const dataWhileLoading = ((loadableState as { data?: BaseData }).data) ?? initialBaseData;
        result = { ...dataWhileLoading, loading: true, error: null };
        break;
      case 'hasError':
        const error = loadableState.error;
        result = { ...initialBaseData, loading: false, error: error instanceof Error ? error.message : String(error) };
        break;
      case 'hasData':
        result = { ...loadableState.data, loading: false, error: null };
        break;
      default: // Should not happen with loadable
        result = { ...initialBaseData, loading: false, error: 'Unknown loadable state' };
    }
    
    // If the new result is meaningfully the same as the last one, return the last one
    // to preserve object reference and prevent unnecessary re-renders.
    if (lastStableBaseData &&
        lastStableBaseData.loading === result.loading &&
        lastStableBaseData.error === result.error &&
        isBaseDataEqual(lastStableBaseData, result)
    ) {
        return lastStableBaseData;
    }

    lastStableBaseData = result;
    return result;
  }
);

// Derived atoms for individual data pieces
export const statDefinitionsAtom = atom((get) => get(baseDataAtom).statDefinitions)
export const externalIdentTypesAtom = atom((get) => get(baseDataAtom).externalIdentTypes)
export const statbusUsersAtom = atom((get) => get(baseDataAtom).statbusUsers)
export const timeContextsAtom = atom((get) => get(baseDataAtom).timeContexts)
export const defaultTimeContextAtom = atom((get) => get(baseDataAtom).defaultTimeContext)
export const hasStatisticalUnitsAtom = atom((get) => get(baseDataAtom).hasStatisticalUnits)

// Action to refresh base data
export const refreshBaseDataAtom = atom(null, (_get, set) => { // get is not used
  set(baseDataCoreAtom);
});

// ============================================================================
// BASE DATA HOOKS - Replace BaseDataClient patterns
// ============================================================================

export const useBaseData = () => {
  const baseData = useAtomValue(baseDataAtom)
  const refreshBaseData = useSetAtom(refreshBaseDataAtom)
  
  return {
    ...baseData,
    refreshBaseData: useCallback(async () => {
      try {
        await refreshBaseData()
      } catch (error) {
        console.error('Failed to refresh base data:', error)
        throw error
      }
    }, [refreshBaseData]),
  }
}
