"use server";

import { SupabaseClient } from '@supabase/supabase-js';
import { Tables } from "@/lib/database.types";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import { ClientBaseDataProvider } from "./BaseDataClient";
// Remove direct import of serverFetch

export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[];
  externalIdentTypes: Tables<"external_ident_type_active">[];
  statbusUsers: Tables<"user_with_role">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context">;
  hasStatisticalUnits: boolean;
}

import { isAuthenticated } from '@/utils/auth/auth-utils';

export async function getBaseData(client: SupabaseClient): Promise<BaseData> {
  console.log('Starting getBaseData with client:', !!client);

  // We'll check authentication once at the beginning
  let authenticated = false;
  try {
    authenticated = await isAuthenticated();
    if (process.env.NODE_ENV === 'development') {
      console.log('BaseDataServer: Authentication status:', authenticated);
    }
  } catch (error) {
    console.error('Authentication check failed in getBaseData:', error);
  }
  
  // Return empty data if not authenticated
  if (!authenticated) {
    if (process.env.NODE_ENV === 'development') {
      console.log('User is not authenticated, returning empty base data');
    }
    return {
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null as any,
      hasStatisticalUnits: false,
    };
  }

  if (!client || typeof client.from !== 'function') {
    console.error('PostgREST client initialization error:', client);
    throw new Error('PostgREST client is not properly initialized.');
  }

  // Get the REST URL and fetch function from the client for debugging
  const restUrl = (client as any).rest?.url || 'URL not available';
  const restFetch = (client as any).rest?.fetch || 'Fetch function not available';
  console.log('Using REST URL:', restUrl);
  console.log('REST fetch available:', !!restFetch);
  
  // Test basic connectivity to the API
  try {
    // Dynamically import serverFetch
    const { serverFetch } = await import('@/utils/auth/server-fetch');
    const response = await serverFetch(restUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      }
    });
    console.log('API connectivity test:', {
      status: response.status,
      statusText: response.statusText,
      ok: response.ok
    });
  } catch (error) {
    console.error('API connectivity test failed:', error);
  }

  // Import the timeContextStore
  const { timeContextStore } = await import('@/context/TimeContextStore');
  
  let maybeStatDefinitions, maybeExternalIdentTypes, maybeStatbusUsers, maybeStatisticalUnit;
  let timeContextData;
  
  try {
    console.log('Fetching base data from database...');
    
    // Use TimeContextStore as the single source of truth for time context data
    console.log('Fetching time contexts via TimeContextStore...');
    try {
      timeContextData = await timeContextStore.getTimeContextData(client);
      console.log(`Successfully fetched ${timeContextData.timeContexts?.length || 0} time contexts via TimeContextStore`);
    } catch (error) {
      console.error('Error fetching time contexts via TimeContextStore:', error);
      // No fallback - we trust our TimeContextStore implementation
      // Return empty data to avoid crashes, but log the error clearly
      console.error('TimeContextStore failed - this is a critical error that needs fixing');
      timeContextData = {
        timeContexts: [],
        defaultTimeContext: null
      };
    }
    
    // Fetch the rest of the data
    [
      { data: maybeStatDefinitions },
      { data: maybeExternalIdentTypes },
      { data: maybeStatbusUsers },
      { data: maybeStatisticalUnit },
    ] = await Promise.all([
      client.from("stat_definition_active").select(),
      client.from("external_ident_type_active").select(),
      client.from("user_with_role").select(),
      client.from("statistical_unit").select("*").limit(1),
    ]);
    
    console.log('Data fetch results:', {
      statDefinitions: maybeStatDefinitions?.length || 0,
      externalIdentTypes: maybeExternalIdentTypes?.length || 0,
      statbusUsers: maybeStatbusUsers?.length || 0,
      timeContexts: timeContextData.timeContexts?.length || 0,
      hasStatisticalUnits: maybeStatisticalUnit?.length || 0
    });
  } catch (error) {
    console.error('Error fetching base data:', error);
    if (error instanceof Error) {
      throw new Error(`Failed to fetch base data: ${error.message}`);
    } else {
      throw new Error('Failed to fetch base data: An unknown error occurred.');
    }
  }

  if (!timeContextData.timeContexts || timeContextData.timeContexts.length === 0) {
    console.error('Missing required time context.');
    // Instead of throwing an error, return empty data
    return {
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null as any,
      hasStatisticalUnits: false,
    };
  }
  console.log('Time contexts found:', timeContextData.timeContexts.length);
  const statDefinitions = maybeStatDefinitions as NonNullable<typeof maybeStatDefinitions>;
  const externalIdentTypes = maybeExternalIdentTypes as NonNullable<typeof maybeExternalIdentTypes>;
  const statbusUsers = maybeStatbusUsers as NonNullable<typeof maybeStatbusUsers>;
  const timeContexts = timeContextData.timeContexts;
  const defaultTimeContext = timeContextData.defaultTimeContext || timeContexts[0];
  const hasStatisticalUnits = maybeStatisticalUnit !== null && maybeStatisticalUnit.length > 0;

  return {
    statDefinitions,
    externalIdentTypes,
    statbusUsers,
    timeContexts,
    defaultTimeContext,
    hasStatisticalUnits,
  };
}

// Server component to fetch and provide base data
export const ServerBaseDataProvider = async ({ children }: { children: React.ReactNode }) => {
  const client = await createPostgRESTSSRClient();
  const baseData = await getBaseData(client);

  return (
    <ClientBaseDataProvider initalBaseData={baseData}>
      {children}
    </ClientBaseDataProvider>
  );
};
