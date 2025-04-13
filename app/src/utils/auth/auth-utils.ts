/**
 * Utility functions for authentication
 */
import { getAuthStatus } from '@/services/auth';

// Cache the authentication status for a short period to avoid excessive API calls
let authStatusCache: { 
  isAuthenticated: boolean;
  user: any | null;
  tokenExpiring: boolean;
  timestamp: number;
} | null = null;

const CACHE_TTL = 30000; // 30 seconds

/**
 * Check if the user is authenticated
 * This function caches the result for a short period to avoid excessive API calls
 */
export async function isAuthenticated(): Promise<boolean> {
  const now = Date.now();
  
  // Use cached value if available and not expired
  if (authStatusCache && (now - authStatusCache.timestamp < CACHE_TTL)) {
    return authStatusCache.isAuthenticated;
  }
  
  // For server-side, check cookies directly
  if (typeof window === 'undefined') {
    try {
      const { cookies } = await import('next/headers');
      const cookieStore = await cookies();
      const token = cookieStore.get('statbus');
      const isAuthenticated = !!token;
      
      // Log authentication status for debugging
      if (process.env.NODE_ENV === 'development') {
        console.log('Server-side auth check via cookies:', { 
          isAuthenticated, 
          hasToken: !!token,
          tokenPrefix: token ? token.value.substring(0, 10) + '...' : null
        });
      }
      
      // Cache the result
      authStatusCache = {
        isAuthenticated,
        user: null,
        tokenExpiring: false,
        timestamp: now
      };
      
      return isAuthenticated;
    } catch (error) {
      console.error('Error checking server-side authentication:', error);
      // Fall back to API call if cookies can't be accessed
    }
  }
  
  // Get fresh authentication status from API
  try {
    const authStatus = await getAuthStatus();
    
    // Cache the full result
    authStatusCache = {
      ...authStatus,
      timestamp: now
    };
    
    return authStatus.isAuthenticated;
  } catch (error) {
    console.error('Error checking authentication status:', error);
    return false;
  }
}

/**
 * Clear the authentication status cache
 * Call this when logging in or out to ensure fresh status
 */
export function clearAuthStatusCache(): void {
  authStatusCache = null;
  
  // Also clear the time context cache when auth cache is cleared
  // We'll import dynamically to avoid circular dependencies
  if (typeof window !== 'undefined') {
    // Only run this in the browser
    import('@/context/TimeContextStore').then(({ timeContextStore }) => {
      timeContextStore.clearCache();
    }).catch(err => {
      console.error('Failed to clear time context cache:', err);
    });
  }
}
