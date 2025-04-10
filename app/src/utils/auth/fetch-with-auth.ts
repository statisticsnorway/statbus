import { refreshToken } from '@/services/auth';

/**
 * Custom fetch function that handles token refresh automatically
 * If a request returns 401 Unauthorized, it will attempt to refresh the token
 * and retry the original request
 */
export async function fetchWithAuth(
  url: string, 
  options: RequestInit = {}
): Promise<Response> {
  // First attempt with current token
  let response = await fetch(url, {
    ...options,
    credentials: 'include', // Always include cookies
  });
  
  // If we get a 401 Unauthorized, try to refresh the token
  if (response.status === 401) {
    try {
      // Try to refresh the token
      const refreshResponse = await refreshToken();
      
      if (!refreshResponse.error) {
        // Retry the original request with the new token
        response = await fetch(url, {
          ...options,
          credentials: 'include',
        });
      } else {
        // If refresh failed, dispatch an event for the auth context to handle
        window.dispatchEvent(new CustomEvent('auth:logout', { 
          detail: { reason: 'refresh_failed' } 
        }));
      }
    } catch (error) {
      console.error('Error refreshing token:', error);
      // Dispatch an event for the auth context to handle
      window.dispatchEvent(new CustomEvent('auth:logout', { 
        detail: { reason: 'refresh_error', error } 
      }));
    }
  }
  
  return response;
}
