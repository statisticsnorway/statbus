/**
 * Utility functions for authentication
 */

/**
 * Check if the user is authenticated
 * This function uses the AuthStore to get the authentication status
 */
export async function isAuthenticated(): Promise<boolean> {
  try {
    // For server-side requests, check if we can access the token directly
    if (typeof window === 'undefined') {
      try {
        // Use dynamic import to avoid issues with next/headers
        const { cookies } = await import('next/headers');
        const cookieStore = await cookies();
        const token = cookieStore.get('statbus');
        
        // Simple check - if token exists, user is authenticated
        return !!token;
      } catch (error) {
        console.error('Error accessing cookies in server component:', error);
        // Fall back to AuthStore if cookies can't be accessed
      }
    }
    
    // Import the authStore
    const { authStore } = await import('@/context/AuthStore');
    
    // Get the authentication status from the store
    const authStatus = await authStore.getAuthStatus();
    
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
  // Import and clear the AuthStore cache
  import('@/context/AuthStore').then(({ authStore }) => {
    authStore.clearCache();
  }).catch(err => {
    console.error('Failed to clear auth cache:', err);
  });
  
  // Also clear the client, time context and base data caches when auth cache is cleared
  // We'll import dynamically to avoid circular dependencies
  if (typeof window !== 'undefined') {
    // Only run this in the browser
    import('@/context/TimeContextStore').then(({ timeContextStore }) => {
      timeContextStore.clearCache();
    }).catch(err => {
      console.error('Failed to clear time context cache:', err);
    });
    
    import('@/context/BaseDataStore').then(({ baseDataStore }) => {
      baseDataStore.clearCache();
    }).catch(err => {
      console.error('Failed to clear base data cache:', err);
    });
    
    import('@/context/ClientStore').then(({ clientStore }) => {
      clientStore.clearCache();
    }).catch(err => {
      console.error('Failed to clear client cache:', err);
    });
  }
}
