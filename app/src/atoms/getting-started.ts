"use client";

/**
 * Getting Started Atoms and Hooks
 *
 * This file contains atoms and hooks related to the "Getting Started"
 * dashboard/wizard, including UI state and data fetching for initial setup metrics.
 */

import { atom, useAtom } from 'jotai'
import { atomWithStorage, atomWithRefresh } from 'jotai/utils'

import { restClientAtom } from './app'
import { isAuthenticatedAtom } from './auth'

// ============================================================================
// GETTING STARTED ATOMS - Replace GettingStartedContext
// ============================================================================

// UI State for the Getting Started Wizard
export interface GettingStartedUIState {
  currentStep: number
  completedSteps: number[]
  isVisible: boolean
}

export const gettingStartedUIStateAtom = atomWithStorage<GettingStartedUIState>(
  'gettingStarted',
  {
    currentStep: 0,
    completedSteps: [],
    isVisible: true,
  }
)

// --- Individual Async Atoms for "Getting Started" Metrics ---

// Activity Category Standard Setting
export const activityCategoryStandardSettingAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { data: settings, error } = await client
    .from("settings")
    .select("activity_category_standard(id,name)")
    .limit(1);
  if (error) {
    console.error('Failed to fetch activity_category_standard setting:', error);
    return null;
  }
  return settings?.[0]?.activity_category_standard as { id: number, name: string } ?? null;
});

// Number of Regions
export const numberOfRegionsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("region").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of regions:', error);
    return null;
  }
  return count;
});

// Number of Custom Activity Category Codes
export const numberOfCustomActivityCodesAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("activity_category_available_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom activity codes:', error);
    return null;
  }
  return count;
});

// Number of Custom Sectors
export const numberOfCustomSectorsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("sector_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom sectors:', error);
    return null;
  }
  return count;
});

// Number of Custom Legal Forms
export const numberOfCustomLegalFormsAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("legal_form_custom").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of custom legal forms:', error);
    return null;
  }
  return count;
});

// Number of Total Activity Category Codes (available)
export const numberOfTotalActivityCodesAtomAsync = atomWithRefresh(async (get) => {
  const isAuthenticated = get(isAuthenticatedAtom);
  if (!isAuthenticated) return null;

  const client = get(restClientAtom);
  if (!client) return null;
  const { count, error } = await client.from("activity_category_available").select("*", { count: "exact", head: true });
  if (error) {
    console.error('Failed to fetch number of total activity codes:', error);
    return null;
  }
  return count;
});

// ============================================================================
// GETTING STARTED HOOKS
// ============================================================================

// A simple hook to manage the UI state of the wizard.
// The data-fetching atoms are intended to be used directly by components.
export const useGettingStartedUI = () => {
  const [uiState, setUiState] = useAtom(gettingStartedUIStateAtom);

  const goToStep = (step: number) => {
    setUiState(prev => ({ ...prev, currentStep: step }));
  };

  const completeStep = (step: number) => {
    setUiState(prev => ({
      ...prev,
      completedSteps: [...new Set([...prev.completedSteps, step])]
    }));
  };

  const setVisibility = (isVisible: boolean) => {
    setUiState(prev => ({ ...prev, isVisible }));
  };

  return {
    ...uiState,
    goToStep,
    completeStep,
    setVisibility,
  };
};
