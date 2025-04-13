"use client";

import React, { createContext, useContext, ReactNode, useState, useEffect, useCallback } from 'react';
import { getBrowserClient } from "@/utils/auth/postgrest-client-browser";
import { SupabaseClient } from '@supabase/supabase-js';
import { BaseData } from './BaseDataServer';

// Create a context for the base data
const BaseDataClientContext = createContext<BaseData & { refreshHasStatisticalUnits: () => Promise<void> }>({
  ...({} as BaseData),
  refreshHasStatisticalUnits: async () => {},
});

// Hook to use the base data context
export const useBaseData = () => {
  const context = useContext(BaseDataClientContext);
  if (!context) {
    throw new Error("useBaseData must be used within a ClientBaseDataProvider");
  }
  return context;
};

// Client component to provide base data context
export const ClientBaseDataProvider = ({ children, initalBaseData }: { children: ReactNode, initalBaseData: BaseData }) => {
  const [baseData, setBaseData] = useState(initalBaseData);
  const [client, setClient] = useState<SupabaseClient | null>(null);

  useEffect(() => {
    const initializeClient = async () => {
      try {
        // Use getBrowserClient instead of createPostgRESTBrowserClient
        // This ensures we're using the singleton pattern correctly
        const supabaseClient = await getBrowserClient();
        setClient(supabaseClient);
      } catch (error) {
        console.error("Error initializing browser client:", error);
      }
    };
    initializeClient();
  }, []);

  const refreshHasStatisticalUnits = useCallback(async () => {
    if (!client) return;
    const maybeUnit = await client.from("statistical_unit").select("*").limit(1);
    const hasStatisticalUnits = (maybeUnit.data && maybeUnit.data?.length > 0) ?? false;
    setBaseData((prevBaseData) => ({
      ...prevBaseData,
      hasStatisticalUnits,
    }));
  }, [client]);

return (
    <BaseDataClientContext.Provider value={{ ...baseData, refreshHasStatisticalUnits }}>
      {children}
    </BaseDataClientContext.Provider>
  );
};
