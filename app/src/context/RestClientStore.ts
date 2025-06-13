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

        if (process.env.NEXT_PUBLIC_DEBUG === 'true') { // Browser-side, use NEXT_PUBLIC_DEBUG
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
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') { // Browser-side, use NEXT_PUBLIC_DEBUG
        console.log(`Browser client cache cleared`);
      }
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
          const postgrestClientHeaders: Record<string, string> = {
            'Content-Type': 'application/json',
          };
          let tokenValue: string | undefined = undefined;

          if (serverRequestCookies) {
            // Use provided cookies if available
            const tokenCookie = serverRequestCookies.get("statbus");
            tokenValue = tokenCookie?.value;
            if (process.env.DEBUG === 'true' && tokenValue) { // Server-side, use DEBUG
              console.log(`RestClientStore: Using token from provided serverRequestCookies for server client's Authorization header.`);
            }
          } else {
            // Fallback to next/headers for cookies
            try {
              const { cookies: getNextCookies } = await import('next/headers');
              const currentCookies = await getNextCookies();
              const tokenCookie = currentCookies.get("statbus");

              tokenValue = tokenCookie?.value;
              if (process.env.DEBUG === 'true' && tokenValue) { // Server-side, use DEBUG
                console.log(`RestClientStore: Using token from next/headers.cookies() for server client's Authorization header.`);
              }
            } catch (error) {
              console.warn('RestClientStore: Could not import or use next/headers.cookies() for server client. Proceeding without Authorization header from this source.', error);
            }
          }

          if (tokenValue) {
            postgrestClientHeaders['Authorization'] = `Bearer ${tokenValue}`;
          } else {
            if (process.env.DEBUG === 'true') { // Server-side, use DEBUG
              console.log(`RestClientStore: No 'statbus' token found for server client. Client will be unauthenticated for Authorization header.`);
            }
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
            
            if (process.env.DEBUG === 'true') {
              console.log(`RestClientStore: Server client PostgREST headers prepared: ${JSON.stringify(postgrestClientHeaders)}`);
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
        if (process.env.DEBUG === 'true') { // Server-side, use DEBUG
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
    // const callStack = new Error().stack?.split('\n').slice(2, 5).join('\n'); // Get a snippet of the call stack
    if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      // console.log(`[RestClientStore.fetchWithAuthRefresh ENTRY] URL: ${url}, Options:`, JSON.stringify(options), `\nCaller: ${callStack}`);
      console.debug(`[RestClientStore.fetchWithAuthRefresh] URL: ${url}`); // Keep a less verbose debug log
    }

    // Special handling for login/logout to ensure Set-Cookie is processed correctly by the browser.
    // These calls manage their own session setup/teardown and don't need the 401 refresh logic.
    // They also need the most direct path for Set-Cookie headers to be effective.
    if (url.endsWith("/rest/rpc/login") || url.endsWith("/rest/rpc/logout")) {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.debug(`[RestClientStore.fetchWithAuthRefresh SIMPLIFIED_PATH] For ${url}.`);
      }
      const fetchOptions = {
        ...options,
        credentials: 'include' as RequestCredentials
      };
      // if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
      //   console.log(`[RestClientStore.fetchWithAuthRefresh SIMPLIFIED_PATH] Native fetch options for ${url}:`, JSON.stringify(fetchOptions));
      // }
      const response = await fetch(url, fetchOptions);
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        const setCookieHeader = response.headers.get('Set-Cookie');
        console.debug(`[RestClientStore.fetchWithAuthRefresh SIMPLIFIED_PATH] Response for ${url}: Status ${response.status}. Set-Cookie present: ${!!setCookieHeader}`);
      }
      return response;
    }
        
    // Original logic for other API calls (data fetching, etc.):
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
        const { cookies: getNextCookies } = require('next/headers');
        const cookieStore = getNextCookies(); // Corrected: cookies() is not async
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
    const initialFetchOptions = {
      ...options,
      credentials: 'include' as RequestCredentials,
      headers
    };
    // if (process.env.NODE_ENV === 'development') {
    //   console.log(`[RestClientStore.fetchWithAuthRefresh MAIN_PATH_INITIAL_ATTEMPT] Native fetch options for ${url}:`, JSON.stringify(initialFetchOptions));
    // }
    let response = await fetch(url, initialFetchOptions);
    // if (process.env.NODE_ENV === 'development') {
    //   console.log(`[RestClientStore.fetchWithAuthRefresh MAIN_PATH_INITIAL_ATTEMPT] Response for ${url}: Status ${response.status}`);
    //   const responseHeaders: Record<string, string> = {};
    //   response.headers.forEach((value, key) => { responseHeaders[key] = value; });
    //   console.log(`[RestClientStore.fetchWithAuthRefresh MAIN_PATH_INITIAL_ATTEMPT] Response headers for ${url}:`, JSON.stringify(responseHeaders));
    // }
    
    // If we get a 401 Unauthorized, try to refresh the token *only on the browser*
    // Server-side 401s should typically be handled by initial auth checks or middleware
    if (response.status === 401 && typeof window !== 'undefined') {
      if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
        console.log(`[RestClientStore.fetchWithAuthRefresh] Received 401 for URL: ${url}. Checking for ongoing refresh.`);
      }

      if (!this.refreshPromise) {
        // No refresh in progress, so this instance will initiate it.
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log(`[RestClientStore.fetchWithAuthRefresh] No refresh in progress. Initiating new token refresh (triggered by URL: ${url}).`);
        }
        this.refreshPromise = (async () => {
          try {
            const refreshApiUrl = `${process.env.NEXT_PUBLIC_BROWSER_REST_URL || ''}/rest/rpc/refresh`;
            const refreshFetchOptions: RequestInit = { // Explicitly type for clarity
              method: 'POST' as const,
              headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
              credentials: 'include' as RequestCredentials // Crucial for sending cookies
            };

            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              console.log(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Current document.cookie before calling ${refreshApiUrl}:`, document.cookie);
              console.log(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Fetch options for ${refreshApiUrl}:`, JSON.stringify(refreshFetchOptions));
            }
            
            const refreshApiResponse = await fetch(refreshApiUrl, refreshFetchOptions);

            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              // Note: We cannot directly read Set-Cookie headers from the response in JS.
              // Logging document.cookie *after* this call (if it were synchronous and cookies were set) would show changes.
              // However, the browser handles Set-Cookie automatically.
              const allRefreshResponseHeaders: Record<string, string> = {};
              refreshApiResponse.headers.forEach((value, key) => { allRefreshResponseHeaders[key] = value; });
              console.log(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Response from ${refreshApiUrl}: Status ${refreshApiResponse.status}, Headers:`, JSON.stringify(allRefreshResponseHeaders));
              
              try {
                const responseBodyText = await refreshApiResponse.clone().text(); // Clone to read body without consuming
                console.log(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Response body from ${refreshApiUrl}:`, responseBodyText);
              } catch (e) {
                // console.error(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Error reading response body from ${refreshApiUrl}:`, e);
                // Keep original debug log if body reading fails for some reason
                console.debug(`[RestClientStore.fetchWithAuthRefresh REFRESH_ATTEMPT] Original console.debug: Response for ${refreshApiUrl}: Status ${refreshApiResponse.status}. Error reading body: ${e}`);
              }
            }

            if (!refreshApiResponse.ok) {
              let errorDetail = `Refresh RPC failed with status: ${refreshApiResponse.status}`;
              try { const errorJson = await refreshApiResponse.json(); errorDetail = errorJson.message || errorDetail; } catch (e) { /* ignore */ }
              console.error(`RestClientStore.fetchWithAuthRefresh: Token refresh RPC failed: ${errorDetail}`);
              window.dispatchEvent(new CustomEvent('auth:logout', { detail: { reason: 'refresh_rpc_failed', error: new Error(errorDetail) } }));
              return false; // Indicate refresh failure
            }
            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              console.log("RestClientStore.fetchWithAuthRefresh: Token refresh RPC successful.");
            }
            return true; // Indicate refresh success
          } catch (error) {
            console.error('[RestClientStore.fetchWithAuthRefresh REFRESH_EXCEPTION] Error during token refresh attempt:', error);
            window.dispatchEvent(new CustomEvent('auth:logout', { detail: { reason: 'refresh_attempt_exception', error } }));
            return false; // Indicate refresh failure
          } finally {
            if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
              console.log(`[RestClientStore.fetchWithAuthRefresh] Refresh operation completed. Clearing shared refreshPromise (triggered by URL: ${url}).`);
            }
            this.refreshPromise = null; // Clear the shared promise once this operation is fully complete
          }
        })();
      } else {
        if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
          console.log(`[RestClientStore.fetchWithAuthRefresh] Refresh already in progress. Awaiting its completion for URL: ${url}.`);
        }
      }

      // All callers (initiator or those that found an existing promise) await the current refreshPromise.
      try {
        const refreshSuccessful = await this.refreshPromise;

        if (refreshSuccessful) {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log(`[RestClientStore.fetchWithAuthRefresh] Refresh successful (awaited for URL: ${url}). Retrying original request.`);
          }
          const retryFetchOptions = { ...options, credentials: 'include' as RequestCredentials, headers };
          response = await fetch(url, retryFetchOptions); // Re-assign to original response variable
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.debug(`[RestClientStore.fetchWithAuthRefresh RETRY_AFTER_REFRESH] Response for ${url}: Status ${response.status}`);
          }
        } else {
          if (process.env.NEXT_PUBLIC_DEBUG === 'true') {
            console.log(`[RestClientStore.fetchWithAuthRefresh] Refresh failed (awaited for URL: ${url}). Returning original 401 response.`);
          }
          // `response` is still the original 401 response from the initial fetch.
        }
      } catch (error) {
        // This catch is for errors specifically from awaiting this.refreshPromise.
        // This might happen if the promise was nullified unexpectedly or rejected in a way not caught by its internal try/catch.
        console.error(`[RestClientStore.fetchWithAuthRefresh] Error awaiting refreshPromise for URL ${url}:`, error);
        // `response` is still the original 401 response.
        // Ensure refreshPromise is cleared if an error occurs here, though it should ideally be handled by the IIFE's finally.
        if (this.refreshPromise) { // Check if it wasn't cleared by the IIFE's finally (e.g. if IIFE itself threw before finally)
            this.refreshPromise = null;
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
export async function fetchWithAuthRefresh( // Renamed for clarity and consistency
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
