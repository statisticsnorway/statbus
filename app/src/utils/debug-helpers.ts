/**
 * Utility functions for debugging and development
 */

/**
 * Safely logs API response details for debugging
 * Only logs in development environment
 * @param response The Response object to log
 * @param context A string describing the context of the response
 * @param logResponseBody Whether to clone and log the response body (defaults to false)
 */
export function logResponseDebug(response: Response, context: string = 'API Response', logResponseBody: boolean = false) {
  if (process.env.NODE_ENV !== 'development') {
    return;
  }
  
  try {
    // Use a unique ID for each debug log to help track multiple calls
    const debugId = Math.random().toString(36).substring(2, 8);
    console.group(`Debug: ${context} [${debugId}]`);
    console.debug('Status:', response.status, response.statusText);
    console.debug('Headers:', Object.fromEntries(response.headers.entries()));
    console.debug('URL:', response.url);
    console.debug('Type:', response.type);
    
    // If requested, clone the response and log its body
    // This is useful for debugging but should be used sparingly
    if (logResponseBody && response.bodyUsed === false) {
      try {
        // Clone the response so we don't consume the original
        const clonedResponse = response.clone();
        
        // Process based on content type
        const contentType = response.headers.get('Content-Type') || '';
        if (contentType.includes('application/json')) {
          // Use a simpler approach to avoid nesting issues
          clonedResponse.text().then(text => {
            try {
              if (text && text.trim()) {
                const data = JSON.parse(text);
                console.debug('Response Body:', data);
              } else {
                console.debug('Response Body: Empty response');
              }
            } catch (err) {
              console.debug('Response Body (raw):', text);
              console.debug('Could not parse response as JSON:', err);
            }
          }).catch(err => {
            console.debug('Could not read response body:', err);
          });
        } else {
          console.debug('Response Body: Not JSON content type, skipping body logging');
        }
      } catch (err) {
        console.debug('Error processing response body:', err);
      }
    }
    
    // Always end the console group at the end of the function
    // This ensures we don't have mismatched group/groupEnd calls
    console.groupEnd();
    return;
  } catch (error) {
    console.error('Error logging response debug info:', error);
    console.groupEnd();
  }
}

/**
 * Safely parses JSON with better error handling
 * Returns null if parsing fails
 */
export async function safeParseJSON(response: Response): Promise<any | null> {
  try {
    // First check if response is likely to contain JSON
    const contentType = response.headers.get('Content-Type');
    if (!contentType?.includes('application/json')) {
      console.warn(`Response doesn't appear to be JSON (Content-Type: ${contentType})`);
    }
    
    // Get text content first
    const text = await response.text();
    
    // Check if we have content to parse
    if (!text || text.trim() === '') {
      console.warn('Empty response body');
      return null;
    }
    
    // Try to parse the JSON
    return JSON.parse(text);
  } catch (error) {
    console.error('JSON parsing error:', error);
    return null;
  }
}
