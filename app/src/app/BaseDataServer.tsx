"use server";

import { SupabaseClient } from '@supabase/supabase-js';
import { getServerClient } from "@/context/ClientStore";
import { ClientBaseDataProvider } from "./BaseDataClient";
import { BaseData } from '@/context/BaseDataStore';

export async function getBaseData(client: SupabaseClient): Promise<BaseData> {
  console.log('Starting getBaseData with client:', !!client);

  // Import the baseDataStore
  const { baseDataStore } = await import('@/context/BaseDataStore');
  
  try {
    // Use BaseDataStore as the single source of truth for all base data
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
    
    return baseData;
  } catch (error) {
    console.error('Error fetching base data via BaseDataStore:', error);
    if (error instanceof Error) {
      throw new Error(`Failed to fetch base data: ${error.message}`);
    } else {
      throw new Error('Failed to fetch base data: An unknown error occurred.');
    }
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
