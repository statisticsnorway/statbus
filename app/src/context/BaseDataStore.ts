/**
 * BaseDataStore - A singleton store for managing base data
 * 
 * This store ensures that base data is:
 * 1. Fetched only once per session
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

import { Database, Tables } from "@/lib/database.types";
import { PostgrestClient } from "@supabase/postgrest-js";
import { getServerClient, getBrowserClient } from "./ClientStore";
export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[];
  externalIdentTypes: Tables<"external_ident_type_active">[];
  statbusUsers: Tables<"user_with_role">[];
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context"> | null;
  hasStatisticalUnits: boolean;
}

type FetchStatus = 'idle' | 'loading' | 'success' | 'error';

class BaseDataStore {
  private static instance: BaseDataStore;
  private data: BaseData = {
    statDefinitions: [],
    externalIdentTypes: [],
    statbusUsers: [],
    timeContexts: [],
    defaultTimeContext: null,
    hasStatisticalUnits: false,
  };
  private status: FetchStatus = 'idle';
  private fetchPromise: Promise<BaseData> | null = null;
  private lastFetchTime: number = 0;
  private readonly CACHE_TTL = 5 * 60 * 1000; // 5 minutes

  private constructor() {
    // Private constructor to enforce singleton pattern
  }

  public static getInstance(): BaseDataStore {
    if (!BaseDataStore.instance) {
      BaseDataStore.instance = new BaseDataStore();
    }
    return BaseDataStore.instance;
  }

  /**
   * Get base data, fetching from API if needed
   * This method deduplicates requests - multiple calls will share the same Promise
   */
  public async getBaseData(client?: PostgrestClient<Database>): Promise<BaseData> {
    const now = Date.now();

    // Get client from ClientStore if not provided
    if (!client) {
      try {
        client = typeof window === 'undefined' 
          ? await getServerClient() 
          : await getBrowserClient();
      } catch (error) {
        console.error('Failed to get client from ClientStore:', error);
        throw error;
      }
    }
    
    // If data is already loaded and cache is still valid, return it immediately
    if (this.status === 'success' && now - this.lastFetchTime < this.CACHE_TTL) {
      return this.data;
    }
    
    // If a fetch is already in progress, return the existing promise
    if (this.status === 'loading' && this.fetchPromise) {
      console.log('Reusing in-progress base data fetch');
      return this.fetchPromise;
    }
    
    // Start a new fetch
    console.log('Starting new base data fetch');
    this.status = 'loading';
    this.fetchPromise = this.fetchBaseData(client);
    
    try {
      const result = await this.fetchPromise;
      this.data = result;
      this.status = 'success';
      this.lastFetchTime = Date.now();
      console.log('Base data fetch completed successfully', {
        statDefinitionsCount: result.statDefinitions.length,
        externalIdentTypesCount: result.externalIdentTypes.length,
        statbusUsersCount: result.statbusUsers.length,
        hasStatisticalUnits: result.hasStatisticalUnits
      });
      return result;
    } catch (error) {
      this.status = 'error';
      console.error('Failed to fetch base data:', error);
      
      // Add more detailed error logging
      if (error instanceof Error) {
        console.error('Error details:', {
          name: error.name,
          message: error.message,
          stack: error.stack,
          originalError: (error as any).originalError,
          clientInfo: (error as any).clientInfo
        });
      }
      
      throw error;
    } finally {
      this.fetchPromise = null;
    }
  }

  /**
   * Force refresh the base data
   */
  public async refreshBaseData(client?: PostgrestClient<Database>): Promise<BaseData> {
    this.status = 'loading';
    
    // Get client from ClientStore if not provided
    if (!client) {
      try {
        client = typeof window === 'undefined' 
          ? await getServerClient() 
          : await getBrowserClient();
      } catch (error) {
        console.error('Failed to get client from ClientStore:', error);
        throw error;
      }
    }
    
    this.fetchPromise = this.fetchBaseData(client);
    
    try {
      const result = await this.fetchPromise;
      this.data = result;
      this.status = 'success';
      this.lastFetchTime = Date.now();
      return result;
    } catch (error) {
      this.status = 'error';
      console.error('Failed to refresh base data:', error);
      throw error;
    } finally {
      this.fetchPromise = null;
    }
  }

  /**
   * Update just the hasStatisticalUnits flag
   */
  public async refreshHasStatisticalUnits(client?: PostgrestClient<Database>): Promise<boolean> {
    // Get client from ClientStore if not provided
    if (!client) {
      try {
        client = typeof window === 'undefined' 
          ? await getServerClient() 
          : await getBrowserClient();
      } catch (error) {
        console.error('Failed to get client from ClientStore:', error);
        return false;
      }
    }
    
    if (!client || typeof client.from !== 'function') {
      console.error('Invalid client provided to refreshHasStatisticalUnits');
      return false;
    }

    try {
      console.log('Checking for statistical units...');
      const { data: maybeStatisticalUnit } = await client.from("statistical_unit").select("*").limit(1);
      const hasStatisticalUnits = maybeStatisticalUnit !== null && maybeStatisticalUnit.length > 0;
      
      // Update the cached data
      this.data.hasStatisticalUnits = hasStatisticalUnits;
      
      console.log(`Statistical units check: ${hasStatisticalUnits ? 'Found' : 'None found'}`);
      return hasStatisticalUnits;
    } catch (error) {
      console.error('Error checking for statistical units:', error);
      return false;
    }
  }

  /**
   * Clear the cached base data
   */
  public clearCache(): void {
    this.data = {
      statDefinitions: [],
      externalIdentTypes: [],
      statbusUsers: [],
      timeContexts: [],
      defaultTimeContext: null,
      hasStatisticalUnits: false,
    };
    this.status = 'idle';
    this.lastFetchTime = 0;
  }

  /**
   * Get the current fetch status
   */
  public getStatus(): FetchStatus {
    return this.status;
  }
  
  /**
   * Get debug information about the store state
   * This is useful for diagnosing issues
   */
  public getDebugInfo(): Record<string, any> {
    return {
      status: this.status,
      lastFetchTime: this.lastFetchTime,
      cacheAge: this.lastFetchTime ? Math.round((Date.now() - this.lastFetchTime) / 1000) + 's' : 'never',
      hasFetchPromise: !!this.fetchPromise,
      dataLoaded: this.status === 'success',
      statDefinitionsCount: this.data.statDefinitions.length,
      externalIdentTypesCount: this.data.externalIdentTypes.length,
      statbusUsersCount: this.data.statbusUsers.length,
      hasStatisticalUnits: this.data.hasStatisticalUnits,
      cacheTTL: this.CACHE_TTL / 1000 + 's',
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
  }

  /**
   * Internal method to fetch base data from API
   */
  private async fetchBaseData(client: PostgrestClient<Database>): Promise<BaseData> {
    if (!client || typeof client.from !== 'function') {
      console.error('Invalid client provided to fetchBaseData');
      throw new Error('Invalid client provided');
    }

    // Enhanced debugging for client object
    const clientDebugInfo = {
      hasFrom: typeof client.from === 'function',
      hasRest: !!(client as any).rest,
      restUrl: (client as any).rest?.url || 'undefined',
      hasAuth: !!(client as any).auth,
      url: client.url,
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
    
    console.log('BaseDataStore client debug info:', clientDebugInfo);
    
    try {
      console.log(`${typeof window !== 'undefined' ? 'Browser' : 'Server'}-side: Fetching base data`);
      
      // Fetch time contexts directly instead of using TimeContextStore
      // This avoids circular dependencies between stores
      console.log('Fetching time contexts directly...');
      let timeContextData: {
        timeContexts: Tables<"time_context">[];
        defaultTimeContext: Tables<"time_context"> | null;
      } = {
        timeContexts: [],
        defaultTimeContext: null
      };
      
      try {
        // Add safety check for client URL
        if (!client.url) {
          console.error('Client URL is undefined or empty');
          throw new Error('Client URL is undefined or empty');
        }
        
        console.log(`Client URL for time_context request: ${client.url}`);
        
        // Safely construct the request
        try {
          // For browser requests, ensure the URL is correct
          // We don't need to modify it since we're now using NEXT_PUBLIC_BROWSER_API_URL
          // which should already have the correct value
          if (typeof window !== 'undefined') {
            console.log('Browser client URL check:', client.url);
            
            // Just log a warning if the URL doesn't include '/postgrest'
            if (client.url && !client.url.includes('/postgrest')) {
              console.warn('Warning: Client URL may be missing /postgrest prefix:', client.url);
            }
          }
          
          console.log('Making request to:', `${client.url}/time_context`);
          const { data: timeContexts, error } = await client.from("time_context").select("*");
          
          if (error) {
            console.error('Error fetching time contexts:', error);
          } else if (timeContexts && timeContexts.length > 0) {
            console.log(`Successfully fetched ${timeContexts.length} time contexts directly`);
            timeContextData = {
              timeContexts,
              defaultTimeContext: timeContexts[0]
            };
          }
        } catch (error) {
          console.error('Exception in client.from("time_context"):', error);
          // Try a more direct approach if the PostgrestClient.from method fails
          console.log('Attempting alternative fetch approach...');
        }
      } catch (error) {
        console.error('Exception fetching time contexts directly:', error);
      }
      
      // Fetch the rest of the data in parallel
      console.log('Fetching remaining base data...');
      
      // Add safety check for client URL before proceeding
      if (!client.url) {
        console.error('Client URL is undefined or empty before parallel requests');
        throw new Error('Client URL is undefined or empty');
      }
      
      // Wrap each request in a try/catch to prevent one failure from stopping all requests
      let maybeStatDefinitions = null, statDefinitionsError = null;
      let maybeExternalIdentTypes = null, externalIdentTypesError = null;
      let maybeStatbusUsers = null, statbusUsersError = null;
      let maybeStatisticalUnit = null, statisticalUnitError = null;
      
      try {
        console.log('Fetching stat_definition_active...');
        const statDefResult = await client.from("stat_definition_active").select();
        maybeStatDefinitions = statDefResult.data;
        statDefinitionsError = statDefResult.error;
      } catch (error) {
        console.error('Exception fetching stat_definition_active:', error);
        statDefinitionsError = error;
      }
      
      try {
        console.log('Fetching external_ident_type_active...');
        const extIdentResult = await client.from("external_ident_type_active").select();
        maybeExternalIdentTypes = extIdentResult.data;
        externalIdentTypesError = extIdentResult.error;
      } catch (error) {
        console.error('Exception fetching external_ident_type_active:', error);
        externalIdentTypesError = error;
      }
      
      try {
        console.log('Fetching user_with_role...');
        const usersResult = await client.from("user_with_role").select();
        maybeStatbusUsers = usersResult.data;
        statbusUsersError = usersResult.error;
      } catch (error) {
        console.error('Exception fetching user_with_role:', error);
        statbusUsersError = error;
      }
      
      try {
        console.log('Fetching statistical_unit...');
        const statUnitResult = await client.from("statistical_unit").select("*").limit(1);
        maybeStatisticalUnit = statUnitResult.data;
        statisticalUnitError = statUnitResult.error;
      } catch (error) {
        console.error('Exception fetching statistical_unit:', error);
        statisticalUnitError = error;
      }
      
      // Check for errors
      if (statDefinitionsError) {
        console.error('Error fetching stat definitions:', statDefinitionsError);
      }
      if (externalIdentTypesError) {
        console.error('Error fetching external ident types:', externalIdentTypesError);
      }
      if (statbusUsersError) {
        console.error('Error fetching statbus users:', statbusUsersError);
      }
      if (statisticalUnitError) {
        console.error('Error checking for statistical units:', statisticalUnitError);
      }
      
      // Log the results
      console.log('Base data fetch results:', {
        statDefinitions: maybeStatDefinitions?.length || 0,
        externalIdentTypes: maybeExternalIdentTypes?.length || 0,
        statbusUsers: maybeStatbusUsers?.length || 0,
        timeContexts: timeContextData.timeContexts?.length || 0,
        hasStatisticalUnits: maybeStatisticalUnit !== null && Array.isArray(maybeStatisticalUnit) && maybeStatisticalUnit.length > 0
      });
      
      // Return the base data
      return {
        statDefinitions: maybeStatDefinitions || [],
        externalIdentTypes: maybeExternalIdentTypes || [],
        statbusUsers: maybeStatbusUsers || [],
        timeContexts: timeContextData.timeContexts || [],
        defaultTimeContext: timeContextData.defaultTimeContext,
        hasStatisticalUnits: maybeStatisticalUnit !== null && Array.isArray(maybeStatisticalUnit) && maybeStatisticalUnit.length > 0
      };
    } catch (error) {
      console.error('Exception fetching base data:', error);
      throw error;
    }
  }
}

// Export a singleton instance
export const baseDataStore = BaseDataStore.getInstance();
