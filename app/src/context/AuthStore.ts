/**
 * AuthStore - A singleton store for managing authentication state
 *
 * This store ensures that authentication state is:
 * 1. Fetched only when needed
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

/**
 * User type definition for authentication
 */
export interface User {
  uid: number;
  sub: string;
  email: string;
  role: string;
  statbus_role: string;
  last_sign_in_at: string;
  created_at: string;
}

/**
 * Authentication status type
 */
export interface AuthStatus {
  isAuthenticated: boolean;
  tokenExpiring: boolean;
  user: User | null;
}


/**
 * Authentication error class
 */
export class AuthenticationError extends Error {
  constructor(message: string = "Authentication required") {
    super(message);
    this.name = "AuthenticationError";
  }
}

type FetchStatus = "idle" | "loading" | "success" | "error";

class AuthStore {
  private static instance: AuthStore;
  private status: AuthStatus = {
    isAuthenticated: false,
    user: null,
    tokenExpiring: false,
  };
  private fetchStatus: FetchStatus = "idle";
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
    if (
      this.fetchStatus === "success" &&
      now - this.lastFetchTime < this.CACHE_TTL
    ) {
      if (process.env.NODE_ENV === "development") {
        // The cache is purged when logging in/out via clearAllCaches() or when manually cleared
        // It doesn't automatically detect cookie changes, but has a short TTL (30s)
        console.log("Using cached auth status", {
          cacheAge: Math.round((now - this.lastFetchTime) / 1000) + "s",
          user: this.status.user,
        });
      }
      return this.status;
    }

    // If a fetch is already in progress, return the existing promise
    if (this.fetchStatus === "loading" && this.fetchPromise) {
      if (process.env.NODE_ENV === "development") {
        console.log("Reusing in-progress auth status fetch");
      }
      return this.fetchPromise;
    }

    // Start a new fetch
    this.fetchStatus = "loading";
    this.fetchPromise = this.fetchAuthStatus();

    try {
      const result = await this.fetchPromise;
      this.status = result;
      this.fetchStatus = "success";
      this.lastFetchTime = Date.now();

      return result;
    } catch (error) {
      this.fetchStatus = "error";
      console.error("Failed to fetch auth status:", error);

      // Add more detailed error logging
      if (error instanceof Error) {
        console.error("Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
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
    this.fetchStatus = "loading";
    this.fetchPromise = this.fetchAuthStatus();

    try {
      const result = await this.fetchPromise;
      this.status = result;
      this.fetchStatus = "success";
      this.lastFetchTime = Date.now();
      return result;
    } catch (error) {
      this.fetchStatus = "error";
      console.error("Failed to refresh auth status:", error);
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
    this.fetchStatus = "success";
    this.lastFetchTime = Date.now();

    if (process.env.NODE_ENV === "development") {
      console.log("Auth status updated directly", {
        isAuthenticated: status.isAuthenticated,
        hasUser: !!status.user,
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
      tokenExpiring: false,
    };
    this.fetchStatus = "idle";
    this.lastFetchTime = 0;

    if (process.env.NODE_ENV === "development") {
      console.log("Auth status cache cleared");
    }
  }

  /**
   * Clear all related caches
   * Call this when logging in or out to ensure fresh state
   */
  public clearAllCaches(): void {
    // Clear auth cache
    this.clearCache();

    // Also clear the client and base data caches when auth cache is cleared
    // We'll import dynamically to avoid circular dependencies
    if (typeof window !== "undefined") {
      // Only run this in the browser
      import("@/context/BaseDataStore")
        .then(({ baseDataStore }) => {
          baseDataStore.clearCache();
        })
        .catch((err) => {
          console.error("Failed to clear base data cache:", err);
        });

      import("@/context/RestClientStore")
        .then(({ clientStore }) => {
          clientStore.clearCache();
        })
        .catch((err) => {
          console.error("Failed to clear client cache:", err);
        });
    }
  }

  /**
   * Check if the user is authenticated
   * This is a convenience method that uses getAuthStatus
   */
  public async isAuthenticated(): Promise<boolean> {
    try {
      const authStatus = await this.getAuthStatus();
      return authStatus.isAuthenticated;
    } catch (error) {
      console.error("Error checking authentication status:", error);
      return false;
    }
  }

  /**
   * Check if a token needs refresh and refresh it if needed
   * Returns success status
   */
  public async refreshTokenIfNeeded(): Promise<{
    success: boolean;
  }> {
    try {
      // First check auth status to see if token is expiring
      const authStatus = await this.getAuthStatus();

      // If not authenticated at all, no point in refreshing
      if (!authStatus.isAuthenticated) {
        return { success: false };
      }

      // If token is not expiring, no need to refresh
      if (!authStatus.tokenExpiring) {
        return { success: true };
      }

      // Get the appropriate client based on environment
      const { getRestClient } = await import("@/context/RestClientStore");
      
      // Client-side or server-side refresh using the appropriate client
      const client = await getRestClient();
        
      const { data, error } = await client.rpc("refresh");
      
      // Clear auth cache to ensure fresh status on next check
      if (!error) {
        this.clearAllCaches();
        return { success: true };
      }
      
      console.error("Token refresh failed:", error);
      return { success: false };
    } catch (error) {
      console.error("Error in refreshTokenIfNeeded:", error);
      return { success: false };
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
      cacheAge: this.lastFetchTime
        ? Math.round((Date.now() - this.lastFetchTime) / 1000) + "s"
        : "never",
      hasFetchPromise: !!this.fetchPromise,
      isAuthenticated: this.status.isAuthenticated,
      hasUser: !!this.status.user,
      tokenExpiring: this.status.tokenExpiring,
      cacheTTL: this.CACHE_TTL / 1000 + "s",
      environment: typeof window !== "undefined" ? "browser" : "server",
    };
  }

  private async fetchAuthStatus(): Promise<AuthStatus> {
    try {
      // Get the appropriate client based on environment
      const { getRestClient } = await import("@/context/RestClientStore");
      const client = await getRestClient();
      
      // Call the auth_status RPC function with type assertion
      const { data, error } = await client.rpc("auth_status");
      
      if (error) {
        console.error("Auth status check failed:", error);
        return { isAuthenticated: false, user: null, tokenExpiring: false };
      }
      
      // Map the response to our AuthStatus format
      const authData = data as any;
      
      const result = authData === null
        ? {
            isAuthenticated: false,
            user: null,
            tokenExpiring: false,
          }
        : {
            isAuthenticated: authData.is_authenticated,
            tokenExpiring: authData.token_expiring === true,
            user: authData.uid ? {
              uid: authData.uid,
              sub: authData.sub,
              email: authData.email,
              role: authData.role,
              statbus_role: authData.statbus_role,
              last_sign_in_at: authData.last_sign_in_at,
              created_at: authData.created_at
            } : null
          };

      if (process.env.NODE_ENV === "development") {
        console.log(`Checked auth status`, {
          user: authData?.user || null,
          result: result,
        });
      }

      return result;
    } catch (error) {
      console.error("Error checking auth status:", error);
      return { isAuthenticated: false, user: null, tokenExpiring: false };
    }
  }
}

// Export a singleton instance
export const authStore = AuthStore.getInstance();
