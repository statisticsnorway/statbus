/**
 * AuthStore - A singleton store for managing authentication state
 * 
 * This store ensures that authentication state is:
 * 1. Fetched only when needed
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

interface AuthStatus {
  isAuthenticated: boolean;
  user: any | null;
  tokenExpiring: boolean;
}

type FetchStatus = 'idle' | 'loading' | 'success' | 'error';

class AuthStore {
  private static instance: AuthStore;
  private status: AuthStatus = {
    isAuthenticated: false,
    user: null,
    tokenExpiring: false
  };
  private fetchStatus: FetchStatus = 'idle';
  private fetchPromise: Promise<AuthStatus> | null = null;
  private lastFetchTime: number = 0;
  private readonly CACHE_TTL = 30 * 1000; // 30 seconds

  private constructor() {
    // Private constructor to enforce singleton pattern
  }

  public static getInstance(): AuthStore {
    if (!AuthStore.instance) {
      AuthStore.instance = new AuthStore();
    }
    return AuthStore.instance;
  }

  /**
   * Get authentication status, fetching from API if needed
   * This method deduplicates requests - multiple calls will share the same Promise
   */
  public async getAuthStatus(): Promise<AuthStatus> {
    const now = Date.now();
    
    // If status is already loaded and cache is still valid, return it immediately
    if (this.fetchStatus === 'success' && now - this.lastFetchTime < this.CACHE_TTL) {
      if (process.env.NODE_ENV === 'development') {
        console.log('Using cached auth status', {
          cacheAge: Math.round((now - this.lastFetchTime) / 1000) + 's',
          isAuthenticated: this.status.isAuthenticated
        });
      }
      return this.status;
    }
    
    // If a fetch is already in progress, return the existing promise
    if (this.fetchStatus === 'loading' && this.fetchPromise) {
      if (process.env.NODE_ENV === 'development') {
        console.log('Reusing in-progress auth status fetch');
      }
      return this.fetchPromise;
    }
    
    // Start a new fetch
    if (process.env.NODE_ENV === 'development') {
      console.log('Starting new auth status fetch');
    }
    this.fetchStatus = 'loading';
    this.fetchPromise = this.fetchAuthStatus();
    
    try {
      const result = await this.fetchPromise;
      this.status = result;
      this.fetchStatus = 'success';
      this.lastFetchTime = Date.now();
      
      if (process.env.NODE_ENV === 'development') {
        console.log('Auth status fetch completed successfully', {
          isAuthenticated: result.isAuthenticated,
          hasUser: !!result.user,
          tokenExpiring: result.tokenExpiring
        });
      }
      
      return result;
    } catch (error) {
      this.fetchStatus = 'error';
      console.error('Failed to fetch auth status:', error);
      
      // Add more detailed error logging
      if (error instanceof Error) {
        console.error('Error details:', {
          name: error.name,
          message: error.message,
          stack: error.stack
        });
      }
      
      // Return the last known status or default to not authenticated
      return this.status.isAuthenticated 
        ? this.status 
        : { isAuthenticated: false, user: null, tokenExpiring: false };
    } finally {
      this.fetchPromise = null;
    }
  }

  /**
   * Force refresh the auth status
   */
  public async refreshAuthStatus(): Promise<AuthStatus> {
    this.fetchStatus = 'loading';
    this.fetchPromise = this.fetchAuthStatus();
    
    try {
      const result = await this.fetchPromise;
      this.status = result;
      this.fetchStatus = 'success';
      this.lastFetchTime = Date.now();
      return result;
    } catch (error) {
      this.fetchStatus = 'error';
      console.error('Failed to refresh auth status:', error);
      throw error;
    } finally {
      this.fetchPromise = null;
    }
  }

  /**
   * Update the auth status directly (used after login/logout)
   */
  public updateAuthStatus(status: AuthStatus): void {
    this.status = status;
    this.fetchStatus = 'success';
    this.lastFetchTime = Date.now();
    
    if (process.env.NODE_ENV === 'development') {
      console.log('Auth status updated directly', {
        isAuthenticated: status.isAuthenticated,
        hasUser: !!status.user
      });
    }
  }

  /**
   * Clear the cached auth status
   */
  public clearCache(): void {
    this.status = {
      isAuthenticated: false,
      user: null,
      tokenExpiring: false
    };
    this.fetchStatus = 'idle';
    this.lastFetchTime = 0;
    
    if (process.env.NODE_ENV === 'development') {
      console.log('Auth status cache cleared');
    }
  }

  /**
   * Get the current fetch status
   */
  public getFetchStatus(): FetchStatus {
    return this.fetchStatus;
  }
  
  /**
   * Get debug information about the store state
   */
  public getDebugInfo(): Record<string, any> {
    return {
      fetchStatus: this.fetchStatus,
      lastFetchTime: this.lastFetchTime,
      cacheAge: this.lastFetchTime ? Math.round((Date.now() - this.lastFetchTime) / 1000) + 's' : 'never',
      hasFetchPromise: !!this.fetchPromise,
      isAuthenticated: this.status.isAuthenticated,
      hasUser: !!this.status.user,
      tokenExpiring: this.status.tokenExpiring,
      cacheTTL: this.CACHE_TTL / 1000 + 's',
      environment: typeof window !== 'undefined' ? 'browser' : 'server'
    };
  }

  /**
   * Internal method to fetch auth status from API
   */
  private async fetchAuthStatus(): Promise<AuthStatus> {
    try {
      // For server-side requests, check if we can access the token directly
      if (typeof window === 'undefined') {
        try {
          // Use dynamic import to avoid issues with next/headers
          const { cookies } = await import('next/headers');
          const cookieStore = await cookies();
          const token = cookieStore.get('statbus');
          
          const result = {
            isAuthenticated: !!token,
            user: null, // We don't have user details from the token alone
            tokenExpiring: false
          };
          
          if (process.env.NODE_ENV === 'development') {
            console.log(`Server-side auth check: ${result.isAuthenticated ? 'Token found' : 'No token'}`);
          }
          
          if (result.isAuthenticated) {
            console.log('Server-side auth check: User is authenticated');
          }
          
          return result;
        } catch (error) {
          console.error('Error accessing cookies in server component:', error);
          // Fall back to API call if cookies can't be accessed
        }
      }
      
      // Always use the proxy URL for consistency in development
      const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
        ? '' // Use relative URL to ensure we hit the same origin
        : (typeof window !== 'undefined' 
            ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
            : process.env.SERVER_API_URL);
        
      const apiEndpoint = `${apiUrl}/postgrest/rpc/auth_status`;
      
      if (process.env.NODE_ENV === 'development') {
        console.log(`Checking auth status at ${apiEndpoint}`);
      }
      
      // Use a consistent approach for both client and server
      const { serverFetch } = await import('@/utils/auth/server-fetch');
      const response = await serverFetch(apiEndpoint, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        }
      });
      
      if (!response.ok) {
        console.error(`Auth status check failed: ${response.status} ${response.statusText}`);
        return { isAuthenticated: false, user: null, tokenExpiring: false };
      }

      // Check if the response is empty (Content-Length: 0)
      const contentLength = response.headers.get('Content-Length');
      const contentType = response.headers.get('Content-Type');
      
      // Handle empty responses (which would cause JSON parse errors)
      if (contentLength === '0' || !contentType?.includes('application/json')) {
        console.warn('Auth status endpoint returned empty or non-JSON response');
        return {
          isAuthenticated: false,
          user: null,
          tokenExpiring: false
        };
      }
      
      // Safely parse the JSON response
      const { safeParseJSON } = await import('@/utils/debug-helpers');
      const data = await safeParseJSON(response);
      
      // If parsing failed, return default values
      if (data === null) {
        return {
          isAuthenticated: false,
          user: null,
          tokenExpiring: false
        };
      }
      
      // The API returns different formats in different contexts, handle both
      const isAuthenticated = 
        data.authenticated === true || 
        data.isAuthenticated === true;
      
      return {
        isAuthenticated,
        user: data.user || null,
        tokenExpiring: data.token_expiring === true || data.tokenExpiring === true
      };
    } catch (error) {
      console.error('Error checking auth status:', error);
      return { isAuthenticated: false, user: null, tokenExpiring: false };
    }
  }
}

// Export a singleton instance
export const authStore = AuthStore.getInstance();
