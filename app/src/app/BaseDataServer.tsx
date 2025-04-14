"use server";

import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { getServerClient } from "@/context/ClientStore";
import { ClientBaseDataProvider } from "./BaseDataClient";
import { BaseData } from '@/context/BaseDataStore';
import { authStore, AuthenticationError, User } from '@/context/AuthStore';

// Define StatbusClient type locally
type StatbusClient = PostgrestClient<Database>;

export async function getBaseData(client: StatbusClient): Promise<BaseData & { isAuthenticated: boolean; user: User | null }> {
  try {
    // Get authentication status from the single source of truth
    const authStatus = await authStore.getAuthStatus();
    
    // If not authenticated, return empty data with auth status
    if (!authStatus.isAuthenticated) {
      return {
        isAuthenticated: false,
        user: null,
        statDefinitions: [],
        externalIdentTypes: [],
        statbusUsers: [],
        timeContexts: [],
        defaultTimeContext: null,
        hasStatisticalUnits: false,
      };
    }

    // Import the baseDataStore
    const { baseDataStore } = await import('@/context/BaseDataStore');
    
    try {
      // Use BaseDataStore to fetch data
      console.log('Fetching base data via BaseDataStore...');
      const baseData = await baseDataStore.getBaseData(client);
      
      console.log('Base data fetch completed via BaseDataStore', {
        statDefinitionsCount: baseData.statDefinitions.length,
        externalIdentTypesCount: baseData.externalIdentTypes.length,
        statbusUsersCount: baseData.statbusUsers.length,
        timeContextsCount: baseData.timeContexts.length,
        hasDefaultTimeContext: !!baseData.defaultTimeContext,
        hasStatisticalUnits: baseData.hasStatisticalUnits
      });
      
      // Return data with authentication status
      return {
        isAuthenticated: true,
        user: authStatus.user,
        ...baseData
      };
    } catch (error) {
      console.error('Error fetching base data via BaseDataStore:', error);
      
      // Check if this is an authentication error
      if (error instanceof Response && error.status === 401) {
        return {
          isAuthenticated: false,
          user: null,
          statDefinitions: [],
          externalIdentTypes: [],
          statbusUsers: [],
          timeContexts: [],
          defaultTimeContext: null,
          hasStatisticalUnits: false,
        };
      }
      
      if (error instanceof AuthenticationError) {
        return {
          isAuthenticated: false,
          user: null,
          statDefinitions: [],
          externalIdentTypes: [],
          statbusUsers: [],
          timeContexts: [],
          defaultTimeContext: null,
          hasStatisticalUnits: false,
        };
      }
      
      if (error instanceof Error) {
        throw new Error(`Failed to fetch base data: ${error.message}`);
      } else {
        throw new Error('Failed to fetch base data: An unknown error occurred.');
      }
    }
  } catch (error) {
    console.error('Error in getBaseData authentication check:', error);
    
    // If authentication check itself fails, return unauthenticated state
    return {
      isAuthenticated: false,
      user: null,
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null,
      hasStatisticalUnits: false,
    };
  }
}

// Server component to fetch and provide base data
export const ServerBaseDataProvider = async ({ children }: { children: React.ReactNode }) => {
  const client = await getServerClient();
  const baseData = await getBaseData(client);

  return (
    <ClientBaseDataProvider initalBaseData={baseData}>
      {children}
    </ClientBaseDataProvider>
  );
};

// Re-export the BaseData type from BaseDataStore for convenience
export type { BaseData } from '@/context/BaseDataStore';
