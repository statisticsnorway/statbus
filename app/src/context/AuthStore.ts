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
import { type User, type AuthStatus, _parseAuthStatusRpcResponseToAuthStatus } from '@/lib/auth.types';


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
    expired_access_token_call_refresh: false,
    error_code: null,
    token_expires_at: null,
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
      return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'AUTH_STORE_FETCH_ERROR', token_expires_at: null };
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
  }

  /**
   * Clear the cached auth status
   */
  public clearCache(): void {
    this.status = {
      isAuthenticated: false,
      user: null,
      expired_access_token_call_refresh: false,
      error_code: null,
      token_expires_at: null,
    };
    this.fetchStatus = "idle";
    this.lastFetchTime = 0;
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
   * Handle post-login state synchronization.
   * Updates auth status and clears related data caches.
   */
  public handleLogin(status: AuthStatus): void {
    this.updateAuthStatus(status);

    // Clear data caches that may contain stale, pre-login data.
    // This is a subset of clearAllCaches, intentionally omitting clearCache().
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
      expired_access_token_call_refresh: this.status.expired_access_token_call_refresh,
      cacheTTL: this.CACHE_TTL / 1000 + "s",
      environment: typeof window !== "undefined" ? "browser" : "server",
    };
  }

  private async fetchAuthStatus(): Promise<AuthStatus> {
    try {
      // Server-side: Use a direct fetch to call auth_status. This is the ONLY place
      // this special logic is needed. It ensures we don't send an Authorization header,
      // which would cause PostgREST to reject an expired token before the SQL function can analyze it.
      if (typeof window === 'undefined') {
        const { headers } = await import('next/headers');
        const incomingHeaders = await headers();
        const apiBaseUrl = process.env.SERVER_REST_URL;
        if (!apiBaseUrl) throw new Error('SERVER_REST_URL is not defined');
        
        const rpcUrl = `${apiBaseUrl}/rest/rpc/auth_status`;
        
        const headersToSend = new Headers();
        headersToSend.set('Content-Type', 'application/json');
        // Forward essential headers for context
        if (incomingHeaders.has('x-forwarded-host')) headersToSend.set('X-Forwarded-Host', incomingHeaders.get('x-forwarded-host')!);
        if (incomingHeaders.has('x-forwarded-proto')) headersToSend.set('X-Forwarded-Proto', incomingHeaders.get('x-forwarded-proto')!);
        if (incomingHeaders.has('x-forwarded-for')) headersToSend.set('X-Forwarded-For', incomingHeaders.get('x-forwarded-for')!);
        // Crucially, forward the cookie header so the SQL function can inspect it.
        if (incomingHeaders.has('cookie')) headersToSend.set('Cookie', incomingHeaders.get('cookie')!);

        const response = await fetch(rpcUrl, { method: 'POST', headers: headersToSend, body: JSON.stringify({}) });
        const data = await response.json();

        if (!response.ok) {
          console.error("AuthStore.fetchAuthStatus: Direct fetch for auth status failed:", { status: response.status, data });
          return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'RPC_ERROR', token_expires_at: null };
        }
        
        return _parseAuthStatusRpcResponseToAuthStatus(data);

      } else {
        // Client-side: Use the standard getRestClient which handles refresh logic.
        const { getRestClient } = await import("@/context/RestClientStore");
        const client = await getRestClient();
        
        if (!client) {
          console.error("AuthStore.fetchAuthStatus: Failed to get a valid REST client.");
          return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'CLIENT_INIT_ERROR', token_expires_at: null };
        }
        
        // Using POST for auth_status, which is the default for RPCs.
        const { data, error, status, statusText } = await client.rpc("auth_status");
        
        if (error) {
          console.error("AuthStore.fetchAuthStatus: Auth status check RPC failed:", { status, statusText, error });
          return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'RPC_ERROR', token_expires_at: null };
        }
      
        return _parseAuthStatusRpcResponseToAuthStatus(data);
      }
    } catch (error) {
      console.error("AuthStore.fetchAuthStatus: Exception during auth status check (outer catch):", error);
      if (error instanceof Error) {
        console.error("AuthStore.fetchAuthStatus: Error details:", {
          name: error.name,
          message: error.message,
          stack: error.stack,
        });
      }
      return { isAuthenticated: false, user: null, expired_access_token_call_refresh: false, error_code: 'FETCH_EXCEPTION', token_expires_at: null };
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
    // getAuthStatus() internally calls fetchAuthStatus, which uses getServerRestClient.
    // getServerRestClient uses the cookies from the request, so this will correctly
    // check the auth status based on the access token present in the page request.
    const currentStatus = await this.getAuthStatus(); 

    // The refresh logic has been removed as it's not viable in the middleware for page loads.
    // The middleware will simply use this status to decide whether to redirect to /login.

    return { status: currentStatus };
  }
}

export const authStore = AuthStore.getInstance();
