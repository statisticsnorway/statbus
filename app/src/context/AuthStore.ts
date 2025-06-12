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
  // AuthStore's version of AuthStatus doesn't need 'loading' as it's about the fetched state.
  isAuthenticated: boolean;
  tokenExpiring: boolean;
  user: User | null;
  error_code: string | null; // Added error_code
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

      // Add more detailed error logging
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
      error_code: null,
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
      
      // Update AuthStore's internal status
      this.status = newParsedStatus;
      this.fetchStatus = "success"; // Mark as success
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
      // Get the appropriate client based on environment
      const { getRestClient } = await import("@/context/RestClientStore");
      const client = await getRestClient();
      
      // Call the auth_status RPC function with type assertion
      const { data, error } = await client.rpc("auth_status");
      
      if (error) {
        console.error("AuthStore.fetchAuthStatus: Auth status check RPC failed:", error);
        return { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'RPC_ERROR' };
      }
    
      // _parseAuthStatusRpcResponseToAuthStatus returns Omit<JotaiAuthStatus, 'loading'>
      // which matches AuthStore's AuthStatus interface.
      const result = _parseAuthStatusRpcResponseToAuthStatus(data); 
    
      return result;
    } catch (error) {
      console.error("AuthStore.fetchAuthStatus: Exception during auth status check:", error);
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
    if (process.env.DEBUG === 'true') {
      console.log("[AuthStore.handleServerAuth] Entry. Request cookies:", JSON.stringify(requestCookies.getAll()));
    }

    let currentStatus = await this.getAuthStatus(); 
    if (process.env.DEBUG === 'true') {
      console.log("[AuthStore.handleServerAuth] Status from getAuthStatus():", JSON.stringify(currentStatus));
    }
    let modifiedRequestHeaders: Headers | undefined = undefined;

    if (!currentStatus.isAuthenticated) {
      if (process.env.DEBUG === 'true') {
        console.log("[AuthStore.handleServerAuth] Initial check indicates not authenticated. Attempting refresh.");
      }
      
      const refreshTokenCookie = requestCookies.get('statbus-refresh');
      if (!refreshTokenCookie || !refreshTokenCookie.value) {
        if (process.env.DEBUG === 'true') {
          console.log("[AuthStore.handleServerAuth] No valid refresh token cookie found.");
        }
        // Return current (unauthenticated) status, no modifications needed
        return { status: currentStatus }; 
      }

      // --- Attempt Refresh ---
      try {
        const refreshUrl = `${process.env.SERVER_REST_URL}/rest/rpc/refresh`;
        if (process.env.DEBUG === 'true') {
          console.log(`[AuthStore.handleServerAuth] Attempting token refresh. URL: ${refreshUrl}, Refresh token value: ${refreshTokenCookie.value.substring(0, 10)}...`);
        }

        const refreshResponse = await fetch(refreshUrl, {
          method: 'POST', 
          headers: {
            'Cookie': `statbus-refresh=${refreshTokenCookie.value}`
            // Ensure 'Origin' or other necessary headers for CSRF/CORS are not missing if your server expects them,
            // though for a server-to-server call like this, it's usually simpler.
          },
        });
        
        if (process.env.DEBUG === 'true') {
          console.log(`[AuthStore.handleServerAuth] Refresh API response status: ${refreshResponse.status}`);
        }

        if (!refreshResponse.ok) {
          let errorBody = 'Could not read error body';
          try {
            errorBody = await refreshResponse.text();
          } catch (readError) {
            console.error("AuthStore.handleServerAuth: Failed to read error response body:", readError);
          }
          console.error(`AuthStore.handleServerAuth: Refresh fetch failed: ${refreshResponse.status} ${refreshResponse.statusText}. Body: ${errorBody}`);
          responseCookies.delete('statbus');
          responseCookies.delete('statbus-refresh');
          return { status: { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_HTTP_ERROR' } };
        }

        // --- Process Successful Refresh ---
        let refreshData;
        let rawResponseText = ''; 
        try {
          // Read the response body as text first.
          rawResponseText = await refreshResponse.text(); 

          if (!rawResponseText) {
            // If the response body is empty, even for a 200 OK, treat it as a failure
            // because we expect a JSON payload (auth.auth_response).
            console.error(`AuthStore.handleServerAuth: Refresh response body is empty. Status: ${refreshResponse.status}. This indicates an issue with the /rpc/refresh endpoint not returning the expected auth_response JSON.`);
            responseCookies.delete('statbus');
            responseCookies.delete('statbus-refresh');
            return { status: { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_EMPTY_RESPONSE' } };
          }

          // If we have a non-empty body, try to parse it as JSON.
          refreshData = JSON.parse(rawResponseText);
        } catch (jsonError: any) {
          console.error(`AuthStore.handleServerAuth: Failed to parse JSON from refresh response. Status: ${refreshResponse.status}. Raw response text: "${rawResponseText}"`, jsonError);
          // If JSON parsing fails, treat as an error in refresh logic
          responseCookies.delete('statbus');
          responseCookies.delete('statbus-refresh');
          return { status: { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_JSON_PARSE_ERROR' } };
        }
        
        // _parseAuthStatusRpcResponseToAuthStatus returns the core fields, matching AuthStore's AuthStatus
        currentStatus = _parseAuthStatusRpcResponseToAuthStatus(refreshData); // This now includes error_code
        if (process.env.DEBUG === 'true') {
          console.log("[AuthStore.handleServerAuth] Status after parsing refresh response:", JSON.stringify(currentStatus));
        }

        if (!currentStatus.isAuthenticated && currentStatus.error_code && process.env.DEBUG === 'true') {
          console.warn(`[AuthStore.handleServerAuth] Refresh RPC returned unauthenticated with error_code: ${currentStatus.error_code}`);
        }

        // Cookies are set by the Set-Cookie headers from refreshResponse.
        // We need to parse them and apply to the outgoing `responseCookies`
        // that the middleware will use.
        const setCookieHeaders = refreshResponse.headers.getSetCookie(); 
        if (setCookieHeaders && setCookieHeaders.length > 0) {
          const parsedSetCookies = setCookie.parse(setCookieHeaders, { map: true });
          
          const newAccessTokenCookie = parsedSetCookies['statbus'];
          const newRefreshTokenCookie = parsedSetCookies['statbus-refresh'];

          if (newAccessTokenCookie?.value) {
            responseCookies.set('statbus', newAccessTokenCookie.value, {
              httpOnly: newAccessTokenCookie.httpOnly,
              secure: newAccessTokenCookie.secure ?? (process.env.NODE_ENV !== 'development'), 
              path: newAccessTokenCookie.path || '/',
              sameSite: (newAccessTokenCookie.sameSite as 'lax' | 'strict' | 'none') || 'lax',
              expires: newAccessTokenCookie.expires,
              maxAge: newAccessTokenCookie.maxAge,
            });
            if (!modifiedRequestHeaders) modifiedRequestHeaders = new Headers();
            modifiedRequestHeaders.set('X-Statbus-Refreshed-Token', newAccessTokenCookie.value);
          } else {
             console.warn("AuthStore.handleServerAuth: No 'statbus' access token in Set-Cookie after refresh.");
          }

          if (newRefreshTokenCookie?.value) {
            responseCookies.set('statbus-refresh', newRefreshTokenCookie.value, {
              httpOnly: newRefreshTokenCookie.httpOnly,
              secure: newRefreshTokenCookie.secure ?? (process.env.NODE_ENV !== 'development'),
              path: newRefreshTokenCookie.path || '/',
              sameSite: (newRefreshTokenCookie.sameSite as 'lax' | 'strict' | 'none') || 'lax',
              expires: newRefreshTokenCookie.expires,
              maxAge: newRefreshTokenCookie.maxAge,
            });
          } else {
            console.warn("AuthStore.handleServerAuth: No 'statbus-refresh' token in Set-Cookie after refresh.");
          }
          
          // If the new status from RPC indicates authenticated AND we got an access token cookie, it's a success.
          if (currentStatus.isAuthenticated && newAccessTokenCookie?.value) {
            if (process.env.DEBUG === 'true') {
              console.log("AuthStore.handleServerAuth: Refresh successful, new auth status parsed, cookies staged.");
            }
          } else {
            // If RPC says authenticated but no access token cookie, or RPC says not authenticated
            console.error(`AuthStore.handleServerAuth: Refresh issue. RPC status: ${currentStatus.isAuthenticated}, Access token cookie present: ${!!newAccessTokenCookie?.value}, Error code: ${currentStatus.error_code}`);
            // Preserve error_code if available from the parsed refreshData
            currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: currentStatus.error_code || 'REFRESH_POST_PROCESS_FAIL' }; 
            responseCookies.delete('statbus'); 
            responseCookies.delete('statbus-refresh');
          }

        } else {
           console.error("AuthStore.handleServerAuth: Refresh RPC response processed, but no Set-Cookie headers received from refreshResponse. This is unexpected if refresh was successful and returned authenticated.");
           currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_NO_SET_COOKIE' };
           responseCookies.delete('statbus');
           responseCookies.delete('statbus-refresh');
        }
      } catch (error) {
        console.error("AuthStore.handleServerAuth: Error during refresh fetch or processing:", error);
        responseCookies.delete('statbus');
        responseCookies.delete('statbus-refresh');
        currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_EXCEPTION' };
      }
    }

    // Return the determined status and any modifications needed
    return { status: currentStatus, modifiedRequestHeaders };
  }
}

// Export a singleton instance
export const authStore = AuthStore.getInstance();
