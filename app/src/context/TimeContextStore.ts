/**
 * TimeContextStore - A singleton store for managing time context data
 * 
 * This store ensures that time context data is:
 * 1. Fetched only once per session
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

import { Tables } from "@/lib/database.types";
import { PostgrestClient } from "@supabase/postgrest-js";

type TimeContextData = {
  timeContexts: Tables<"time_context">[];
  defaultTimeContext: Tables<"time_context"> | null;
};

type FetchStatus = 'idle' | 'loading' | 'success' | 'error';

class TimeContextStore {
  private static instance: TimeContextStore;
  private data: TimeContextData = {
    timeContexts: [],
    defaultTimeContext: null,
  };
  private status: FetchStatus = 'idle';
  private fetchPromise: Promise<TimeContextData> | null = null;
  private lastFetchTime: number = 0;
  private readonly CACHE_TTL = 5 * 60 * 1000; // 5 minutes

  private constructor() {
    // Private constructor to enforce singleton pattern
  }

  public static getInstance(): TimeContextStore {
    if (!TimeContextStore.instance) {
      TimeContextStore.instance = new TimeContextStore();
    }
    return TimeContextStore.instance;
  }

  /**
   * Get time context data, fetching from API if needed
   * This method deduplicates requests - multiple calls will share the same Promise
   */
  public async getTimeContextData(client: PostgrestClient): Promise<TimeContextData> {
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
        // Client-side - use AuthStore directly
        authenticated = await authStore.isAuthenticated();
      }
      
      if (!authenticated) {
        console.log('Not authenticated, returning empty time context data');
        return {
          timeContexts: [],
          defaultTimeContext: null,
        };
      }
    } catch (error) {
      console.error('Authentication check failed in TimeContextStore:', error);
      // Continue with the request, but log the error
    }
    
    // If data is already loaded and cache is still valid, return it immediately
    if (this.status === 'success' && now - this.lastFetchTime < this.CACHE_TTL) {
      return this.data;
    }
    
    // If a fetch is already in progress, return the existing promise
    if (this.status === 'loading' && this.fetchPromise) {
      console.log('Reusing in-progress time context fetch');
      return this.fetchPromise;
    }
    
    // Start a new fetch
    console.log('Starting new time context fetch');
    this.status = 'loading';
    this.fetchPromise = this.fetchTimeContextData(client);
    
    try {
      const result = await this.fetchPromise;
      this.data = result;
      this.status = 'success';
      this.lastFetchTime = Date.now();
      console.log('Time context fetch completed successfully', {
        contextCount: result.timeContexts.length,
        hasDefault: !!result.defaultTimeContext
      });
      return result;
    } catch (error) {
      this.status = 'error';
      console.error('Failed to fetch time context data:', error);
      
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
   * Force refresh the time context data
   */
  public async refreshTimeContextData(client: PostgrestClient): Promise<TimeContextData> {
    this.status = 'loading';
    this.fetchPromise = this.fetchTimeContextData(client);
    
    try {
      const result = await this.fetchPromise;
      this.data = result;
      this.status = 'success';
      this.lastFetchTime = Date.now();
      return result;
    } catch (error) {
      this.status = 'error';
      console.error('Failed to refresh time context data:', error);
      throw error;
    } finally {
      this.fetchPromise = null;
    }
  }

  /**
   * Clear the cached time context data
   */
  public clearCache(): void {
    this.data = {
      timeContexts: [],
      defaultTimeContext: null,
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
      contextCount: this.data.timeContexts.length,
      hasDefaultContext: !!this.data.defaultTimeContext,
      cacheTTL: this.CACHE_TTL / 1000 + 's',
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
  }

  /**
   * Internal method to fetch time context data from API
   */
  private async fetchTimeContextData(client: PostgrestClient): Promise<TimeContextData> {
    if (!client || typeof client.from !== 'function') {
      console.error('Invalid client provided to fetchTimeContextData');
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
      console.log('TimeContextStore client debug info:', clientDebugInfo);
    }
    
    try {
      // Always use the client directly for consistency
      // This is the most reliable approach that works in both client and server contexts
      console.log(`${typeof window !== 'undefined' ? 'Browser' : 'Server'}-side: Using direct client query for time contexts`);
            
      // Execute the query with detailed error handling
      const result = await client.from("time_context").select("*");
      const { data: timeContexts, error, status, statusText } = result;
      
      // Log the complete response for debugging only in development
      if (process.env.NODE_ENV === 'development') {
        console.log('Time context query response:', {
          status,
          statusText,
          hasError: !!error,
          errorMessage: error?.message,
          errorCode: error?.code,
          dataCount: timeContexts?.length || 0
        });
      }
      
      if (error) {
        console.error('Error fetching time contexts with client:', error);
        // Add more context to the error
        const enhancedError = new Error(`Time context fetch failed: ${error.message} (Code: ${error.code})`);
        (enhancedError as any).originalError = error;
        (enhancedError as any).clientInfo = clientDebugInfo;
        throw enhancedError;
      }
      
      if (!timeContexts || timeContexts.length === 0) {
        console.warn('No time contexts found');
        return {
          timeContexts: [],
          defaultTimeContext: null,
        };
      }
      
      console.log(`Successfully fetched ${timeContexts.length} time contexts`);
      
      return {
        timeContexts,
        defaultTimeContext: timeContexts[0],
      };
    } catch (error) {
      console.error('Exception fetching time contexts:', error);
      throw error;
    }
  }
}

// Export a singleton instance
export const timeContextStore = TimeContextStore.getInstance();
