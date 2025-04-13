/**
 * Authentication service for direct interaction with the PostgREST API
 */
import { logResponseDebug, safeParseJSON } from '@/utils/debug-helpers';

/**
 * Get the current authentication status from the server
 */
import { clearAuthStatusCache } from '@/utils/auth/auth-utils';

// Import the shared cache from auth-utils
// We'll use the cache from auth-utils.ts instead of maintaining our own

export async function getAuthStatus() {
  console.log('Explicit auth_status check called');
  
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
        
        console.log(`Server-side auth check: ${result.isAuthenticated ? 'Token found' : 'No token'}`);
        
        // If authenticated, ensure we have a valid client ready
        if (result.isAuthenticated) {
          try {
            const { getServerClient } = await import('@/utils/auth/postgrest-client-server');
            await getServerClient();
          } catch (error) {
            console.error('Failed to initialize server client during auth check:', error);
          }
        }
        
        return result;
      } catch (error) {
        console.error('Error accessing cookies in server component:', error);
        // Fall back to API call if cookies can't be accessed
      }
    }
    
    // Always use the proxy URL for consistency in development
    // In development, this should be the Next.js app URL which proxies to PostgREST
    const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
      ? '' // Use relative URL to ensure we hit the same origin
      : (typeof window !== 'undefined' 
          ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
          : process.env.SERVER_API_URL);
      
    const apiEndpoint = `${apiUrl}/postgrest/rpc/auth_status`;
    console.log(`Checking auth status at ${apiEndpoint}`);
    
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
    
    // Log response details in development for debugging
    if (process.env.NODE_ENV === 'development') {
      console.debug('Auth status response:', {
        status: response.status,
        contentType,
        contentLength,
        headers: Object.fromEntries(response.headers.entries())
      });
    }
    
    // Handle empty responses (which would cause JSON parse errors)
    if (contentLength === '0' || !contentType?.includes('application/json')) {
      console.warn('Auth status endpoint returned empty or non-JSON response');
      return {
        isAuthenticated: false,
        user: null,
        tokenExpiring: false
      };
    }
    
    // Only log response details in development if explicitly enabled
    if (process.env.DEBUG_AUTH === 'true') {
      logResponseDebug(response, 'Auth Status', true);
    }
    
    // Safely parse the JSON response
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
    
    if (process.env.NODE_ENV === 'development') {
      console.log('Auth status response data:', data);
      console.log('Is authenticated:', isAuthenticated);
    }
    
    const result = {
      isAuthenticated,
      user: data.user || null,
      tokenExpiring: data.token_expiring === true || data.tokenExpiring === true
    };
    
    // We don't need to cache here as auth-utils.ts will handle caching
    
    return result;
  } catch (error) {
    console.error('Error checking auth status:', error);
    return { isAuthenticated: false, user: null, tokenExpiring: false };
  }
}

/**
 * Login with email and password
 * This calls the PostgreSQL login function directly via PostgREST
 */
export async function login(email: string, password: string) {
  // Always use the proxy URL for consistency in development
  const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
    ? '' // Use relative URL to ensure we hit the same origin
    : (typeof window !== 'undefined' 
        ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
        : process.env.SERVER_API_URL);
      
  const response = await fetch(`${apiUrl}/postgrest/rpc/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify({ email, password }),
    credentials: 'include' // Important for cookies
  });
  
  // Log response details in development
  logResponseDebug(response, 'Login');
  
  if (!response.ok) {
    const errorData = await safeParseJSON(response) || { message: 'Login failed' };
    throw new Error(errorData.message || 'Login failed');
  }
  
  return safeParseJSON(response);
}

/**
 * Logout the current user
 * This calls the PostgreSQL logout function directly via PostgREST
 */
export async function logout() {
  // Always use the proxy URL for consistency in development
  const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
    ? '' // Use relative URL to ensure we hit the same origin
    : (typeof window !== 'undefined' 
        ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
        : process.env.SERVER_API_URL);
    
  const response = await fetch(`${apiUrl}/postgrest/rpc/logout`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    credentials: 'include'
  });
  
  // Log response details in development
  logResponseDebug(response, 'Logout');
  
  // Clear the auth cache when logging out
  clearAuthStatusCache();
  
  // The TimeContextStore cache will be cleared by clearAuthStatusCache
  
  return safeParseJSON(response);
}

/**
 * Refresh the authentication token
 * This calls the PostgreSQL refresh function directly via PostgREST
 */
export async function refreshToken() {
  // Always use the proxy URL for consistency in development
  const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
    ? '' // Use relative URL to ensure we hit the same origin
    : (typeof window !== 'undefined' 
        ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
        : process.env.SERVER_API_URL);
    
  const response = await fetch(`${apiUrl}/postgrest/rpc/refresh`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    credentials: 'include',
    ...(typeof window !== 'undefined' ? { mode: 'cors' } : {})
  });
  
  // Log response details in development
  logResponseDebug(response, 'Refresh Token');
  
  return safeParseJSON(response);
}

/**
 * List all active sessions for the current user
 */
export async function listActiveSessions() {
  // Always use the proxy URL for consistency in development
  const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
    ? '' // Use relative URL to ensure we hit the same origin
    : (typeof window !== 'undefined' 
        ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
        : process.env.SERVER_API_URL);
    
  const response = await fetch(`${apiUrl}/postgrest/rpc/list_active_sessions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    credentials: 'include',
    ...(typeof window !== 'undefined' ? { mode: 'cors' } : {})
  });
  
  // Log response details in development
  logResponseDebug(response, 'List Active Sessions');
  
  return safeParseJSON(response);
}

/**
 * Revoke a specific session
 */
export async function revokeSession(sessionId: string) {
  // Always use the proxy URL for consistency in development
  const apiUrl = process.env.NODE_ENV === 'development' && typeof window !== 'undefined'
    ? '' // Use relative URL to ensure we hit the same origin
    : (typeof window !== 'undefined' 
        ? process.env.NEXT_PUBLIC_BROWSER_API_URL 
        : process.env.SERVER_API_URL);
    
  const response = await fetch(`${apiUrl}/postgrest/rpc/revoke_session`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json'
    },
    body: JSON.stringify({ refresh_session_jti: sessionId }),
    credentials: 'include',
    ...(typeof window !== 'undefined' ? { mode: 'cors' } : {})
  });
  
  // Log response details in development
  logResponseDebug(response, 'Revoke Session');
  
  return safeParseJSON(response);
}
