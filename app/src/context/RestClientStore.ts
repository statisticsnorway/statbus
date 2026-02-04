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
  private refreshPromise: Promise<boolean> | null = null; // Shared promise for token refresh

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
    type: ClientType
  ): Promise<PostgrestClient<Database>> {
    if (type === 'server') {
      // Server client: Directly initialize. Caching is handled by the exported getServerRestClient.
      try {
        const client = await this.initializeClient('server');
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
    }
    // Server client cache is not managed here, so no log for type === 'server'
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
    type: ClientType
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
          const postgrestClientHeaders: Record<string, string> = {
            'Content-Type': 'application/json',
          };
          let tokenValue: string | undefined = undefined;

          // On server, always try to get cookies and forward them.
          try {
            const { cookies: getNextCookies } = await import('next/headers');
            const currentCookies = await getNextCookies();
            const tokenCookie = currentCookies.get("statbus");
            tokenValue = tokenCookie?.value;

            // Forward the entire cookie header for the SQL function to inspect.
            const rawCookieHeader = currentCookies.toString();
            if (rawCookieHeader) {
              postgrestClientHeaders['Cookie'] = rawCookieHeader;
            }

          } catch (error) {
            console.warn('RestClientStore: Could not import or use next/headers.cookies() for server client. Proceeding without auth headers.', error);
          }

          if (tokenValue) {
            postgrestClientHeaders['Authorization'] = `Bearer ${tokenValue}`;
          } else {
          }

          // Add X-Forwarded-* headers from the incoming request
          try {
            // Dynamically import headers when in server side mode
            const { headers: getNextHeaders } = await import('next/headers');
            const incomingHeaders = await getNextHeaders();
            
            const xForwardedHost = incomingHeaders.get('x-forwarded-host');
            if (xForwardedHost) {
              postgrestClientHeaders['X-Forwarded-Host'] = xForwardedHost;
            }
            
            const xForwardedProto = incomingHeaders.get('x-forwarded-proto');
            if (xForwardedProto) {
              postgrestClientHeaders['X-Forwarded-Proto'] = xForwardedProto;
            }
            
            const xForwardedFor = incomingHeaders.get('x-forwarded-for');
            if (xForwardedFor) {
              postgrestClientHeaders['X-Forwarded-For'] = xForwardedFor;
            }
            
          } catch (error) {
            console.warn('RestClientStore: Could not read incoming headers using next/headers. X-Forwarded-* headers will not be set for PostgrestClient.', error);
          }
          
          return new PostgrestClient<Database>(apiUrl, { headers: postgrestClientHeaders });
        };

        const client = await Promise.race([
          createClient(),
          timeoutPromise
        ]);
        // Log initialization attempt for server client
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
    // This function is now a simple fetch wrapper. The complex logic for handling
    // 401 errors and triggering a token refresh has been removed and centralized
    // into the declarative authMachine. This eliminates the race condition where
    // both this fetch wrapper and the auth machine would try to refresh the token.

    const headers = new Headers(options.headers);

    const fetchOptions = {
      ...options,
      credentials: 'include' as RequestCredentials,
      headers,
    };

    try {
      return await fetch(url, fetchOptions);
    } catch (error: any) {
      if (error.name !== 'AbortError') {
        console.error(`[RestClientStore.fetchWithAuthRefresh] Fetch failed for URL: ${url}`, error);
      }
      throw error;
    }
  }
}

// Export a singleton instance
export const clientStore = RestClientStore.getInstance();

// Export convenience methods for accessing PostgREST clients
// Use React.cache on the exported function to memoize per request
export const getServerRestClient = cache(
  async (): Promise<PostgrestClient<Database>> => {
    return clientStore.getRestClient('server');
  }
);

export async function getBrowserRestClient(): Promise<PostgrestClient<Database>> {
  return clientStore.getRestClient('browser');
}

// Export the fetch function with auth refresh handling
export async function fetchWithAuthRefresh( // Renamed for clarity and consistency
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  if (typeof window === 'undefined') {
    // This function's refresh logic is browser-only.
    // For server-side authenticated calls, prefer using `fetchWithAuth`.
    console.warn(
      "fetchWithAuthRefresh was called on the server-side. Its refresh logic is browser-only. " +
      "Consider using `fetchWithAuth` for server-side calls."
    );
    // It will still proceed and work (auth header added, no refresh attempted), but the name is misleading.
  }
  return clientStore.fetchWithAuthRefresh(url, options);
}

/**
 * Performs a fetch request with authentication headers, intended for server-side use.
 * It retrieves necessary headers (including Authorization and X-Forwarded-*)
 * from `getServerRestClient` and merges them with any headers provided in `options`.
 * This function does NOT implement token refresh logic.
 */
export async function fetchWithAuth(url: string, options: RequestInit = {}): Promise<Response> {
  if (typeof window !== 'undefined') {
    // This function is intended for server-side use.
    // For browser-side calls that need auth and refresh, use fetchWithAuthRefresh.
    console.error(
      "fetchWithAuth was called on the client-side. This is not its intended use. " +
      "Use fetchWithAuthRefresh for browser-side calls needing refresh, or global fetch with " +
      "credentials: 'include' for simple authenticated browser fetches."
    );
    // Fallback to clientStore.fetchWithAuthRefresh if misused on client, though this indicates an architectural issue.
    return clientStore.fetchWithAuthRefresh(url, options);
  }

  // Server-side execution
  const client = await getServerRestClient(); // Provides base headers including Auth and X-Forwarded-*
  
  // Start with base headers from the server client (Auth, X-Forwarded-*, default Content-Type)
  const combinedHeaders = new Headers(client.headers);

  // Apply/override with headers from options
  if (options.headers) {
    const incomingHeaders = new Headers(options.headers);
    incomingHeaders.forEach((value, key) => {
      combinedHeaders.set(key, value);
    });
  }
  
  const finalOptions: RequestInit = {
    ...options,
    headers: combinedHeaders,
  };
  
  // The `url` parameter is assumed to be a full URL.
  return fetch(url, finalOptions);
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
