/**
 * Authentication service for direct interaction with the PostgREST API
 */
import { logResponseDebug, safeParseJSON } from '@/utils/debug-helpers';

/**
 * Get the current authentication status from the server
 */
import { clearAuthStatusCache } from '@/utils/auth/auth-utils';

export async function getAuthStatus() {
  console.log('Explicit auth_status check called');
  
  try {
    // Import the authStore
    const { authStore } = await import('@/context/AuthStore');
    
    // Get the authentication status from the store
    return await authStore.getAuthStatus();
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
  
  // Update the auth store with the new status
  try {
    const { authStore } = await import('@/context/AuthStore');
    await authStore.refreshAuthStatus();
  } catch (error) {
    console.error('Failed to update auth store after login:', error);
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
  
  // Update the auth store with the new status
  try {
    const { authStore } = await import('@/context/AuthStore');
    authStore.updateAuthStatus({
      isAuthenticated: false,
      user: null,
      tokenExpiring: false
    });
  } catch (error) {
    console.error('Failed to update auth store after logout:', error);
  }
  
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
