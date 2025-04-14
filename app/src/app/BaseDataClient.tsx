"use client";

import React, { createContext, useContext, ReactNode, useState, useEffect, useCallback } from 'react';
import { getBrowserClient } from "@/context/ClientStore";
import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { BaseData } from '@/context/BaseDataStore';
import { authStore, User } from '@/context/AuthStore';

// Create a context for the base data
const BaseDataClientContext = createContext<BaseData & { 
  isAuthenticated: boolean;
  user: User | null;
  refreshHasStatisticalUnits: () => Promise<boolean>;
  refreshAllBaseData: () => Promise<void>;
  getDebugInfo: () => Record<string, any>;
  ensureAuthenticated: () => boolean;
}>({
  isAuthenticated: false,
  user: null,
  ...({} as BaseData),
  refreshHasStatisticalUnits: async () => false,
  refreshAllBaseData: async () => {},
  getDebugInfo: () => ({}),
  ensureAuthenticated: () => false,
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
export const ClientBaseDataProvider = ({ 
  children, 
  initalBaseData 
}: { 
  children: ReactNode, 
  initalBaseData: BaseData & { isAuthenticated: boolean; user: User | null } 
}) => {
  const [baseData, setBaseData] = useState(initalBaseData);
  const [client, setClient] = useState<PostgrestClient<Database> | null>(null);

  useEffect(() => {
    const initializeClient = async () => {
      try {
        // Use getBrowserClient from ClientStore
        // This ensures we're using the singleton pattern correctly
        const postgrestClient = await getBrowserClient();
        setClient(postgrestClient);
      } catch (error) {
        console.error("Error initializing browser client:", error);
      }
    };
    initializeClient();
  }, []);

  const refreshHasStatisticalUnits = useCallback(async () => {
    if (!client) return false;
    try {
      // Import the baseDataStore
      const { baseDataStore } = await import('@/context/BaseDataStore');
      
      // Use the BaseDataStore to refresh the hasStatisticalUnits flag
      const hasStatisticalUnits = await baseDataStore.refreshHasStatisticalUnits(client);
      
      // Update the local state with the new value
      setBaseData((prevBaseData) => ({
        ...prevBaseData,
        hasStatisticalUnits,
      }));
      
      return hasStatisticalUnits;
    } catch (error) {
      console.error("Error refreshing hasStatisticalUnits:", error);
      return false;
    }
  }, [client]);
  
  const refreshAllBaseData = useCallback(async () => {
    if (!client) return;
    
    try {
      // Import the baseDataStore
      const { baseDataStore } = await import('@/context/BaseDataStore');
      
      // Use the BaseDataStore to refresh all base data
      const freshBaseData = await baseDataStore.refreshBaseData(client);
      
      // Update the local state with the new data
      setBaseData(freshBaseData as BaseData & { isAuthenticated: boolean; user: User | null });
      
      console.log('Base data refreshed successfully', {
        statDefinitionsCount: freshBaseData.statDefinitions.length,
        externalIdentTypesCount: freshBaseData.externalIdentTypes.length,
        statbusUsersCount: freshBaseData.statbusUsers.length,
        timeContextsCount: freshBaseData.timeContexts.length,
        hasDefaultTimeContext: !!freshBaseData.defaultTimeContext,
        hasStatisticalUnits: freshBaseData.hasStatisticalUnits
      });
    } catch (error) {
      console.error("Error refreshing base data:", error);
    }
  }, [client]);
  
  const getDebugInfo = useCallback(() => {
    // Import the baseDataStore
    try {
      // We need to use a dynamic import here since we're in a callback
      // This is a bit of a hack, but it works for debugging purposes
      const baseDataStore = require('@/context/BaseDataStore').baseDataStore;
      return baseDataStore.getDebugInfo();
    } catch (error) {
      console.error("Error getting base data debug info:", error);
      return {
        error: 'Failed to get debug info',
        message: error instanceof Error ? error.message : String(error)
      };
    }
  }, []);

  // Function to check if authenticated and warn if not
  const ensureAuthenticated = useCallback(() => {
    if (!baseData.isAuthenticated) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('Attempting to use base data while not authenticated');
      }
      return false;
    }
    return true;
  }, [baseData.isAuthenticated]);

  return (
    <BaseDataClientContext.Provider value={{ 
      ...baseData, 
      isAuthenticated: baseData.isAuthenticated,
      user: baseData.user,
      refreshHasStatisticalUnits,
      refreshAllBaseData,
      getDebugInfo,
      ensureAuthenticated
    }}>
      {children}
    </BaseDataClientContext.Provider>
  );
};
