/**
 * Network diagnostics utility for troubleshooting connectivity issues
 * This file provides functions to test connectivity to various services
 */

/**
 * Tests connectivity to a URL and returns diagnostic information
 * @param url The URL to test
 * @param options Additional fetch options
 * @returns Diagnostic information about the connection attempt
 */
export async function testConnectivity(url: string, options: RequestInit = {}): Promise<{
  url: string;
  success: boolean;
  status?: number;
  statusText?: string;
  error?: string;
  responseText?: string;
  timing: {
    start: number;
    end: number;
    duration: number;
  };
}> {
  const start = Date.now();
  
  try {
    const response = await fetch(url, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      },
      ...options
    });
    
    const end = Date.now();
    let responseText = '';
    
    try {
      // Try to get some of the response text for diagnostics
      const reader = response.body?.getReader();
      if (reader) {
        const { value } = await reader.read();
        if (value) {
          responseText = new TextDecoder().decode(value).substring(0, 100);
          if (responseText.length === 100) {
            responseText += '...';
          }
        }
      }
    } catch (e) {
      responseText = 'Could not read response body';
    }
    
    return {
      url,
      success: response.ok,
      status: response.status,
      statusText: response.statusText,
      responseText,
      timing: {
        start,
        end,
        duration: end - start
      }
    };
  } catch (error) {
    const end = Date.now();
    return {
      url,
      success: false,
      error: error instanceof Error ? error.message : String(error),
      timing: {
        start,
        end,
        duration: end - start
      }
    };
  }
}

/**
 * Tests connectivity to all critical services and returns diagnostic information
 * @returns Diagnostic information about all connection attempts
 */
export async function runNetworkDiagnostics() {
  const serverApiUrl = process.env.SERVER_REST_URL;
  const browserApiUrl = process.env.NEXT_PUBLIC_BROWSER_REST_URL;
  
  const results = await Promise.all([
    serverApiUrl ? testConnectivity(serverApiUrl) : Promise.resolve({
      url: 'SERVER_REST_URL not set',
      success: false,
      error: 'Environment variable not set',
      timing: { start: 0, end: 0, duration: 0 }
    }),
    browserApiUrl ? testConnectivity(browserApiUrl) : Promise.resolve({
      url: 'NEXT_PUBLIC_BROWSER_REST_URL not set',
      success: false,
      error: 'Environment variable not set',
      timing: { start: 0, end: 0, duration: 0 }
    }),
    // Test local development API endpoint
    testConnectivity('http://localhost:8000/api').catch(() => ({
      url: 'http://localhost:8000/api',
      success: false,
      error: 'Could not connect to local development API',
      timing: { start: 0, end: 0, duration: 0 }
    }))
  ]);
  
  return {
    timestamp: new Date().toISOString(),
    environment: {
      serverApiUrl,
      browserApiUrl,
      nodeEnv: process.env.NODE_ENV,
      deploymentSlot: process.env.NEXT_PUBLIC_DEPLOYMENT_SLOT_CODE
    },
    results
  };
}
