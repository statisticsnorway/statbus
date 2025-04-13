"use client";
import React, { createContext, useContext, useState, useEffect, useCallback } from 'react';
import { getBrowserClient } from "@/context/ClientStore";
import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { isAuthenticated } from '@/utils/auth/auth-utils';

// Define StatbusClient type locally
type StatbusClient = PostgrestClient<Database>;

interface GettingStartedState {
  activity_category_standard: { id: number, name: string } | null;
  numberOfRegions: number | null;
  numberOfCustomActivityCategoryCodes: number | null;
  numberOfCustomSectors: number | null;
  numberOfCustomLegalForms: number | null;
}

interface GettingStartedContextType extends GettingStartedState {
  refreshCounts: () => Promise<void>;
  refreshNumberOfRegions: () => Promise<void>;
  refreshNumberOfCustomActivityCategoryCodes: () => Promise<void>;
  refreshNumberOfCustomSectors: () => Promise<void>;
  refreshNumberOfCustomLegalForms: () => Promise<void>;
}

const GettingStartedContext = createContext<GettingStartedContextType | undefined>(undefined);

export const GettingStartedProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [state, setState] = useState<GettingStartedState>({
    activity_category_standard: null,
    numberOfRegions: null,
    numberOfCustomActivityCategoryCodes: null,
    numberOfCustomSectors: null,
    numberOfCustomLegalForms: null,
  });

  const [client, setClient] = useState<StatbusClient | null>(null);

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


  const refreshCounts = useCallback(async () => {
    await refreshActivityCategoryStandard();
    await refreshNumberOfRegions();
    await refreshNumberOfCustomActivityCategoryCodes();
    await refreshNumberOfCustomSectors();
    await refreshNumberOfCustomLegalForms();
  }, [
    refreshActivityCategoryStandard,
    refreshNumberOfCustomActivityCategoryCodes,
    refreshNumberOfCustomLegalForms,
    refreshNumberOfCustomSectors,
    refreshNumberOfRegions,
  ]);

  useEffect(() => {
    let isMounted = true;
    const initializeClient = async () => {
      try {
        const postgrestClient = await getBrowserClient();
        if (isMounted) {
          setClient(postgrestClient);
        }
      } catch (error) {
        console.error("Error initializing browser client in GettingStartedContext:", error);
      }
    };
    initializeClient();
    
    return () => {
      isMounted = false;
    };
  }, []);

  useEffect(() => {
    if (client) {
      let isMounted = true;
      
      const loadData = async () => {
        try {
          // Check authentication status first
          const authenticated = await isAuthenticated();
          console.log('GettingStartedContext: Authentication status:', authenticated);
          
          if (!authenticated || !isMounted) {
            console.warn("Not authenticated or component unmounted, skipping data fetch");
            return;
          }
          
          // Pre-fetch base data to ensure it's cached (includes time contexts)
          try {
            const { baseDataStore } = await import('@/context/BaseDataStore');
            await baseDataStore.getBaseData(client);
            console.log('Base data pre-fetched successfully');
          } catch (error) {
            console.warn('Failed to pre-fetch base data:', error);
            // Continue anyway, as this is just optimization
          }
          
          // Test connection with a simple query first
          const response = await client.from("settings").select("id").limit(1);
          console.log('Connection test result:', {
            success: !response.error,
            error: response.error,
            status: response.status
          });
          
          if (!response.error && isMounted) {
            // Only try to access data if authenticated and test succeeded
            await refreshCounts();
          } else if (isMounted) {
            console.error("Connection test failed:", response.error);
          }
        } catch (err) {
          if (isMounted) {
            console.error("Failed to load data:", err);
          }
        }
      };
      
      loadData();
      
      return () => {
        isMounted = false;
      };
    }
  }, [client, refreshCounts]);

  return (
    <GettingStartedContext.Provider
      value={{
        ...state,
        refreshCounts,
        refreshNumberOfRegions,
        refreshNumberOfCustomActivityCategoryCodes,
        refreshNumberOfCustomSectors,
        refreshNumberOfCustomLegalForms,
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

