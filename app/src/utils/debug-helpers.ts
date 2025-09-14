import { logger } from "@/lib/client-logger";

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
  // The logger's debug method already handles the visibility check, but we also
  // keep the NODE_ENV check to ensure this is completely stripped from production.
  if (process.env.NODE_ENV !== 'development') {
    return;
  }
  
  try {
    // Use a unique ID for each debug log to help track multiple calls.
    const debugId = Math.random().toString(36).substring(2, 8);
    const logContext = `${context}:${debugId}`;

    logger.debug(logContext, 'Status:', response.status, response.statusText);
    logger.debug(logContext, 'Headers:', Object.fromEntries(response.headers.entries()));
    logger.debug(logContext, 'URL:', response.url);
    logger.debug(logContext, 'Type:', response.type);
    
    // If requested, clone the response and log its body.
    if (logResponseBody && response.bodyUsed === false) {
      try {
        const clonedResponse = response.clone();
        const contentType = response.headers.get('Content-Type') || '';

        if (contentType.includes('application/json')) {
          clonedResponse.text().then(text => {
            try {
              if (text && text.trim()) {
                const data = JSON.parse(text);
                logger.debug(logContext, 'Response Body:', data);
              } else {
                logger.debug(logContext, 'Response Body: Empty response');
              }
            } catch (err) {
              logger.debug(logContext, 'Response Body (raw):', text);
              logger.debug(logContext, 'Could not parse response as JSON:', err);
            }
          }).catch(err => {
            logger.debug(logContext, 'Could not read response body:', err);
          });
        } else {
          logger.debug(logContext, 'Response Body: Not JSON content type, skipping body logging');
        }
      } catch (err) {
        logger.debug(logContext, 'Error processing response body:', err);
      }
    }
  } catch (error) {
    logger.error('logResponseDebug', 'Error logging response debug info:', error);
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
      logger.warn('safeParseJSON', `Response doesn't appear to be JSON (Content-Type: ${contentType})`);
    }
    
    // Get text content first
    const text = await response.text();
    
    // Check if we have content to parse
    if (!text || text.trim() === '') {
      logger.warn('safeParseJSON', 'Empty response body');
      return null;
    }
    
    // Try to parse the JSON
    return JSON.parse(text);
  } catch (error) {
    logger.error('safeParseJSON', 'JSON parsing error:', error);
    return null;
  }
}
