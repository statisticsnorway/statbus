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
import { getServerRestClient, getBrowserRestClient, getRestClient } from "./RestClientStore";
export interface BaseData {
  statDefinitions: Tables<"stat_definition_active">[];
  externalIdentTypes: Tables<"external_ident_type_active">[];
  statbusUsers: Tables<"user">[];
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

  // Worker Status State (Importing, Deriving Units, Deriving Reports)
  private isImporting: boolean | null = null;
  private isDerivingUnits: boolean | null = null;
  private isDerivingReports: boolean | null = null;
  private workerStatusLoading: boolean = false;
  private workerStatusError: string | null = null;
  private lastWorkerStatusFetchTime: number = 0;
  private readonly WORKER_STATUS_CACHE_TTL = 10 * 1000; // 10 seconds cache for status

  // Listener callback registry for worker status changes
  private workerStatusListeners: Set<() => void> = new Set();

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

    // Get client from RestClientStore if not provided
    if (!client) {
      try {
        client = await getRestClient();
      } catch (error) {
        console.error('Failed to get client from RestClientStore:', error);
        throw error;
      }
    }
    
    // If data is already loaded and cache is still valid, return it immediately
    if (this.status === 'success' && now - this.lastFetchTime < this.CACHE_TTL) {
      return this.data;
    }
    
    // If a fetch is already in progress, return the existing promise
    if (this.status === 'loading' && this.fetchPromise) {
      // console.log('Reusing in-progress base data fetch');
      return this.fetchPromise;
    }
    
    this.status = 'loading';
    this.fetchPromise = this.fetchBaseData(client);
    
    try {
      const result = await this.fetchPromise;
      this.data = result;
      this.status = 'success';
      this.lastFetchTime = Date.now();
      // console.log('Base data fetch completed successfully', {
      //   statDefinitionsCount: result.statDefinitions.length,
      //   externalIdentTypesCount: result.externalIdentTypes.length,
      //   statbusUsersCount: result.statbusUsers.length,
      //   hasStatisticalUnits: result.hasStatisticalUnits
      // });
      return result;
    } catch (error) {
      this.status = 'error';
      console.error('Failed to fetch base data:', error);
      
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
   * Refresh a specific worker status function, or all if functionName is omitted.
   */
  public async refreshWorkerStatus(
    functionName?: string, // Made optional
    client?: PostgrestClient<Database>
  ): Promise<{ isImporting: boolean | null, isDerivingUnits: boolean | null, isDerivingReports: boolean | null }> {
    const now = Date.now();
    // Basic throttling/caching
    // If a specific function is requested and it's loading, or if a general refresh is ongoing.
    const logFunctionName = functionName || "all";
    if (this.workerStatusLoading && now - this.lastWorkerStatusFetchTime < 5000) { 
        // console.log(`Worker status refresh for ${logFunctionName} already in progress or recently completed.`);
        return { isImporting: this.isImporting, isDerivingUnits: this.isDerivingUnits, isDerivingReports: this.isDerivingReports };
    }

    this.workerStatusLoading = true;
    this.workerStatusError = null;
    this.lastWorkerStatusFetchTime = now;

    // Get client if not provided
    let currentClient = client;
    if (!currentClient) {
      try {
        currentClient = await getRestClient();
      } catch (error) {
        console.error('Failed to get client for worker status refresh:', error);
        this.workerStatusError = "Failed to get API client";
        this.workerStatusLoading = false;
        return { isImporting: this.isImporting, isDerivingUnits: this.isDerivingUnits, isDerivingReports: this.isDerivingReports };
      }
    }

    if (!currentClient || typeof currentClient.rpc !== 'function') {
      console.error('Invalid client provided to refreshWorkerStatus');
      this.workerStatusError = "Invalid API client";
      this.workerStatusLoading = false;
      return { isImporting: this.isImporting, isDerivingUnits: this.isDerivingUnits, isDerivingReports: this.isDerivingReports };
    }

    try {
      const refreshSingleStatus = async (name: 'is_importing' | 'is_deriving_statistical_units' | 'is_deriving_reports') => {
        if (!currentClient) return; // Should have been checked already
        const rpcResult = await currentClient.rpc(name);
        if (rpcResult.error) throw new Error(`Status error for ${name}: ${rpcResult.error.message}`);
        
        if (name === 'is_importing') this.isImporting = rpcResult.data ?? null;
        else if (name === 'is_deriving_statistical_units') this.isDerivingUnits = rpcResult.data ?? null;
        else if (name === 'is_deriving_reports') this.isDerivingReports = rpcResult.data ?? null;
        // console.log(`Worker status refreshed: ${name}=${rpcResult.data ?? null}`);
      };

      if (functionName) {
        if (functionName === 'is_importing' || functionName === 'is_deriving_statistical_units' || functionName === 'is_deriving_reports') {
          await refreshSingleStatus(functionName);
        } else {
          console.warn(`refreshWorkerStatus called with unknown functionName: ${functionName}`);
        }
      } else {
        // console.log("Refreshing all worker statuses...");
        await Promise.all([
          refreshSingleStatus('is_importing'),
          refreshSingleStatus('is_deriving_statistical_units'),
          refreshSingleStatus('is_deriving_reports')
        ]);
        // console.log("All worker statuses refreshed.");
      }
      
      return { 
        isImporting: this.isImporting, 
        isDerivingUnits: this.isDerivingUnits, 
        isDerivingReports: this.isDerivingReports 
      };

    } catch (error: any) {
      const logCtx = functionName || "all";
      console.error(`Failed to refresh worker status for ${logCtx}:`, error);
      this.workerStatusError = error.message || `Unknown error fetching worker status for ${logCtx}`;
      
      // If a specific function failed, nullify it. If 'all' failed, nullify all.
      if (functionName === 'is_importing' || !functionName) this.isImporting = null;
      if (functionName === 'is_deriving_statistical_units' || !functionName) this.isDerivingUnits = null;
      if (functionName === 'is_deriving_reports' || !functionName) this.isDerivingReports = null;
      
      this.notifyWorkerStatusListeners();
      return { isImporting: this.isImporting, isDerivingUnits: this.isDerivingUnits, isDerivingReports: this.isDerivingReports };

    } finally {
      this.workerStatusLoading = false;
      this.notifyWorkerStatusListeners();
    }
  }


  // Method to notify listeners
  private notifyWorkerStatusListeners() {
    this.workerStatusListeners.forEach(listener => listener());
  }

  // Method for components to subscribe
  public subscribeWorkerStatus(listener: () => void): () => void {
    this.workerStatusListeners.add(listener);
    // Return an unsubscribe function
    return () => {
      this.workerStatusListeners.delete(listener);
    };
  }

  /**
   * Get the current cached worker status
   */
  public getWorkerStatus(): { isImporting: boolean | null, isDerivingUnits: boolean | null, isDerivingReports: boolean | null, isLoading: boolean, error: string | null } {
    // Check cache validity - might force a refresh if stale, but keep it simple for now
    // const now = Date.now();
    // if (now - this.lastWorkerStatusFetchTime > this.WORKER_STATUS_CACHE_TTL && !this.workerStatusLoading) {
    //   console.log("Worker status cache stale, triggering background refresh.");
    //   this.refreshWorkerStatus(); // Trigger refresh in background
    // }
    return {
      isImporting: this.isImporting,
      isDerivingUnits: this.isDerivingUnits,
      isDerivingReports: this.isDerivingReports,
      isLoading: this.workerStatusLoading,
      error: this.workerStatusError
    };
  }


  /**
   * Force refresh the base data
   */
  public async refreshBaseData(client?: PostgrestClient<Database>): Promise<BaseData> {
    this.status = 'loading';
    
    // Get client from RestClientStore if not provided
    if (!client) {
      try {
        client = await getRestClient();
      } catch (error) {
        console.error('Failed to get client from RestClientStore:', error);
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
    // Get client from RestClientStore if not provided
    if (!client) {
      try {
        client = await getRestClient();
      } catch (error) {
        console.error('Failed to get client from RestClientStore:', error);
        return false;
      }
    }
    
    if (!client || typeof client.from !== 'function') {
      console.error('Invalid client provided to refreshHasStatisticalUnits');
      return false;
    }

    try {
      const { data: maybeStatisticalUnit } = await client.from("statistical_unit").select("*").limit(1);
      const hasStatisticalUnits = maybeStatisticalUnit !== null && maybeStatisticalUnit.length > 0;
      
      // Update the cached data
      this.data.hasStatisticalUnits = hasStatisticalUnits;
      
      // console.log(`Statistical units check: ${hasStatisticalUnits ? 'Found' : 'None found'}`);
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
      timeContextsCount: this.data.timeContexts.length,
      hasDefaultTimeContext: !!this.data.defaultTimeContext,
      hasStatisticalUnits: this.data.hasStatisticalUnits,
      cacheTTL: this.CACHE_TTL / 1000 + 's',
      workerStatus: this.getWorkerStatus(),
      lastWorkerStatusFetchTime: this.lastWorkerStatusFetchTime,
      workerStatusCacheAge: this.lastWorkerStatusFetchTime ? Math.round((Date.now() - this.lastWorkerStatusFetchTime) / 1000) + 's' : 'never',
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
      hasAuth: !!(client as any).auth,
      url: client.url,
      type: typeof window !== 'undefined' ? 'browser' : 'server'
    };
    
    // console.log('BaseDataStore client debug info:', clientDebugInfo);
    
    try {
      // Fetch all the data in parallel using Promise.all
      const fetchStatDefinitions = async () => {
        try {
          const result = await client.from("stat_definition_active").select();
          return { data: result.data, error: result.error };
        } catch (error) {
          console.error('Exception fetching stat_definition_active:', error);
          return { data: null, error };
        }
      };
      
      const fetchExternalIdentTypes = async () => {
        try {
          const result = await client.from("external_ident_type_active").select();
          return { data: result.data, error: result.error };
        } catch (error) {
          console.error('Exception fetching external_ident_type_active:', error);
          return { data: null, error };
        }
      };
      
      const fetchStatbusUsers = async () => {
        try {
          const result = await client.from("user").select();
          return { data: result.data, error: result.error };
        } catch (error) {
          console.error('Exception fetching user:', error);
          return { data: null, error };
        }
      };
      
      const fetchStatisticalUnit = async () => {
        try {
          const result = await client.from("statistical_unit").select("*").limit(1);
          return { data: result.data, error: result.error };
        } catch (error) {
          console.error('Exception fetching statistical_unit:', error);
          return { data: null, error };
        }
      };
      
      const fetchTimeContexts = async () => {
        try {
          const result = await client.from("time_context").select("*");
          return { data: result.data, error: result.error };
        } catch (error) {
          console.error('Exception fetching time_context:', error);
          return { data: null, error };
        }
      };
      
      const [
        statDefinitionsResult,
        externalIdentTypesResult,
        statbusUsersResult,
        statisticalUnitResult,
        timeContextsResult
      ] = await Promise.all([
        fetchStatDefinitions(),
        fetchExternalIdentTypes(),
        fetchStatbusUsers(),
        fetchStatisticalUnit(),
        fetchTimeContexts()
      ]);
      
      const maybeStatDefinitions = statDefinitionsResult.data;
      const statDefinitionsError = statDefinitionsResult.error;
      
      const maybeExternalIdentTypes = externalIdentTypesResult.data;
      const externalIdentTypesError = externalIdentTypesResult.error;
      
      const maybeStatbusUsers = statbusUsersResult.data;
      const statbusUsersError = statbusUsersResult.error;
      
      const maybeStatisticalUnit = statisticalUnitResult.data;
      const statisticalUnitError = statisticalUnitResult.error;
      
      const maybeTimeContexts = timeContextsResult.data;
      const timeContextsError = timeContextsResult.error;
      
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
      if (timeContextsError) {
        console.error('Error fetching time contexts:', timeContextsError);
      }
      
      let timeContextData: {
        timeContexts: Tables<"time_context">[];
        defaultTimeContext: Tables<"time_context"> | null;
      } = {
        timeContexts: [],
        defaultTimeContext: null
      };
      
      if (maybeTimeContexts && maybeTimeContexts.length > 0) {
        let chosenDefault: Tables<"time_context"> | null = null;

        // The time_context view is pre-ordered, so the first entry is the default.
        if (maybeTimeContexts.length > 0) {
          chosenDefault = maybeTimeContexts[0] as Tables<"time_context">;
        }
        
        timeContextData = {
          timeContexts: maybeTimeContexts as Tables<"time_context">[], // Keep original order for the main list
          defaultTimeContext: chosenDefault // This can be null if maybeTimeContexts is empty
        };
      }
      
      // console.log('Base data fetch results:', {
      //   statDefinitions: maybeStatDefinitions?.length || 0,
      //   externalIdentTypes: maybeExternalIdentTypes?.length || 0,
      //   statbusUsers: maybeStatbusUsers?.length || 0,
      //   timeContexts: timeContextData.timeContexts?.length || 0,
      //   hasStatisticalUnits: maybeStatisticalUnit !== null && Array.isArray(maybeStatisticalUnit) && maybeStatisticalUnit.length > 0
      // });
      
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
