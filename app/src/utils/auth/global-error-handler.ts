/**
 * Sets up a global error handler to catch 401 Unauthorized errors
 * and dispatch a custom event that the auth context can listen for
 */
export function setupGlobalErrorHandler() {
  // Store the original fetch function
  const originalFetch = window.fetch;
  
  // Override the fetch function
  window.fetch = async function(input, init) {
    try {
      // Add credentials include by default for all requests to our API
      const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
      
      // If this is a request to our API, ensure credentials are included
      if (url.includes('/postgrest/')) {
        init = {
          ...init,
          credentials: 'include',
          headers: {
            ...init?.headers,
            'Content-Type': 'application/json',
            'Accept': 'application/json'
          }
        };
      }
      
      const response = await originalFetch.apply(this, [input, init]);
      
      if (response.status === 401) {
        // Dispatch a custom event that the auth context can listen for
        window.dispatchEvent(new CustomEvent('auth:401', {
          detail: {
            url,
            status: response.status
          }
        }));
      }
      
      return response;
    } catch (error) {
      console.error('Fetch error:', error);
      throw error;
    }
  };
}
