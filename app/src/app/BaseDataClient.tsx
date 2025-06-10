"use client";

import React, { createContext, useContext, ReactNode, useState, useEffect, useCallback } from 'react';
import { getBrowserRestClient } from "@/context/RestClientStore";
import { PostgrestClient } from '@supabase/postgrest-js';
import { useAuth } from '@/hooks/useAuth'; // Import useAuth hook
import { Database } from '@/lib/database.types';
import { BaseData, baseDataStore } from '@/context/BaseDataStore'; // Import type and store instance
import { authStore, User } from '@/context/AuthStore';

// Define the shape of the context value including worker status
type WorkerStatus = {
  isImporting: boolean | null;
  isDerivingUnits: boolean | null;
  isDerivingReports: boolean | null;
  isLoading: boolean;
  error: string | null;
};

type BaseDataContextValue = BaseData & {
  isAuthenticated: boolean;
  user: User | null;
  workerStatus: WorkerStatus;
  refreshHasStatisticalUnits: () => Promise<boolean>;
  refreshAllBaseData: () => Promise<void>;
  getDebugInfo: () => Record<string, any>;
  ensureAuthenticated: () => boolean;
};


// Create a context for the base data
const BaseDataClientContext = createContext<BaseDataContextValue>({
  isAuthenticated: false,
  user: null,
  ...({} as BaseData), // Initial empty base data
  workerStatus: baseDataStore.getWorkerStatus(), // Get initial status from store
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
  // State for base data (passed from server)
  const [baseData, setBaseData] = useState(initalBaseData);
  // State for worker status (synced with store)
  const [workerStatus, setWorkerStatus] = useState<WorkerStatus>(baseDataStore.getWorkerStatus());
  // State for the Postgrest client
  const [client, setClient] = useState<PostgrestClient<Database> | null>(null);
  // State for SSE connection error
  const [sseConnectionError, setSseConnectionError] = useState<string | null>(null);


  // Effect to initialize the Postgrest client
  useEffect(() => {
    const initializeClient = async () => {
      try {
        // Use getBrowserRestClient from RestClientStore
        // This ensures we're using the singleton pattern correctly
        const postgrestClient = await getBrowserRestClient();
        setClient(postgrestClient);
      } catch (error) {
        console.error("Error initializing browser client:", error);
      }
    };
    initializeClient();
  }, []);

  // Effect to synchronize auth state from AuthContext into local baseData state
  useEffect(() => {
    setBaseData(prev => {
      // Update local baseData if AuthContext state differs
      if (prev.isAuthenticated !== authContextIsAuthenticated || prev.user !== authContextUser) {
        return {
          ...prev,
          isAuthenticated: authContextIsAuthenticated,
          user: authContextUser,
        };
      }
      return prev; // No change needed
    });
  }, [authContextIsAuthenticated, authContextUser]);

  // Effect to subscribe to BaseDataStore worker status changes
  useEffect(() => {
    const handleStatusChange = () => {
      setWorkerStatus(baseDataStore.getWorkerStatus());
    };
    // Subscribe and get the unsubscribe function
    const unsubscribe = baseDataStore.subscribeWorkerStatus(handleStatusChange);
    // Initial sync
    handleStatusChange();
    // Cleanup subscription on unmount
    return () => unsubscribe();
  }, []); // Run only once on mount

  // Effect to manage the SSE connection for 'check' notifications
  useEffect(() => {
    let eventSource: EventSource | null = null;

    if (baseData.isAuthenticated) {
      console.log("[SSE] BaseDataClient: User authenticated. Setting up EventSource listener for /api/sse/worker-check");
      eventSource = new EventSource('/api/sse/worker-check'); // Updated route path
      setSseConnectionError(null); // Reset error on new connection attempt

      eventSource.onopen = () => {
        console.log('[SSE] BaseDataClient: Connection opened successfully.');
        setSseConnectionError(null);
      };

      // Generic message handler for debugging
      eventSource.onmessage = (event) => {
        console.warn('[SSE] BaseDataClient: Received generic message (without specific event type):', event);
      };

      eventSource.addEventListener('check', (event) => {
        console.log('[SSE] BaseDataClient: Received "check" event:', event);
        try {
          const functionName = event.data;
          console.log('[SSE] BaseDataClient: Received check hint payload:', functionName);
          
          if (functionName === 'is_importing' || 
              functionName === 'is_deriving_statistical_units' || 
              functionName === 'is_deriving_reports') {
            console.log(`[SSE] BaseDataClient: Checking function: ${functionName}`);
            baseDataStore.refreshWorkerStatus(functionName);
          } else {
            console.warn(`[SSE] BaseDataClient: Unknown function name: ${functionName}`);
          }
        } catch (err) {
          console.error('[SSE] BaseDataClient: Error processing check SSE message:', err);
          setSseConnectionError('Error processing status check hint.');
        }
      });

      eventSource.onerror = (err) => {
        console.error('[SSE] BaseDataClient: EventSource encountered an error:', err);
        setSseConnectionError('Connection error. Status updates may be unavailable. Check browser console/network tab.');
        if (eventSource) eventSource.close(); // Close the connection on error
      };
    } else {
      console.log("[SSE] BaseDataClient: User not authenticated or auth state not ready. SSE connection not started.");
    }

    // Cleanup function
    return () => {
      if (eventSource) {
        console.log('[SSE] BaseDataClient: Closing EventSource connection (due to unmount or auth change).');
        eventSource.close();
      }
    };
  }, [baseData.isAuthenticated]); // Re-run when isAuthenticated changes

  // --- Callback functions provided by context ---

  const refreshHasStatisticalUnits = useCallback(async () => {
    if (!client) return false;
    try {
      const hasStatisticalUnits = await baseDataStore.refreshHasStatisticalUnits(client);
      // Update the local state for baseData (which includes hasStatisticalUnits)
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
      const freshBaseData = await baseDataStore.refreshBaseData(client);
      // Update the local state with the new data, preserving auth state
      setBaseData((prev) => ({
        ...freshBaseData,
        isAuthenticated: prev.isAuthenticated,
        user: prev.user,
      }));
      console.log('Base data refreshed successfully via context');
    } catch (error) {
      console.error("Error refreshing base data via context:", error);
    }
  }, [client]);

  const getDebugInfo = useCallback(() => {
    // Add SSE connection status to debug info
    const storeInfo = baseDataStore.getDebugInfo();
    return {
      ...storeInfo,
      sseConnectionError: sseConnectionError,
    };
  }, [sseConnectionError]);

  const ensureAuthenticated = useCallback(() => {
    if (!baseData.isAuthenticated) {
      if (process.env.NODE_ENV === 'development') {
        console.warn('Attempting to use base data while not authenticated');
      }
      return false;
    }
    return true;
  }, [baseData.isAuthenticated]);

  // --- Context Provider ---

  // Combine base data and worker status for the context value
  const contextValue: BaseDataContextValue = {
    ...baseData,
    isAuthenticated: baseData.isAuthenticated,
    user: baseData.user,
    workerStatus: { // Include the latest status from local state (synced with store)
      ...workerStatus,
      // Override error if SSE connection failed
      error: workerStatus.error || sseConnectionError
    },
    refreshHasStatisticalUnits,
    refreshAllBaseData,
    getDebugInfo,
    ensureAuthenticated
  };

  return (
    <BaseDataClientContext.Provider value={contextValue}>
      {children}
    </BaseDataClientContext.Provider>
  );
};
