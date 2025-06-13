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
      // Get the appropriate client based on environment
      const { getRestClient } = await import("@/context/RestClientStore");
      const client = await getRestClient(); // This will be a server client if called from handleServerAuth
      
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
      const allCookiesForLog = requestCookies.getAll().map(c => ({ name: c.name, value: c.value.startsWith('eyJ') ? `${c.value.substring(0,15)}...` : c.value }));
      console.log("[AuthStore.handleServerAuth] Entry. Request cookies:", JSON.stringify(allCookiesForLog));
      const accessToken = requestCookies.get('statbus');
      if (accessToken && accessToken.value) {
        console.log(`[AuthStore.handleServerAuth] Access token ('statbus' cookie) found in request: ${accessToken.value.substring(0, 20)}...`);
      } else {
        console.log("[AuthStore.handleServerAuth] No access token ('statbus' cookie) found in request cookies.");
      }
    }

    let currentStatus = await this.getAuthStatus(); 
    if (process.env.DEBUG === 'true') {
      console.log("[AuthStore.handleServerAuth] Status from getAuthStatus() (which calls /rpc/auth_status):", JSON.stringify(currentStatus));
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

        const constructedRefreshHeaders: HeadersInit = {
          'Cookie': `statbus-refresh=${refreshTokenCookie.value}`,
          // Add any other headers PostgREST might expect for server-to-server RPC, though usually minimal.
          // 'Content-Type': 'application/json', // Usually not needed for POST to RPC if no body, but PostgREST might be strict.
        };
        if (process.env.DEBUG === 'true') {
          console.log(`[AuthStore.handleServerAuth] Headers being sent to internal /rpc/refresh:`, JSON.stringify(constructedRefreshHeaders));
        }

        const refreshResponse = await fetch(refreshUrl, {
          method: 'POST', 
          headers: constructedRefreshHeaders,
        });
        
        if (process.env.DEBUG === 'true') {
          console.log(`[AuthStore.handleServerAuth] Internal /rpc/refresh API response status: ${refreshResponse.status}`);
        }

        // ALWAYS process Set-Cookie headers from the refreshResponse first.
        // This ensures that whatever public.refresh decided about cookies (set new, clear old)
        // is staged to be sent back to the browser.
        const setCookieHeaders = refreshResponse.headers.getSetCookie();
        if (setCookieHeaders && setCookieHeaders.length > 0) {
          const parsedSetCookies = setCookie.parse(setCookieHeaders);
          
          parsedSetCookies.forEach(cookieObject => {
            const options: Parameters<typeof responseCookies.set>[2] = {
              httpOnly: cookieObject.httpOnly,
              secure: cookieObject.secure ?? (process.env.NODE_ENV !== 'development'), // Default to secure if not specified and not in dev
              path: cookieObject.path || '/', // Default path
              sameSite: (cookieObject.sameSite?.toLowerCase() as 'lax' | 'strict' | 'none' | undefined) || 'lax', // Default SameSite
              expires: cookieObject.expires, // Will be undefined if not set
              maxAge: cookieObject.maxAge,   // Will be undefined if not set
            };
            // Remove undefined options to avoid issues with Next.js cookie setting
            // This ensures that only explicitly provided attributes are set.
            Object.keys(options).forEach(keyStr => {
              const key = keyStr as keyof typeof options;
              if (options[key] === undefined) {
                delete options[key];
              }
            });
            
            if (process.env.DEBUG === 'true') {
              console.log(`[AuthStore.handleServerAuth] Staging Set-Cookie for browser: Name=${cookieObject.name}, Value=${cookieObject.value.substring(0,15)}..., Options=${JSON.stringify(options)}`);
            }
            responseCookies.set(cookieObject.name, cookieObject.value, options);

            if (cookieObject.name === 'statbus' && cookieObject.value) { // 'statbus' is the access token cookie
              if (!modifiedRequestHeaders) modifiedRequestHeaders = new Headers();
              // Store the new access token to be available for the current request processing if needed.
              modifiedRequestHeaders.set('X-Statbus-Refreshed-Token', cookieObject.value);
            }
          });
          if (process.env.DEBUG === 'true') {
            console.log("[AuthStore.handleServerAuth] Applied Set-Cookie headers from refresh response to outgoing response cookies.");
          }
        } else {
          if (process.env.DEBUG === 'true') {
            console.log("[AuthStore.handleServerAuth] No Set-Cookie headers received from refresh response.");
          }
        }

        // Now, determine the application's view of the auth status based on the response body and HTTP status.
        if (!refreshResponse.ok) {
          let errorBodyText = 'Could not read error body';
          let parsedErrorBody: any = null;
          let errorCodeFromServer: string | null = null;
          try {
            errorBodyText = await refreshResponse.text();
            if (errorBodyText) {
              parsedErrorBody = JSON.parse(errorBodyText);
              errorCodeFromServer = parsedErrorBody?.error_code || null;
            }
          } catch (parseError) {
            console.error("AuthStore.handleServerAuth: Failed to parse JSON from error response body:", parseError, "Raw error body:", errorBodyText);
          }
          
          console.error(`AuthStore.handleServerAuth: Refresh fetch failed (HTTP status not OK): ${refreshResponse.status} ${refreshResponse.statusText}. Error Code: ${errorCodeFromServer || 'N/A'}. Body: ${errorBodyText}`);
          // Backend is responsible for cookie clearing via Set-Cookie, so no direct delete here.
          currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: errorCodeFromServer || 'REFRESH_HTTP_ERROR' };
          return { status: currentStatus, modifiedRequestHeaders }; // Return early as body processing below is not relevant for error status
        }

        // --- Process Successful HTTP Refresh (status OK) ---
        let refreshData;
        let rawResponseText = ''; 
        try {
          rawResponseText = await refreshResponse.text(); 

          if (!rawResponseText) {
            console.error(`AuthStore.handleServerAuth: Refresh response body is empty despite HTTP ${refreshResponse.status}. This indicates an issue with the /rpc/refresh endpoint not returning the expected auth_response JSON.`);
            // Backend is responsible for cookie clearing. If it sent 200 OK with empty body and didn't clear cookies, that's a backend issue.
            currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_EMPTY_RESPONSE' };
          } else {
            refreshData = JSON.parse(rawResponseText);
            currentStatus = _parseAuthStatusRpcResponseToAuthStatus(refreshData);
          }
        } catch (jsonError: any) {
          console.error(`AuthStore.handleServerAuth: Failed to parse JSON from refresh response (HTTP status ${refreshResponse.status}). Raw response text: "${rawResponseText}"`, jsonError);
          // Backend is responsible for cookie clearing.
          currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_JSON_PARSE_ERROR' };
        }
        
        if (process.env.DEBUG === 'true') {
          console.log("[AuthStore.handleServerAuth] Status after parsing refresh response body:", JSON.stringify(currentStatus));
        }

        if (!currentStatus.isAuthenticated && currentStatus.error_code && process.env.DEBUG === 'true') {
          console.warn(`[AuthStore.handleServerAuth] Refresh RPC returned unauthenticated with error_code: ${currentStatus.error_code}`);
        }
        // The success of the refresh in terms of application state is now in currentStatus.
        // Cookie management has been handled by processing Set-Cookie headers.

      } catch (error) { // This outer catch handles errors from the fetch call itself or initial Set-Cookie processing.
        console.error("AuthStore.handleServerAuth: Error during refresh fetch or initial processing:", error);
        // Backend is responsible for cookie clearing. If fetch fails, cookies on browser are unchanged by this attempt.
        currentStatus = { isAuthenticated: false, user: null, tokenExpiring: false, error_code: 'REFRESH_EXCEPTION' };
      }
    }

    return { status: currentStatus, modifiedRequestHeaders };
  }
}

export const authStore = AuthStore.getInstance();
