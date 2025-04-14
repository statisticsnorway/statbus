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
  id: string;
  email: string;
  role: string;
  statbus_role: string;
}

/**
 * Authentication status type
 */
export interface AuthStatus {
  isAuthenticated: boolean;
  user: User | null;
  tokenExpiring: boolean;
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

    // Also clear the client, time context and base data caches when auth cache is cleared
    // We'll import dynamically to avoid circular dependencies
    if (typeof window !== "undefined") {
      // Only run this in the browser
      import("@/context/TimeContextStore")
        .then(({ timeContextStore }) => {
          timeContextStore.clearCache();
        })
        .catch((err) => {
          console.error("Failed to clear time context cache:", err);
        });

      import("@/context/BaseDataStore")
        .then(({ baseDataStore }) => {
          baseDataStore.clearCache();
        })
        .catch((err) => {
          console.error("Failed to clear base data cache:", err);
        });

      import("@/context/ClientStore")
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
   * Returns success status and new tokens if refreshed
   */
  public async refreshTokenIfNeeded(): Promise<{
    success: boolean;
    newTokens?: { accessToken: string; refreshToken: string };
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

      // Check if we're on the server or client
      if (typeof window === "undefined") {
        try {
          // Get cookies for server-side refresh
          const { cookies } = await import("next/headers");
          const cookieStore = await cookies();
          const refreshToken = cookieStore.get("statbus-refresh");

          // No refresh token
          if (!refreshToken) {
            return { success: false };
          }

          // Call the refresh endpoint
          const apiUrl = process.env.SERVER_API_URL;
          const response = await fetch(`${apiUrl}/postgrest/rpc/refresh`, {
            method: "POST",
            headers: {
              Authorization: `Bearer ${refreshToken.value}`,
              "Content-Type": "application/json",
            },
            credentials: "include",
          });

          if (response.ok) {
            // Extract the new tokens from the response
            const cookies = response.headers.getSetCookie();

            // Extract token values for potential use in the current request
            const newAccessToken = this.extractTokenFromCookies(
              cookies,
              "statbus"
            );
            const newRefreshToken = this.extractTokenFromCookies(
              cookies,
              "statbus-refresh"
            );

            // Clear auth cache to ensure fresh status on next check
            this.clearAllCaches();

            return {
              success: true,
              newTokens: {
                accessToken: newAccessToken,
                refreshToken: newRefreshToken,
              },
            };
          }

          // Refresh failed
          return { success: false };
        } catch (error) {
          console.error("Error refreshing token on server:", error);
          return { success: false };
        }
      } else {
        // Client-side refresh
        const { refreshToken } = await import("@/services/auth");
        const result = await refreshToken();

        // Clear auth cache to ensure fresh status on next check
        if (!result.error) {
          this.clearAllCaches();
        }

        return { success: !result.error };
      }
    } catch (error) {
      console.error("Error in refreshTokenIfNeeded:", error);
      return { success: false };
    }
  }

  /**
   * Helper function to extract token from Set-Cookie headers
   */
  private extractTokenFromCookies(cookies: string[], name: string): string {
    for (const cookie of cookies) {
      if (cookie.startsWith(`${name}=`)) {
        const match = cookie.match(new RegExp(`${name}=([^;]+)`));
        if (match && match[1]) {
          return match[1];
        }
      }
    }
    return "";
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

  /**
   * Internal method to fetch auth status from API
   * This is the definitive source of truth for authentication status
   */
  private async fetchAuthStatus(): Promise<AuthStatus> {
    try {
      // Always use the auth_status endpoint for accurate authentication status
      // Don't rely on cookie presence as a shortcut

      // Always use the proxy URL for consistency in development
      const apiUrl =
        process.env.NODE_ENV === "development" && typeof window !== "undefined"
          ? "" // Use relative URL to ensure we hit the same origin
          : typeof window !== "undefined"
            ? process.env.NEXT_PUBLIC_BROWSER_API_URL
            : process.env.SERVER_API_URL;

      const apiEndpoint = `${apiUrl}/postgrest/rpc/auth_status`;

      // Make the authenticated request directly
      const headers = new Headers({
        "Content-Type": "application/json",
        Accept: "application/json",
      });

      // In server components, get the token from cookies
      if (typeof window === "undefined") {
        const { cookies } = await import("next/headers");
        const cookieStore = await cookies();
        const token = cookieStore.get("statbus");

        if (token) {
          // Add the token as a cookie header
          headers.set("Cookie", `statbus=${token.value}`);
        }
      }

      const response = await fetch(apiEndpoint, {
        method: "GET",
        headers,
        credentials: "include", // Always include cookies
      });

      if (!response.ok) {
        console.error(
          `Auth status check failed: ${response.status} ${response.statusText}`
        );
        return { isAuthenticated: false, user: null, tokenExpiring: false };
      }

      // Safely parse the JSON response - this handles empty or non-JSON responses
      const { safeParseJSON } = await import("@/utils/debug-helpers");
      const data = await safeParseJSON(response);

      const result =
        data === null
          ? {
              isAuthenticated: false,
              user: null,
              tokenExpiring: false,
            }
          : {
              isAuthenticated: data.isAuthenticated,
              user: data.user || null,
              tokenExpiring:
                data.token_expiring === true || data.tokenExpiring === true,
            };

      if (process.env.NODE_ENV === "development") {
        console.log(`Checked auth status`, {
          url: apiEndpoint,
          user: data.user || null,
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
