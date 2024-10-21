"use client";
import React, { createContext, useContext, useState, useEffect, useCallback, useRef } from 'react';
import { createSupabaseBrowserClientAsync } from "@/utils/supabase/client";
import { SupabaseClient } from '@supabase/supabase-js';

interface GettingStartedState {
  activity_category_standard: { id: number, name: string } | null;
  numberOfRegions: number | null;
  numberOfLegalUnits: number | null;
  numberOfEstablishments: number | null;
  numberOfCustomActivityCategoryCodes: number | null;
  numberOfCustomSectors: number | null;
  numberOfCustomLegalForms: number | null;
  numberOfStatisticalUnits: number | null;
}

interface GettingStartedContextType extends GettingStartedState {
  refreshCounts: () => Promise<void>;
  refreshNumberOfRegions: () => Promise<void>;
  refreshNumberOfLegalUnits: () => Promise<void>;
  refreshNumberOfEstablishments: () => Promise<void>;
  refreshNumberOfCustomActivityCategoryCodes: () => Promise<void>;
  refreshNumberOfCustomSectors: () => Promise<void>;
  refreshNumberOfCustomLegalForms: () => Promise<void>;
  refreshNumberOfStatisticalUnits: () => Promise<void>;
}

const GettingStartedContext = createContext<GettingStartedContextType | undefined>(undefined);

export const GettingStartedProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, setState] = useState<GettingStartedState>({
    activity_category_standard: null,
    numberOfRegions: null,
    numberOfLegalUnits: null,
    numberOfEstablishments: null,
    numberOfCustomActivityCategoryCodes: null,
    numberOfCustomSectors: null,
    numberOfCustomLegalForms: null,
    numberOfStatisticalUnits: null,
  });

  const [client, setClient] = useState<SupabaseClient | null>(null);

  const refreshActivityCategoryStandard = useCallback(async () => {
    if (!client) return;

    const { data: settings } = await client
      .from("settings")
      .select("activity_category_standard(id,name)")
      .limit(1);
    const activity_category_standard = settings?.[0]?.activity_category_standard as any as { id: number, name: string };
    setState((prevState) => ({
      ...prevState,
      activity_category_standard,
    }));
  }, [client]);

  const refreshNumberOfRegions = useCallback(async () => {
    if (!client) return;

    const { count: numberOfRegions } = await client.from("region").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfRegions,
    }));
  }, [client]);

  const refreshNumberOfLegalUnits = useCallback(async () => {
    if (!client) return;

    const { count: numberOfLegalUnits } = await client.from("legal_unit").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfLegalUnits,
    }));
  }, [client]);

  const refreshNumberOfEstablishments = useCallback(async () => {
    if (!client) return;

    const { count: numberOfEstablishments } = await client.from("establishment").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfEstablishments,
    }));
  }, [client]);

  const refreshNumberOfCustomActivityCategoryCodes = useCallback(async () => {
    if (!client) return;

    const { count: numberOfCustomActivityCategoryCodes } = await client.from("activity_category_available_custom").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfCustomActivityCategoryCodes,
    }));
  }, [client]);

  const refreshNumberOfCustomSectors = useCallback(async () => {
    if (!client) return;

    const { count: numberOfCustomSectors } = await client.from("sector_custom").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfCustomSectors,
    }));
  }, [client]);

  const refreshNumberOfCustomLegalForms = useCallback(async () => {
    if (!client) return;

    const { count: numberOfCustomLegalForms } = await client.from("legal_form_custom").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfCustomLegalForms,
    }));
  }, [client]);

  const refreshNumberOfStatisticalUnits = useCallback(async () => {
    if (!client) return;

    const { count: numberOfStatisticalUnits } = await client.from("statistical_unit").select("*", { count: "exact" }).limit(0);

    setState((prevState) => ({
      ...prevState,
      numberOfStatisticalUnits,
    }));
  }, [client]);

  const refreshCounts = useCallback(async () => {
    await refreshActivityCategoryStandard();
    await refreshNumberOfRegions();
    await refreshNumberOfLegalUnits();
    await refreshNumberOfEstablishments();
    await refreshNumberOfCustomActivityCategoryCodes();
    await refreshNumberOfCustomSectors();
    await refreshNumberOfCustomLegalForms();
    await refreshNumberOfStatisticalUnits();
  }, [
    refreshActivityCategoryStandard,
    refreshNumberOfCustomActivityCategoryCodes,
    refreshNumberOfCustomLegalForms,
    refreshNumberOfCustomSectors,
    refreshNumberOfEstablishments,
    refreshNumberOfLegalUnits,
    refreshNumberOfRegions,
    refreshNumberOfStatisticalUnits,
  ]);

  useEffect(() => {
    const initializeClient = async () => {
      const supabaseClient = await createSupabaseBrowserClientAsync();
      setClient(supabaseClient);
    };
    initializeClient();
  }, []);

  useEffect(() => {
    if (client) {
      refreshCounts();
    }
  }, [client, refreshCounts]);

  return (
    <GettingStartedContext.Provider
      value={{
        ...state,
        refreshCounts,
        refreshNumberOfRegions,
        refreshNumberOfLegalUnits,
        refreshNumberOfEstablishments,
        refreshNumberOfCustomActivityCategoryCodes,
        refreshNumberOfCustomSectors,
        refreshNumberOfCustomLegalForms,
        refreshNumberOfStatisticalUnits,
      }}
    >
      {children}
    </GettingStartedContext.Provider>
  );
};

export const useGettingStarted = () => {
  const context = useContext(GettingStartedContext);
  if (!context) {
    throw new Error("useGettingStarted must be used within a GettingStartedProvider");
  }
  return context;
};

