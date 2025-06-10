"use server";

import { headers } from 'next/headers'; // Import headers
import { PostgrestClient } from '@supabase/postgrest-js';
import { Database } from '@/lib/database.types';
import { getServerRestClient } from "@/context/RestClientStore";
// import { ClientBaseDataProvider } from "./BaseDataClient"; // Removed
import type { BaseData, User } from "@/atoms"; // Assuming types are exported from atoms/index.ts
import { authStore, AuthenticationError } from '@/context/AuthStore'; // authStore still used in getBaseData
import { InitialStateHydrator } from "./InitialStateHydrator"; // Added

export async function getBaseData(client: PostgrestClient<Database>): Promise<BaseData & { isAuthenticated: boolean; user: User | null }> {
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
  // Opt this specific server component into dynamic rendering.
  // This is necessary because it will call getServerRestClient which uses cookies().
  // The parent <Suspense> in layout.tsx will handle the fallback.
  const nextHeaders = headers(); // This call makes this component dynamic.

  const client = await getServerRestClient();
  const baseDataWithAuth = await getBaseData(client);

  // ClientBaseDataProvider is removed.
  // We pass the initial server-fetched data to InitialStateHydrator,
  // which is a client component responsible for setting the initial Jotai atom states.
  return (
    <InitialStateHydrator initialData={baseDataWithAuth}>
      {children}
    </InitialStateHydrator>
  );
};

// Re-export the BaseData type (if still needed directly by consumers of this file)
// Or consider removing if all consumers now get BaseData type from @/atoms
// For now, let's assume the type export might still be used elsewhere.
export type { BaseData } from '@/atoms'; // Assuming type is exported from atoms/index.ts
