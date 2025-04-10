/**
 * Sets up a global error handler to catch 401 Unauthorized errors
 * and dispatch a custom event that the auth context can listen for
 */
export function setupGlobalErrorHandler() {
  // Store the original fetch function
  const originalFetch = window.fetch;
  
  // Override the fetch function
  window.fetch = async function(input, init) {
    const response = await originalFetch.apply(this, [input, init]);
    
    if (response.status === 401) {
      // Dispatch a custom event that the auth context can listen for
      window.dispatchEvent(new CustomEvent('auth:401'));
    }
    
    return response;
  };
}
