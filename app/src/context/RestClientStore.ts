/**
 * RestClientStore - A singleton store for managing PostgREST client instances
 * 
 * This store manages PostgrestClient instances that connect to a PostgREST API server.
 * PostgREST is a standalone web server that turns your PostgreSQL database directly into a RESTful API.
 * 
 * This store ensures that client instances are:
 * 1. Created only once per context (server/browser)
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests for clients are deduplicated
 */

import { cache } from 'react';
import { Database } from "@/lib/database.types";
import { PostgrestClient } from "@supabase/postgrest-js";

type ClientType = 'server' | 'browser';
type ClientStatus = 'idle' | 'initializing' | 'ready' | 'error';

interface ClientInfo {
  client: PostgrestClient<Database> | null;
  status: ClientStatus;
  error: Error | null;
  initPromise: Promise<PostgrestClient<Database>> | null;
  lastInitTime: number;
}

class RestClientStore {
  private static instance: RestClientStore;
  // Only browser client state is stored now
  private clients: { browser: ClientInfo } = {
    browser: {
      client: null,
      status: 'idle',
      error: null,
      initPromise: null,
      lastInitTime: 0
    }
  };
  // TTL only relevant for browser client now
  private readonly BROWSER_CLIENT_TTL = 10 * 60 * 1000; // 10 minutes

  private constructor() {
    // Private constructor to enforce singleton pattern
  }

  public static getInstance(): RestClientStore {
    if (!RestClientStore.instance) {
      RestClientStore.instance = new RestClientStore();
    }
    return RestClientStore.instance;
  }

  /**
   * Get a PostgREST client for the specified context
   * This method deduplicates requests - multiple calls will share the same Promise
   */
  public async getRestClient(
    type: ClientType,
    serverRequestCookies?: import('next/dist/server/web/spec-extension/cookies').RequestCookies | Readonly<import('next/dist/server/web/spec-extension/cookies').RequestCookies>
  ): Promise<PostgrestClient<Database>> {
    if (type === 'server') {
      // Server client: Directly initialize. Caching is handled by the exported getServerRestClient.
      try {
        const client = await this.initializeClient('server', serverRequestCookies);
        // Log moved back to initializeClient to see raw initialization calls
        return client;
      } catch (error) {
        console.error(`Failed to initialize server client for request:`, error);
        throw error;
      }
    } else {
      // Browser client: Use caching and promise deduplication (existing logic)
      const now = Date.now();
      const clientInfo = this.clients.browser;

      // If client is already initialized and not expired, return it immediately
      if (clientInfo.status === 'ready' && clientInfo.client &&
          (now - clientInfo.lastInitTime < this.BROWSER_CLIENT_TTL)) {
        return clientInfo.client;
      }

      // If initialization is already in progress, return the existing promise
      if (clientInfo.status === 'initializing' && clientInfo.initPromise) {
        if (process.env.NODE_ENV === 'development') {
          console.log(`Reusing in-progress browser client initialization`);
        }
        return clientInfo.initPromise;
      }

      // Start a new initialization for the browser client
      clientInfo.status = 'initializing';
      clientInfo.initPromise = this.initializeClient('browser');

      try {
        const client = await clientInfo.initPromise;
        clientInfo.client = client;
        clientInfo.status = 'ready';
        clientInfo.lastInitTime = Date.now();
        clientInfo.error = null;

        if (process.env.NODE_ENV === 'development') {
          console.log(`Browser PostgREST client initialized`, { url: client.url });
        }

        return client;
      } catch (error) {
        clientInfo.status = 'error';
        clientInfo.error = error instanceof Error ? error : new Error(String(error));
        console.error(`Failed to initialize browser client:`, error);
        throw error;
      } finally {
        clientInfo.initPromise = null;
      }
    }
  }

  /**
   * Clear the cached browser client
   */
  public clearCache(type?: ClientType): void {
    // Only browser client uses caching now
    if (type === 'browser' || !type) {
       this.clients.browser = {
        client: null,
        status: 'idle',
        error: null,
        initPromise: null,
        lastInitTime: 0
      };
      if (process.env.NODE_ENV === 'development') {
        console.log(`Browser client cache cleared`);
      }
    }
    if (type === 'server' && process.env.NODE_ENV === 'development') {
       console.log(`Server client cache does not exist, clearCache ignored`);
    }
  }

  /**
   * Get debug information about the store state
   */
  public getDebugInfo(): Record<string, any> {
    // Server client state is no longer stored globally in the store
    const serverDebugInfo = {
      status: 'N/A (created per request)',
      lastInitTime: 'N/A',
      cacheAge: 'N/A',
      hasClient: 'N/A',
      hasInitPromise: 'N/A',
      hasError: 'N/A',
      errorMessage: 'N/A'
    };

    return {
      server: serverDebugInfo,
      browser: {
        status: this.clients.browser.status,
        lastInitTime: this.clients.browser.lastInitTime,
        cacheAge: this.clients.browser.lastInitTime ?
          Math.round((Date.now() - this.clients.browser.lastInitTime) / 1000) + 's' :
          'never',
        hasClient: !!this.clients.browser.client,
        hasInitPromise: !!this.clients.browser.initPromise,
        hasError: !!this.clients.browser.error,
        errorMessage: this.clients.browser.error?.message
      },
      browserCacheTTL: this.BROWSER_CLIENT_TTL / 1000 + 's',
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
  }

  /**
   * Internal method to initialize a client
   */
  private async initializeClient(
    type: ClientType,
    serverRequestCookies?: import('next/dist/server/web/spec-extension/cookies').RequestCookies | Readonly<import('next/dist/server/web/spec-extension/cookies').RequestCookies>
  ): Promise<PostgrestClient<Database>> {
    try {
      if (type === 'server') {
        // Create server client
        const apiBaseUrl = process.env.SERVER_REST_URL;
        if (!apiBaseUrl) {
          throw new Error('SERVER_REST_URL environment variable is not defined');
        }
        const apiUrl = apiBaseUrl + '/rest';

        // Add a timeout to prevent hanging
        const timeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error('Client initialization timed out')), 10000);
        });

        // Create a new PostgrestClient with auth headers from cookies
        const createClient = async () => {
          let headers: Record<string, string> = {
            'Content-Type': 'application/json',
          };
          let tokenValue: string | undefined = undefined;

          if (serverRequestCookies) {
            // Use provided cookies if available
            const tokenCookie = serverRequestCookies.get("statbus");
            tokenValue = tokenCookie?.value;
            if (process.env.NODE_ENV === 'development' && tokenValue) {
              console.log(`RestClientStore: Using token from provided serverRequestCookies for server client.`);
            }
          } else {
            // Fallback to next/headers
            try {
              const { cookies: nextCookiesFn } = await import("next/headers");
              const cookieStore = await nextCookiesFn();
              const tokenCookie = cookieStore.get("statbus");
              tokenValue = tokenCookie?.value;
              if (process.env.NODE_ENV === 'development' && tokenValue) {
                console.log(`RestClientStore: Using token from next/headers for server client.`);
              }
            } catch (error) {
              console.warn('RestClientStore: Could not import or use next/headers.cookies() for server client. Proceeding without Authorization header from this source.', error);
            }
          }

          if (tokenValue) {
            headers['Authorization'] = `Bearer ${tokenValue}`;
          } else {
            if (process.env.NODE_ENV === 'development') {
              console.log(`RestClientStore: No 'statbus' token found for server client. Client will be unauthenticated.`);
            }
          }
          
          return new PostgrestClient<Database>(apiUrl, { headers });
        };

        const client = await Promise.race([
          createClient(),
          timeoutPromise
        ]);
        // Log initialization attempt for server client
        if (process.env.NODE_ENV === 'development') {
          console.log(`Server PostgREST client initialized`, { url: client.url });
        }
        return client;
      } else {
        // Create browser client
        const apiBaseUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL;
        
        if (!apiBaseUrl) {
          throw new Error('NEXT_PUBLIC_BROWSER_REST_URL environment variable is not defined');
        }
        
        const apiUrl = apiBaseUrl + '/rest';
        
        // Browser client initialization is logged at the end with timing information
        
        // Add a timeout to prevent hanging
        const timeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error('Client initialization timed out')), 10000);
        });
        
        // Create a new PostgrestClient with fetch wrapper for auth
        const createClient = async () => {
          if (!apiUrl) {
            throw new Error('API URL is undefined or empty');
          }
          
          // For browser clients, we need to ensure the PostgREST API URL is properly set
          // The PostgrestClient constructor doesn't handle relative URLs correctly
          const client = new PostgrestClient<Database>(apiUrl, {
            headers: {
              'Content-Type': 'application/json',
            },
            fetch: this.fetchWithAuthRefresh.bind(this) as typeof fetch,
          });
          
          // Force the URL to be the relative path for browser clients
          if (type === 'browser') {
            // @ts-ignore - We need to modify the private url property
            client.url = apiUrl;
          }          
          return client;
        };
        
        // Race the client creation against the timeout
        return await Promise.race([
          createClient(),
          timeoutPromise
        ]);
      }
    } catch (error) {
      console.error(`Error initializing ${type} client:`, error);
      throw error;
    }
  }
  
  /**
   * Custom fetch function that handles token refresh automatically
   * If a request returns 401 Unauthorized, it will attempt to refresh the token
   * and retry the original request
   */
  public async fetchWithAuthRefresh(
    url: string, 
    options: RequestInit = {}
  ): Promise<Response> {
    // Log request in development mode
    if (process.env.NODE_ENV === 'development' && !url.includes('/auth/token')) {
      console.debug(`Request to: ${url}`);
    }
        
    // Get auth token from cookies
    let headers: Record<string, string> = {
      'Content-Type': typeof options.headers === 'object' && options.headers 
        ? (options.headers as Record<string, string>)['Content-Type'] || 'application/json'
        : 'application/json',
      'Accept': typeof options.headers === 'object' && options.headers
        ? (options.headers as Record<string, string>)['Accept'] || 'application/json'
        : 'application/json',
    };
    
    // Add auth token from cookies
    try {
      if (typeof window === 'undefined') {
        // Server-side: Get token from next/headers
        const { cookies } = require('next/headers');
        const cookieStore = await cookies();
        const token = cookieStore.get("statbus");
        
        if (token) {
          headers['Authorization'] = `Bearer ${token.value}`;
        }
      } else {
        // Browser-side: Cookies will be sent automatically with credentials: 'include'
        // No need to manually set Authorization header
      }
    } catch (error) {
      console.error('Error getting auth token from cookies:', error);
    }
    
    // Merge with existing headers
    if (options.headers) {
      headers = { ...headers, ...(options.headers as Record<string, string>) };
    }
    
    // First attempt with current token
    let response = await fetch(url, {
      ...options,
      credentials: 'include', // Always include cookies
      headers
    });
    
    // If we get a 401 Unauthorized, try to refresh the token *only on the browser*
    // Server-side 401s should typically be handled by initial auth checks or middleware
    if (response.status === 401 && typeof window !== 'undefined') {
      try {
        // Import the AuthStore dynamically to avoid circular dependencies
        const { authStore } = await import('@/context/AuthStore');
        
        // Try to refresh the token
        const refreshResult = await authStore.refreshTokenIfNeeded();
        const refreshResponse = { error: !refreshResult.success };
        
        if (!refreshResponse.error) {
          // Retry the original request with the new token
          response = await fetch(url, {
            ...options,
            credentials: 'include',
            headers: {
              ...options.headers,
              'Content-Type': typeof options.headers === 'object' && options.headers 
                ? (options.headers as Record<string, string>)['Content-Type'] || 'application/json'
                : 'application/json',
              'Accept': typeof options.headers === 'object' && options.headers
                ? (options.headers as Record<string, string>)['Accept'] || 'application/json'
                : 'application/json',
            }
          });
        } else {
          // If refresh failed, dispatch an event for the auth context to handle
          if (typeof window !== 'undefined') {
            window.dispatchEvent(new CustomEvent('auth:logout', { 
              detail: { reason: 'refresh_failed' } 
            }));
          }
        }
      } catch (error) {
        console.error('Error refreshing token:', error);
        // Dispatch an event for the auth context to handle
        if (typeof window !== 'undefined') {
          window.dispatchEvent(new CustomEvent('auth:logout', { 
            detail: { reason: 'refresh_error', error } 
          }));
        }
      }
    }
    
    return response;
  }
}

// Export a singleton instance
export const clientStore = RestClientStore.getInstance();

// Export convenience methods for accessing PostgREST clients
// Use React.cache on the exported function to memoize per request
export const getServerRestClient = cache(
  async (
    requestContext?: { cookies: import('next/dist/server/web/spec-extension/cookies').RequestCookies | Readonly<import('next/dist/server/web/spec-extension/cookies').RequestCookies> }
  ): Promise<PostgrestClient<Database>> => {
    return clientStore.getRestClient('server', requestContext?.cookies);
  }
);

export async function getBrowserRestClient(): Promise<PostgrestClient<Database>> {
  return clientStore.getRestClient('browser');
}

// Export the fetch function with auth refresh handling
export async function fetchWithAuth(
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  return clientStore.fetchWithAuthRefresh(url, options);
}

/**
 * Get a client that automatically selects between server and browser client
 * based on the current environment
 */
export async function getRestClient(): Promise<PostgrestClient<Database>> {
  // Use the cached getServerRestClient on the server side
  return typeof window === 'undefined'
    ? await getServerRestClient()
    : await clientStore.getRestClient('browser');
}
