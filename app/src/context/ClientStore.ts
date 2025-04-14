/**
 * ClientStore - A singleton store for managing PostgREST client instances
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

class ClientStore {
  private static instance: ClientStore;
  private clients: Record<ClientType, ClientInfo> = {
    server: {
      client: null,
      status: 'idle',
      error: null,
      initPromise: null,
      lastInitTime: 0
    },
    browser: {
      client: null,
      status: 'idle',
      error: null,
      initPromise: null,
      lastInitTime: 0
    }
  };
  private readonly CLIENT_TTL = 10 * 60 * 1000; // 10 minutes

  private constructor() {
    // Private constructor to enforce singleton pattern
  }

  public static getInstance(): ClientStore {
    if (!ClientStore.instance) {
      ClientStore.instance = new ClientStore();
    }
    return ClientStore.instance;
  }

  /**
   * Get a PostgREST client for the specified context
   * This method deduplicates requests - multiple calls will share the same Promise
   */
  public async getClient(type: ClientType): Promise<PostgrestClient<Database>> {
    const now = Date.now();
    const clientInfo = this.clients[type];
    
    // If client is already initialized and not expired, return it immediately
    if (clientInfo.status === 'ready' && clientInfo.client && 
        (now - clientInfo.lastInitTime < this.CLIENT_TTL)) {
      return clientInfo.client;
    }
    
    // If initialization is already in progress, return the existing promise
    if (clientInfo.status === 'initializing' && clientInfo.initPromise) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`Reusing in-progress ${type} client initialization`);
      }
      return clientInfo.initPromise;
    }
    
    // Start a new initialization
    this.clients[type].status = 'initializing';
    this.clients[type].initPromise = this.initializeClient(type);
    
    try {
      const client = await this.clients[type].initPromise;
      this.clients[type].client = client;
      this.clients[type].status = 'ready';
      this.clients[type].lastInitTime = Date.now();
      this.clients[type].error = null;
      
      if (process.env.NODE_ENV === 'development') {
        console.log(`PostgREST client initialized`,{url: client.url, type: type});
      }
      
      return client;
    } catch (error) {
      this.clients[type].status = 'error';
      this.clients[type].error = error instanceof Error ? error : new Error(String(error));
      
      console.error(`Failed to initialize ${type} client:`, error);
      
      throw error;
    } finally {
      this.clients[type].initPromise = null;
    }
  }

  /**
   * Force refresh the client
   */
  public async refreshClient(type: ClientType): Promise<PostgrestClient<Database>> {
    this.clients[type].status = 'initializing';
    this.clients[type].initPromise = this.initializeClient(type);
    
    try {
      const client = await this.clients[type].initPromise;
      this.clients[type].client = client;
      this.clients[type].status = 'ready';
      this.clients[type].lastInitTime = Date.now();
      this.clients[type].error = null;
      return client;
    } catch (error) {
      this.clients[type].status = 'error';
      this.clients[type].error = error instanceof Error ? error : new Error(String(error));
      throw error;
    } finally {
      this.clients[type].initPromise = null;
    }
  }

  /**
   * Clear the cached client
   */
  public clearCache(type?: ClientType): void {
    if (type) {
      this.clients[type] = {
        client: null,
        status: 'idle',
        error: null,
        initPromise: null,
        lastInitTime: 0
      };
      
      if (process.env.NODE_ENV === 'development') {
        console.log(`${type} client cache cleared`);
      }
    } else {
      // Clear all clients
      Object.keys(this.clients).forEach(clientType => {
        this.clients[clientType as ClientType] = {
          client: null,
          status: 'idle',
          error: null,
          initPromise: null,
          lastInitTime: 0
        };
      });
      
      if (process.env.NODE_ENV === 'development') {
        console.log('All client caches cleared');
      }
    }
  }

  /**
   * Get debug information about the store state
   */
  public getDebugInfo(): Record<string, any> {
    return {
      server: {
        status: this.clients.server.status,
        lastInitTime: this.clients.server.lastInitTime,
        cacheAge: this.clients.server.lastInitTime ? 
          Math.round((Date.now() - this.clients.server.lastInitTime) / 1000) + 's' : 
          'never',
        hasClient: !!this.clients.server.client,
        hasInitPromise: !!this.clients.server.initPromise,
        hasError: !!this.clients.server.error,
        errorMessage: this.clients.server.error?.message
      },
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
      cacheTTL: this.CLIENT_TTL / 1000 + 's',
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
  }

  /**
   * Internal method to initialize a client
   */
  private async initializeClient(type: ClientType): Promise<PostgrestClient<Database>> {
    try {
      if (type === 'server') {
        // Create server client
        const apiBaseUrl = process.env.SERVER_API_URL;        
        if (!apiBaseUrl) {
          throw new Error('SERVER_API_URL environment variable is not defined');
        }
        const apiUrl = apiBaseUrl + '/postgrest';
        
        // Add a timeout to prevent hanging
        const timeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error('Client initialization timed out')), 10000);
        });
        
        // Create a new PostgrestClient with auth headers from cookies
        const createClient = async () => {
          // Get auth token from cookies for server components
          let headers: Record<string, string> = {
            'Content-Type': 'application/json',
          };
          
          try {
            const { cookies } = await import("next/headers");
            const cookieStore = await cookies();
            const token = cookieStore.get("statbus");
            
            if (token) {
              // Add the token as an Authorization header
              headers['Authorization'] = `Bearer ${token.value}`;
              
              if (process.env.NODE_ENV === 'development') {
                console.log('Server client initialized with auth token');
              }
            } else {
              console.log('No auth token found in cookies for server client');
            }
          } catch (error) {
            console.error('Error getting cookies for server client:', error);
          }
          
          return new PostgrestClient<Database>(apiUrl, { headers });
        };
        
        // Race the client creation against the timeout
        return await Promise.race([
          createClient(),
          timeoutPromise
        ]);
      } else {
        // Create browser client
        const apiBaseUrl = process.env.NEXT_PUBLIC_BROWSER_API_URL;
        
        if (!apiBaseUrl) {
          throw new Error('NEXT_PUBLIC_BROWSER_API_URL environment variable is not defined');
        }
        
        const apiUrl = apiBaseUrl + '/postgrest';
        
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
      console.debug(`Fetch request to: ${url}`);
    }
    
    // Handle URLs for the PostgREST client
    // Ensure we have a properly formatted URL
    if (!url.startsWith('http') && !url.startsWith('/')) {
      url = `/postgrest/${url}`;
      if (process.env.NODE_ENV === 'development') {
        console.debug(`Modified relative URL to: ${url}`);
      }
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
        const cookieStore = cookies();
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
    
    // If we get a 401 Unauthorized, try to refresh the token
    if (response.status === 401) {
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
export const clientStore = ClientStore.getInstance();

// Export convenience methods for accessing PostgREST clients
export async function getServerClient(): Promise<PostgrestClient<Database>> {
  return clientStore.getClient('server');
}

export async function getBrowserClient(): Promise<PostgrestClient<Database>> {
  return clientStore.getClient('browser');
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
export async function getClient(): Promise<PostgrestClient<Database>> {
  return typeof window === 'undefined'
    ? await clientStore.getClient('server')
    : await clientStore.getClient('browser');
}
