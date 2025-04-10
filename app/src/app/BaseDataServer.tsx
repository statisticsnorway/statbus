"use server";

import { SupabaseClient } from '@supabase/supabase-js';
import { Tables } from "@/lib/database.types";
import { createPostgRESTSSRClient } from "@/utils/auth/postgrest-client-server";
import { ClientBaseDataProvider } from "./BaseDataClient";

export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[];
  externalIdentTypes: Tables<"external_ident_type_active">[];
  statbusUsers: Tables<"user_with_role">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context">;
  hasStatisticalUnits: boolean;
}

async function checkAuthStatus(): Promise<boolean> {
  try {
    const response = await fetch(`${process.env.SERVER_API_URL}/postgrest/rpc/auth_status`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      },
      credentials: 'include'
    });
    
    if (response.ok) {
      const data = await response.json();
      return data.authenticated === true;
    }
    return false;
  } catch (error) {
    console.error('Error checking auth status:', error);
    return false;
  }
}

export async function getBaseData(client: SupabaseClient): Promise<BaseData> {
  console.log('Starting getBaseData with client:', !!client);

  // Check if user is authenticated before proceeding
  const isAuthenticated = await checkAuthStatus();
  if (!isAuthenticated) {
    console.log('User is not authenticated, returning empty base data');
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
    const response = await fetch(restUrl, {
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

  let maybeStatDefinitions, maybeExternalIdentTypes, maybeStatbusUsers, maybeTimeContexts, maybeStatisticalUnit;
  try {
    console.log('Fetching base data from database...');
    
    // Fetch time contexts separately first for better debugging
    console.log('Fetching time contexts...');
    const timeContextResponse = await client.from("time_context").select();
    console.log('Time context response:', {
      status: timeContextResponse.status,
      statusText: timeContextResponse.statusText,
      error: timeContextResponse.error,
      count: timeContextResponse.data?.length || 0
    });
    maybeTimeContexts = timeContextResponse.data;
    
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
      timeContexts: maybeTimeContexts?.length || 0,
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

  if (!maybeTimeContexts || maybeTimeContexts.length === 0) {
    console.error('Missing required time context. Raw response:', maybeTimeContexts);
    throw new Error("Missing required time context");
  }
  console.log('Time contexts found:', maybeTimeContexts.length);
  const statDefinitions = maybeStatDefinitions as NonNullable<typeof maybeStatDefinitions>;
  const externalIdentTypes = maybeExternalIdentTypes as NonNullable<typeof maybeExternalIdentTypes>;
const statbusUsers = maybeStatbusUsers as NonNullable<typeof maybeStatbusUsers>;
  const timeContexts = maybeTimeContexts as NonNullable<typeof maybeTimeContexts>;
  const defaultTimeContext = timeContexts[0];
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
