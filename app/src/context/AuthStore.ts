/**
 * AuthStore - A singleton store for managing authentication state
 *
 * This store ensures that authentication state is:
 * 1. Fetched only when needed
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

import { getRestClient, getServerRestClient } from "@/context/RestClientStore";
import type { NextRequest, NextResponse } from 'next/server';

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
   * Get authentication status, always fetching fresh data from API
   */
  public async getAuthStatus(): Promise<AuthStatus> {
    // Always fetch fresh data - no caching
    this.fetchStatus = "loading";
    
    try {
      // Directly fetch auth status without caching
      const result = await this.fetchAuthStatus();
      
      // Update the status for other methods that might use it
      this.status = result;
      this.fetchStatus = "success";
      this.lastFetchTime = Date.now();

      return result;
    } catch (error) {
      this.fetchStatus = "error";
      console.error("AuthStore.getAuthStatus: Failed to fetch auth status:", error);

      // Add more detailed error logging
      if (error instanceof Error) {
        console.error("AuthStore.getAuthStatus: Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
        });
      }

      // Always return a fresh unauthenticated state on error
      console.log("AuthStore.getAuthStatus: Returning unauthenticated state due to error");
      return { isAuthenticated: false, user: null, tokenExpiring: false };
    }
  }

  /**
   * Force refresh the auth status
   * (Now identical to getAuthStatus since caching is removed)
   */
  public async refreshAuthStatus(): Promise<AuthStatus> {
    return this.getAuthStatus();
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
    // Server-side refresh is handled by middleware, this function is only for browser-side.
    if (typeof window === 'undefined') {
      console.warn("AuthStore.refreshTokenIfNeeded called on server, returning false. Middleware should handle refresh.");
      return { success: false };
    }
      
    try {
      // Always fetch fresh auth status (on the browser)
      const authStatus = await this.fetchAuthStatus();

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
      
      if (!error) {
        if (process.env.NODE_ENV === "development") {
          console.log("Token refreshed successfully");
        }
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

      return result;
    } catch (error) {
      console.error("AuthStore.fetchAuthStatus: Error checking auth status:", error);
      if (error instanceof Error) {
        console.error("AuthStore.fetchAuthStatus: Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
        });
      }
      return { isAuthenticated: false, user: null, tokenExpiring: false };
    }
  }
  
  /**
   * Performs server-side authentication check and handles token refresh if necessary.
   * This is intended to be called from Next.js Middleware.
   * 
   * @param requestCookies - Readonly cookies from the incoming NextRequest.
   * @param responseCookies - Mutable cookies object from a NextResponse instance.
   * @returns An object containing the final auth status, and potentially modified request/response headers.
   */
  public async handleServerAuth(
    requestCookies: NextRequest['cookies'],
    responseCookies: NextResponse['cookies']
  ): Promise<{
    status: AuthStatus;
    modifiedRequestHeaders?: Headers; // Headers for subsequent handlers in the *same* request
    // Note: responseCookies object passed in is mutated directly for Set-Cookie
  }> {
    let currentStatus = await this.getAuthStatus(); // Uses getServerRestClient -> next/headers implicitly
    let modifiedRequestHeaders: Headers | undefined = undefined;

    if (!currentStatus.isAuthenticated) {
      console.log("AuthStore.handleServerAuth: Initial check failed, attempting refresh.");
      
      const refreshTokenCookie = requestCookies.get('statbus-refresh');
      if (!refreshTokenCookie) {
        console.log("AuthStore.handleServerAuth: No refresh token cookie found.");
        // Return current (unauthenticated) status, no modifications needed
        return { status: currentStatus }; 
      }

      // --- Attempt Refresh ---
      try {
        const refreshUrl = `${process.env.SERVER_REST_URL}/rpc/refresh`; 
        console.log(`AuthStore.handleServerAuth: Attempting token refresh via: ${refreshUrl}`);

        const refreshResponse = await fetch(refreshUrl, {
          method: 'POST', 
          headers: {
            'Cookie': `statbus-refresh=${refreshTokenCookie.value}`
          },
        });

        if (!refreshResponse.ok) {
          console.error(`AuthStore.handleServerAuth: Refresh fetch failed: ${refreshResponse.status} ${refreshResponse.statusText}`);
          // Clear potentially invalid cookies on the response
          responseCookies.delete('statbus');
          responseCookies.delete('statbus-refresh');
          return { status: { isAuthenticated: false, user: null, tokenExpiring: false } };
        }

        // --- Process Successful Refresh ---
        const setCookieHeader = refreshResponse.headers.get('set-cookie');
        if (!setCookieHeader) {
           console.error("AuthStore.handleServerAuth: Refresh succeeded but no Set-Cookie header received.");
           // Return unauthenticated status, maybe clear cookies?
           responseCookies.delete('statbus');
           responseCookies.delete('statbus-refresh');
           return { status: { isAuthenticated: false, user: null, tokenExpiring: false } };
        }

        // Parse new tokens (basic parsing, needs improvement for production)
        let newAccessToken: string | null = null;
        let newRefreshToken: string | null = null;
        const cookies = setCookieHeader.split(', '); 
        cookies.forEach(cookieStr => {
           const parts = cookieStr.split(';')[0].split('=');
           if (parts.length === 2) {
             const name = parts[0].trim();
             const value = parts[1].trim();
             if (name === 'statbus') newAccessToken = value;
             else if (name === 'statbus-refresh') newRefreshToken = value;
           }
        });

        if (newAccessToken && newRefreshToken) {
          console.log("AuthStore.handleServerAuth: Refresh successful.");
          
          // Stage Set-Cookie headers on the response object provided by the middleware
          const cookieOptions = { 
            httpOnly: true, 
            secure: process.env.NODE_ENV !== 'development', 
            path: '/', 
            sameSite: 'lax' as const 
          };
          responseCookies.set('statbus', newAccessToken, cookieOptions);
          responseCookies.set('statbus-refresh', newRefreshToken, cookieOptions);

          // Prepare modified headers for the *ongoing* request
          // We need the original request headers to clone them
          // This part is tricky as AuthStore doesn't have the full NextRequest
          // We will return the new tokens and let middleware handle header modification
          modifiedRequestHeaders = new Headers(); // Placeholder - middleware will construct this
          modifiedRequestHeaders.set('X-Statbus-Refreshed-Token', newAccessToken); // Signal new token

          // Re-check auth status *conceptually* with the new token
          // In reality, the next call to getAuthStatus in the *same request* 
          // needs the modified headers passed via middleware.
          // For now, we optimistically assume authentication is successful.
          // A more robust approach might involve fetching user details here.
          currentStatus = { 
              isAuthenticated: true, 
              // User details might be stale here, ideally fetch them
              user: null, // Mark as potentially stale or fetch user info
              tokenExpiring: false // Assume new token is not immediately expiring
          }; 
          
          console.log("AuthStore.handleServerAuth: Staging new cookies and signaling modified headers.");
          
        } else {
           console.error("AuthStore.handleServerAuth: Refresh succeeded but failed to parse new tokens from Set-Cookie:", setCookieHeader);
           responseCookies.delete('statbus');
           responseCookies.delete('statbus-refresh');
           currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false };
        }

      } catch (error) {
        console.error("AuthStore.handleServerAuth: Error during refresh fetch:", error);
        responseCookies.delete('statbus');
        responseCookies.delete('statbus-refresh');
        currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false };
      }
    }

    // Return the determined status and any modifications needed
    return { status: currentStatus, modifiedRequestHeaders };
  }
}

// Export a singleton instance
export const authStore = AuthStore.getInstance();
