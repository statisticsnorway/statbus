/**
 * AuthStore - A singleton store for managing authentication state
 *
 * This store ensures that authentication state is:
 * 1. Fetched only when needed
 * 2. Properly cached
 * 3. Available globally
 * 4. Requests are deduplicated (multiple simultaneous requests result in only one API call)
 */

import { getRestClient, getServerRestClient, fetchWithAuth } from "@/context/RestClientStore";
import type { NextRequest, NextResponse } from 'next/server';
import * as setCookie from 'set-cookie-parser';
import { _parseAuthStatusRpcResponseToAuthStatus } from '@/atoms/index'; 

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
  error_code: string | null;
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
    error_code: null,
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

      if (error instanceof Error) {
        console.error("AuthStore.getAuthStatus: Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
        });
      }

      // Always return a fresh unauthenticated state on error
      if (process.env.DEBUG === 'true') {
        console.log("AuthStore.getAuthStatus: Returning unauthenticated state due to error");
      }
      return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'AUTH_STORE_FETCH_ERROR' };
    }
  }

  /**
   * Force refresh the auth status
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

    if (process.env.DEBUG === 'true') {
      console.log("AuthStore.updateAuthStatus: Auth status updated directly", {
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
      error_code: null,
    };
    this.fetchStatus = "idle";
    this.lastFetchTime = 0;

    if (process.env.DEBUG === 'true') {
      console.log("AuthStore.clearCache: Auth status cache cleared");
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
  // This method is being deprecated in favor of clientSideRefreshAtom for Jotai-integrated proactive refresh.
  // If RestClientStore.fetchWithAuthRefresh was the only caller, it can be removed.
  // For now, commenting out as its direct Jotai update capability is limited.
  /*
  public async refreshTokenIfNeeded(): Promise<{
    success: boolean;
    // newStatus?: AuthStatus; // If it were to return the new status
  }> {
    // This method, if kept, would be for non-Jotai callers or specific scenarios.
    // It cannot directly update Jotai's authStatusAtom.
    // The clientSideRefreshAtom in app/src/atoms/index.ts is preferred for Jotai environments.
    if (typeof window === 'undefined') {
      console.warn("AuthStore.refreshTokenIfNeeded called on server. This is unexpected for client-side refresh logic.");
      return { success: false };
    }
      
    try {
      const client = await getRestClient(); // Assumes getRestClient is available
        
      const { data, error } = await client.rpc("refresh"); // RPC now returns AuthStatus directly
      
      if (error) {
        console.error("AuthStore.refreshTokenIfNeeded: Token refresh RPC failed:", error);
        return { success: false };
      }
      
      // data is the new AuthStatus object from the RPC
      const newParsedStatus = _parseAuthStatusRpcResponseToAuthStatus(data);
      
      this.status = newParsedStatus;
      this.fetchStatus = "success";
      this.lastFetchTime = Date.now();

      if (process.env.NODE_ENV === "development") {
        console.log("AuthStore.refreshTokenIfNeeded: Token refreshed successfully (AuthStore internal state updated).");
      }
      // IMPORTANT: This does NOT update the Jotai authStatusAtom.
      // Callers needing Jotai state update should use clientSideRefreshAtom.
      return { success: true // , newStatus: newParsedStatus 
      }; 
    } catch (error) {
      console.error("Error in AuthStore.refreshTokenIfNeeded:", error);
      return { success: false };
    }
  }
  */

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
      let client;
      // Determine if running in a server environment
      if (typeof window === 'undefined') {
        const { getServerRestClient } = await import("@/context/RestClientStore");
        client = await getServerRestClient();
      } else {
        const { getRestClient } = await import("@/context/RestClientStore");
        client = await getRestClient(); // This should be the browser client
      }
      
      if (!client) {
        console.error("AuthStore.fetchAuthStatus: Failed to get a valid REST client.");
        return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'CLIENT_INIT_ERROR' };
      }
      
      if (process.env.DEBUG === 'true') {
        console.log(`[AuthStore.fetchAuthStatus] Calling client.rpc('auth_status', {}, { get: true, count: 'exact' }). Client URL: ${client.url}`);
      }
      // Using GET for auth_status
      const { data, error, status, statusText, count } = await client.rpc("auth_status", {}, { get: true, count: 'exact' });
      
      if (process.env.DEBUG === 'true') {
        console.log(`[AuthStore.fetchAuthStatus] Response from client.rpc('auth_status', {}, { get: true, count: 'exact' }): status=${status}, statusText=${statusText}, data=${JSON.stringify(data)}, error=${JSON.stringify(error)}, count=${count}`);
      }
      
      if (error) {
        console.error("AuthStore.fetchAuthStatus: Auth status check RPC failed:", { status, statusText, error });
        return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'RPC_ERROR' };
      }
    
      // _parseAuthStatusRpcResponseToAuthStatus returns Omit<JotaiAuthStatus, 'loading'>
      // which matches AuthStore's AuthStatus interface.
      const result = _parseAuthStatusRpcResponseToAuthStatus(data); 
    
      return result;
    } catch (error) {
      console.error("AuthStore.fetchAuthStatus: Exception during auth status check (outer catch):", error);
      if (error instanceof Error) {
        console.error("AuthStore.fetchAuthStatus: Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
        });
      }
      return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'FETCH_EXCEPTION' };
    }
  }
  
  /**
   * Performs a server-side authentication check. This is intended to be called from Next.js Middleware.
   * It checks for a valid access token by calling the `/rest/rpc/auth_status` endpoint.
   * 
   * It does NOT attempt to refresh the token. As documented in `doc/auth-design.md`, the refresh token
   * is not available to the middleware during page requests due to its `HttpOnly` and `Path=/rest/rpc/refresh`
   * cookie properties. Token refresh is a client-side responsibility.
   * 
   * @param requestCookies - Readonly cookies from the incoming NextRequest.
   * @param responseCookies - Mutable cookies object from a NextResponse instance (currently unused but kept for API consistency).
   * @returns An object containing the authentication status.
   */
  public async handleServerAuth(
    requestCookies: NextRequest['cookies'],
    responseCookies: NextResponse['cookies']
  ): Promise<{
    status: AuthStatus;
  }> {
    if (process.env.DEBUG === 'true') {
      const allCookiesForLog = requestCookies.getAll().map(c => ({ name: c.name, value: c.value.startsWith('eyJ') ? `${c.value.substring(0,15)}...` : c.value }));
      console.log("[AuthStore.handleServerAuth] Entry. Request cookies:", JSON.stringify(allCookiesForLog));
      const accessToken = requestCookies.get('statbus');
      if (accessToken && accessToken.value) {
        console.log(`[AuthStore.handleServerAuth] Access token ('statbus' cookie) found in request: ${accessToken.value.substring(0, 20)}...`);
      } else {
        console.log("[AuthStore.handleServerAuth] No access token ('statbus' cookie) found in request cookies.");
      }
    }

    // getAuthStatus() internally calls fetchAuthStatus, which uses getServerRestClient.
    // getServerRestClient uses the cookies from the request, so this will correctly
    // check the auth status based on the access token present in the page request.
    const currentStatus = await this.getAuthStatus(); 
    if (process.env.DEBUG === 'true') {
      console.log("[AuthStore.handleServerAuth] Status from getAuthStatus() (which calls /rest/rpc/auth_status):", JSON.stringify(currentStatus));
    }

    // The refresh logic has been removed as it's not viable in the middleware for page loads.
    // The middleware will simply use this status to decide whether to redirect to /login.

    return { status: currentStatus };
  }
}

export const authStore = AuthStore.getInstance();
