/**
 * Utility for making authenticated requests
 * This centralizes the logic for API calls with proper auth handling
 */

// Avoid direct imports that only work in server components
// We'll use dynamic imports when needed

/**
 * Make an authenticated request
 * This function handles adding the auth token from cookies when in server context
 */
export async function serverFetch(
  url: string,
  options: RequestInit = {}
): Promise<Response> {
  try {
    // Create headers with default values if not provided
    const headers = new Headers(options.headers || {});
    
    // Set default headers if not provided
    if (!headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json');
    }
    if (!headers.has('Accept')) {
      headers.set('Accept', 'application/json');
    }
    
    // In server components, get the token from cookies
    if (typeof window === 'undefined') {
      try {
        // Use a function that safely gets cookies in server context
        const token = await getServerCookie('statbus');
        
        // Instead of setting Authorization header, pass the token as a cookie
        if (token) {
          // Create a cookie string
          const cookieHeader = headers.get('Cookie') || '';
          // Append our auth cookie to any existing cookies
          const newCookieHeader = cookieHeader 
            ? `${cookieHeader}; statbus=${token}`
            : `statbus=${token}`;
          
          headers.set('Cookie', newCookieHeader);
          
          // Only log in development mode and only for debugging purposes
          if (process.env.NODE_ENV === 'development' && process.env.DEBUG_AUTH === 'true') {
            console.log('Auth cookie added', {
              url: new URL(url.toString()).pathname
            });
          }
        } else {
          console.warn('No token available for server-side request to:', url.toString());
        }
      } catch (error) {
        console.warn('Could not access cookies in server component:', error);
        // Continue without the token
      }
    }
    
    // Make the request with credentials included
    const response = await fetch(url, {
      ...options,
      headers,
      credentials: 'include',
    });
    
    return response;
  } catch (error) {
    console.error('Server fetch error:', error);
    throw error;
  }
}

/**
 * Helper function to safely get cookies in server context
 * This uses dynamic imports to avoid issues with next/headers
 */
async function getServerCookie(name: string): Promise<string | null> {
  if (typeof window !== 'undefined') {
    return null; // Not in server context
  }
  
  try {
    // Dynamic import that will only execute in server components
    const { cookies } = await import('next/headers');
    const cookieStore = await cookies();
    const cookie = cookieStore.get(name);
    return cookie ? cookie.value : null;
  } catch (error) {
    console.warn(`Error getting cookie ${name}:`, error);
    return null;
  }
}
