/**
 * BaseDataStore - A singleton store for managing base data
 * 
 * This store ensures that base data is:
 * 1. Fetched only once per session
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

import { Tables } from "@/lib/database.types";
import { SupabaseClient } from '@supabase/supabase-js';

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
  public async getBaseData(client: any): Promise<BaseData> {
    const now = Date.now();
    
    // Check authentication directly from cookies if on server
    let authenticated = false;
    try {
      if (typeof window === 'undefined') {
        // Server-side - check cookies directly
        const { cookies } = await import('next/headers');
        const cookieStore = await cookies();
        const token = cookieStore.get('statbus');
        authenticated = !!token;
      } else {
        // Client-side - use auth-utils
        const { isAuthenticated } = await import('@/utils/auth/auth-utils');
        authenticated = await isAuthenticated();
      }
      
      if (!authenticated) {
        console.log('Not authenticated, returning empty base data');
        return {
          statDefinitions: [],
          externalIdentTypes: [],
          statbusUsers: [],
          timeContexts: [],
          defaultTimeContext: null,
          hasStatisticalUnits: false,
        };
      }
    } catch (error) {
      console.error('Authentication check failed in BaseDataStore:', error);
      // Continue with the request, but log the error
    }
    
    // If data is already loaded and cache is still valid, return it immediately
    if (this.status === 'success' && now - this.lastFetchTime < this.CACHE_TTL) {
      console.log('Using cached base data', {
        cacheAge: Math.round((now - this.lastFetchTime) / 1000) + 's',
        hasStatisticalUnits: this.data.hasStatisticalUnits,
        statDefinitionsCount: this.data.statDefinitions.length,
        externalIdentTypesCount: this.data.externalIdentTypes.length,
        statbusUsersCount: this.data.statbusUsers.length
      });
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
  public async refreshBaseData(client: any): Promise<BaseData> {
    this.status = 'loading';
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
  public async refreshHasStatisticalUnits(client: any): Promise<boolean> {
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
  private async fetchBaseData(client: SupabaseClient): Promise<BaseData> {
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
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
    
    if (process.env.NODE_ENV === 'development') {
      console.log('BaseDataStore client debug info:', clientDebugInfo);
    }
    
    try {
      console.log(`${typeof window !== 'undefined' ? 'Browser' : 'Server'}-side: Fetching base data`);
      
      // Fetch time contexts directly instead of using TimeContextStore
      // This avoids circular dependencies between stores
      console.log('Fetching time contexts directly...');
      let timeContextData = {
        timeContexts: [],
        defaultTimeContext: null
      };
      
      try {
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
        console.error('Exception fetching time contexts directly:', error);
      }
      
      // Fetch the rest of the data in parallel
      console.log('Fetching remaining base data...');
      const [
        { data: maybeStatDefinitions, error: statDefinitionsError },
        { data: maybeExternalIdentTypes, error: externalIdentTypesError },
        { data: maybeStatbusUsers, error: statbusUsersError },
        { data: maybeStatisticalUnit, error: statisticalUnitError }
      ] = await Promise.all([
        client.from("stat_definition_active").select(),
        client.from("external_ident_type_active").select(),
        client.from("user_with_role").select(),
        client.from("statistical_unit").select("*").limit(1)
      ]);
      
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
        hasStatisticalUnits: maybeStatisticalUnit?.length > 0
      });
      
      // Return the base data
      return {
        statDefinitions: maybeStatDefinitions || [],
        externalIdentTypes: maybeExternalIdentTypes || [],
        statbusUsers: maybeStatbusUsers || [],
        timeContexts: timeContextData.timeContexts || [],
        defaultTimeContext: timeContextData.defaultTimeContext,
        hasStatisticalUnits: maybeStatisticalUnit !== null && maybeStatisticalUnit.length > 0
      };
    } catch (error) {
      console.error('Exception fetching base data:', error);
      throw error;
    }
  }
}

// Export a singleton instance
export const baseDataStore = BaseDataStore.getInstance();
