/**
 * ClientStore - A singleton store for managing PostgREST client instances
 * 
 * This store ensures that client instances are:
 * 1. Created only once per context (server/browser)
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests for clients are deduplicated
 */

import { SupabaseClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';

type ClientType = 'server' | 'browser';
type ClientStatus = 'idle' | 'initializing' | 'ready' | 'error';

interface ClientInfo {
  client: SupabaseClient<Database> | null;
  status: ClientStatus;
  error: Error | null;
  initPromise: Promise<SupabaseClient<Database>> | null;
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
  public async getClient(type: ClientType): Promise<SupabaseClient<Database>> {
    const now = Date.now();
    const clientInfo = this.clients[type];
    
    // If client is already initialized and not expired, return it immediately
    if (clientInfo.status === 'ready' && clientInfo.client && 
        (now - clientInfo.lastInitTime < this.CLIENT_TTL)) {
      if (process.env.NODE_ENV === 'development') {
        console.log(`Using cached ${type} client`, {
          cacheAge: Math.round((now - clientInfo.lastInitTime) / 1000) + 's'
        });
      }
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
    if (process.env.NODE_ENV === 'development') {
      console.log(`Starting new ${type} client initialization`);
    }
    
    this.clients[type].status = 'initializing';
    this.clients[type].initPromise = this.initializeClient(type);
    
    try {
      const client = await this.clients[type].initPromise;
      this.clients[type].client = client;
      this.clients[type].status = 'ready';
      this.clients[type].lastInitTime = Date.now();
      this.clients[type].error = null;
      
      if (process.env.NODE_ENV === 'development') {
        console.log(`${type} client initialization completed successfully`);
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
  public async refreshClient(type: ClientType): Promise<SupabaseClient<Database>> {
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
  private async initializeClient(type: ClientType): Promise<SupabaseClient<Database>> {
    try {
      if (type === 'server') {
        // Import the server client creator
        const { createPostgRESTSSRClient } = await import('@/utils/auth/postgrest-client-server');
        
        // Add a timeout to prevent hanging
        const timeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error('Client initialization timed out')), 10000);
        });
        
        // Race the client creation against the timeout
        return await Promise.race([
          createPostgRESTSSRClient(),
          timeoutPromise
        ]);
      } else {
        // Import the browser client creator
        const { createPostgRESTBrowserClient } = await import('@/utils/auth/postgrest-client-browser');
        
        // Add a timeout to prevent hanging
        const timeoutPromise = new Promise<never>((_, reject) => {
          setTimeout(() => reject(new Error('Client initialization timed out')), 10000);
        });
        
        // Race the client creation against the timeout
        return await Promise.race([
          createPostgRESTBrowserClient(),
          timeoutPromise
        ]);
      }
    } catch (error) {
      console.error(`Error initializing ${type} client:`, error);
      throw error;
    }
  }
}

// Export a singleton instance
export const clientStore = ClientStore.getInstance();

// Export convenience methods
export async function getServerClient(): Promise<SupabaseClient<Database>> {
  return clientStore.getClient('server');
}

export async function getBrowserClient(): Promise<SupabaseClient<Database>> {
  return clientStore.getClient('browser');
}
