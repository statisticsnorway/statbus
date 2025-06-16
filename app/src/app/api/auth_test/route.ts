import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { getServerRestClient } from '@/context/RestClientStore'; // Assuming this path
import { Agent } from 'undici';
import type { Database } from '@/lib/database.types';

// Define the expected response structure from the auth.auth_test_response PG type
// This is based on doc/db/function/public_auth_test().md
interface AuthTestDbResponse {
  headers: Record<string, any> | null;
  cookies: Record<string, any> | null;
  claims: Record<string, any> | null;
  access_token: {
    present: boolean;
    token_length: number | null;
    valid: boolean | null;
    expired: boolean | null;
    claims: Record<string, any> | null;
  } | null;
  refresh_token: {
    present: boolean;
    token_length: number | null;
    valid: boolean | null;
    expired: boolean | null;
    claims: Record<string, any> | null;
    jti: string | null;
    version: string | null;
  } | null;
  timestamp: string | null;
  deployment_slot: string | null;
  is_https: boolean | null;
}

export async function GET(request: NextRequest) {
  const cookieStore = await cookies();
  const allIncomingCookies = cookieStore.getAll().reduce((acc, cookie) => {
    acc[cookie.name] = cookie.value;
    return acc;
  }, {} as Record<string, string>);
 
  // Log the SERVER_REST_URL to verify its configuration
  const serverRestUrlEnv = process.env.SERVER_REST_URL;
  if (process.env.NODE_ENV === 'development' || process.env.DEBUG === 'true') {
   console.log(`[AuthTestAPI] SERVER_REST_URL: ${serverRestUrlEnv}`);
  }
 
  const incomingHeaders: Record<string, string> = {};
  request.headers.forEach((value, key) => {
    // Only include relevant headers for brevity, or filter sensitive ones
    if (key.toLowerCase().startsWith('x-') || ['user-agent', 'accept', 'host', 'cookie'].includes(key.toLowerCase())) {
      incomingHeaders[key] = value;
    }
  });
  
  const responsePayload: Record<string, any> = {
    message: "Auth Test API Endpoint Results",
    incoming_request_to_nextjs_api: {
      url: request.url,
      method: request.method,
      headers: incomingHeaders, // Headers received by this Next.js API route
      cookies: allIncomingCookies, // Cookies received by this Next.js API route
    },
    postgrest_js_call_to_rpc_auth_test: {},
    direct_fetch_call_to_rpc_auth_test: {},
  };

  // Method 1: Using postgrest-js (via getServerRestClient)
  try {
    const client = await getServerRestClient(); // Uses http://proxy:80/rest
    if (!client) {
      throw new Error('Failed to initialize server RestClient');
    }
    // The rpc method in postgrest-js for a function that returns a single row
    // will typically return the row object directly in `data`, not an array.
    const { data, error } = await client.rpc('auth_test');
    
    if (error) {
      console.error('Error from postgrest-js rpc(auth_test):', error);
      responsePayload.postgrest_js_call_to_rpc_auth_test = {
        status: 'error',
        error: { message: error.message, details: error.details, hint: error.hint, code: error.code },
      };
    } else {
      responsePayload.postgrest_js_call_to_rpc_auth_test = {
        status: 'success',
        data: data as AuthTestDbResponse, // data should be AuthTestDbResponse
      };
     if (process.env.NODE_ENV === 'development' || process.env.DEBUG === 'true') {
       responsePayload.postgrest_js_call_to_rpc_auth_test.debug_server_rest_url_used = serverRestUrlEnv; // Add which URL was used
     }
    }
  } catch (e: any) {
    console.error('Exception during postgrest-js call:', e);
    responsePayload.postgrest_js_call_to_rpc_auth_test = {
      status: 'exception',
      error: { message: e.message, stack: e.stack },
    };
  }

  // Method 2: Direct fetch to http://proxy:80/rest/rpc/auth_test
  const directFetchUrl = 'http://proxy:80/rest/rpc/auth_test';

  // Create an explicit Undici agent for direct fetch calls
  const undiciAgent = new Agent({
    connect: { timeout: 5000 }, // 5-second connect timeout
    // keepAliveTimeout: 4000, // Optional: shorter keep-alive than default
    // keepAliveMaxTimeout: 60000, // Optional: max keep-alive
  });


  // Diagnostic: Simple fetch to proxy root to test basic connectivity
  try {
    console.log("Attempting simple diagnostic GET to http://proxy:80/ using undici.Agent");
    const diagnosticResponse = await fetch('http://proxy:80/', { 
      method: 'GET',
      // @ts-ignore Property 'dispatcher' does exist on 'RequestInit'. Next.js's bundled TS types for fetch might be slightly different or undici types not fully aligned with global Fetch API types.
      dispatcher: undiciAgent 
    });
    console.log(`Diagnostic GET to http://proxy:80/ status: ${diagnosticResponse.status}`);
    const diagnosticText = await diagnosticResponse.text();
    console.log(`Diagnostic GET to http://proxy:80/ text: ${diagnosticText.substring(0, 200)}...`);
    responsePayload.diagnostic_simple_fetch_to_proxy_root = {
      status_code: diagnosticResponse.status,
      status_text: diagnosticResponse.statusText,
      body_snippet: diagnosticText.substring(0, 200) + (diagnosticText.length > 200 ? "..." : "")
    };
  } catch (diagErr: any) {
    console.error('Exception during diagnostic simple GET to http://proxy:80/:', diagErr);
    responsePayload.diagnostic_simple_fetch_to_proxy_root = {
      status: 'exception',
      error: { message: diagErr.message, stack: diagErr.stack },
    };
  }
  // End Diagnostic with explicit agent

  // Diagnostic: Simple fetch to proxy root WITHOUT explicit agent
  if (process.env.NODE_ENV === 'development' || process.env.DEBUG === 'true') {
    try {
      console.log("Attempting simple diagnostic GET to http://proxy:80/ using GLOBAL fetch agent");
      const diagnosticResponseGlobalAgent = await fetch('http://proxy:80/', { 
        method: 'GET',
        // No explicit dispatcher/agent here
      });
      console.log(`Diagnostic GET (global agent) to http://proxy:80/ status: ${diagnosticResponseGlobalAgent.status}`);
      const diagnosticTextGlobalAgent = await diagnosticResponseGlobalAgent.text();
      console.log(`Diagnostic GET (global agent) to http://proxy:80/ text: ${diagnosticTextGlobalAgent.substring(0, 200)}...`);
      responsePayload.diagnostic_simple_fetch_to_proxy_root_global_agent = {
        status_code: diagnosticResponseGlobalAgent.status,
        status_text: diagnosticResponseGlobalAgent.statusText,
        body_snippet: diagnosticTextGlobalAgent.substring(0, 200) + (diagnosticTextGlobalAgent.length > 200 ? "..." : "")
      };
    } catch (diagGlobErr: any) {
      console.error('Exception during diagnostic simple GET (global agent) to http://proxy:80/:', diagGlobErr);
      responsePayload.diagnostic_simple_fetch_to_proxy_root_global_agent = {
        status: 'exception',
        error: { message: diagGlobErr.message, stack: diagGlobErr.stack },
      };
    }
  }
  // End Diagnostic without explicit agent

  // Determine the protocol of the incoming request to this API route
  const incomingRequestProtocol = request.nextUrl.protocol.replace(/:$/, '');

  const headersForDirectFetch: Record<string, string> = {
    // Forward essential headers. PostgREST might need 'Accept' for JSON.
    'Accept': 'application/json',
    // DO NOT set 'Host' here for internal calls to 'http://proxy:80'. 
    // 'fetch' will set it correctly to 'proxy:80' based on directFetchUrl.
    // The 'X-Forwarded-Host' (set below) is used by the internal Caddy for domain matching.
    'Content-Type': 'application/json', // Essential for POST with JSON body
  };

  // Set X-Forwarded-Proto based on the original incoming request to this API route
  // If the original request to Next.js was HTTPS, this should be 'https'.
  // The `request.nextUrl.protocol` gives the protocol of the request to this Next.js API route.
  // If Next.js itself is behind another proxy that terminates TLS, this might be http.
  // Relying on x-forwarded-proto from the incoming request is more robust if available.
  headersForDirectFetch['X-Forwarded-Proto'] = request.headers.get('x-forwarded-proto') || incomingRequestProtocol;

  // Set X-Forwarded-For
  // Use the incoming X-Forwarded-For, or fall back to the direct peer IP if not present.
  // This helps PostgREST see the original client IP.
  const incomingXFF = request.headers.get('x-forwarded-for');
  if (incomingXFF) {
    headersForDirectFetch['X-Forwarded-For'] = incomingXFF;
  } else {
    // request.ip is available in Next.js Edge/Node.js runtimes
    const ip = (request as NextRequest & { ip?: string }).ip;
    if (ip) { 
      headersForDirectFetch['X-Forwarded-For'] = ip;
    }
  }
  
  // Set X-Forwarded-Host to the original host requested by the client
  const originalHost = request.headers.get('x-forwarded-host') || request.headers.get('host');
  if (originalHost) {
    headersForDirectFetch['X-Forwarded-Host'] = originalHost;
  }


  if (allIncomingCookies['statbus']) {
    // PostgREST uses the Authorization header for JWT if present.
    // The server-side RestClientStore's fetchWithAuthRefresh also does this.
    headersForDirectFetch['Authorization'] = `Bearer ${allIncomingCookies['statbus']}`;
  }
  // Also forward the raw Cookie header as PostgREST can also read from request.cookies
  // Note: cookieStore is already awaited above.
  const rawCookieHeader = cookieStore.toString(); // Gets the 'name=value; name2=value2' string
  if (rawCookieHeader) {
    headersForDirectFetch['Cookie'] = rawCookieHeader;
  }
  
  // Remove any x-forwarded-port from the direct fetch, as it's less common to forward
  // and might confuse the internal proxy if it's not expecting it for Host matching.
  // The Host header now correctly reflects the target service name for the internal proxy.
  // The other X-Forwarded-* headers provide the original client context.
  // Note: The 'Host' header set above to 'dev.statbus.org' (or original host) is key for the internal Caddy.


  try {
    const directResponse = await fetch(directFetchUrl, {
      method: 'POST', // PostgREST RPCs are typically POST, even if they don't modify data
      headers: headersForDirectFetch,
      body: JSON.stringify({}), // Send an empty JSON object for RPC POST
      // @ts-ignore Property 'dispatcher' does exist on 'RequestInit'.
      dispatcher: undiciAgent 
    });

    const responseHeaders: Record<string, string> = {};
    directResponse.headers.forEach((value, key) => {
      responseHeaders[key] = value;
    });

    let responseData: AuthTestDbResponse | null = null;
    let responseParseError: string | null = null;
    let rawBodyForError: string | null = null;

    if (directResponse.ok && directResponse.headers.get('content-type')?.includes('application/json')) {
        try {
            // PostgREST RPCs that return a single row object directly (not in an array)
            responseData = await directResponse.json() as AuthTestDbResponse;
            if (typeof responseData !== 'object' || responseData === null) {
                // If it's not an object or is null, but parsed, it's unexpected.
                // This case might indicate an empty array `[]` was returned and parsed, then `responseData` became `null` if not handled.
                // However, typical single RPCs return an object or fail to parse if empty.
                console.warn('Direct fetch JSON parsed but was not the expected object:', responseData);
                // To be safe, if it's not a populated object, consider it a parsing issue for this context.
                if (!responseData || Object.keys(responseData).length === 0) {
                  responseParseError = `Parsed JSON was not a populated object. Parsed: ${JSON.stringify(responseData)}`;
                  responseData = null; // Ensure it's null if not a valid object structure
                }
            }
        } catch (e: any) {
            console.error('Error parsing JSON from direct fetch:', e);
            responseParseError = e.message;
            // Attempt to get raw body for better error reporting if JSON parsing fails
            try {
                // Clone the response before .text() if .json() might have consumed it,
                // though typically .json() failing means .text() can still be read.
                // For simplicity, assuming .text() can be called after .json() fails.
                rawBodyForError = await directResponse.text();
                console.error('Raw response text from direct fetch on JSON parse error:', rawBodyForError);
            } catch (textErr: any) {
                console.error('Could not get raw text from direct fetch response after JSON parse error:', textErr);
            }
        }
    } else if (!directResponse.ok) {
        const errorBody = await directResponse.text();
        console.error(`Direct fetch failed with status: ${directResponse.status} ${directResponse.statusText}. Body: ${errorBody}`);
        responseParseError = `Direct fetch failed: ${directResponse.status} ${directResponse.statusText}. Body: ${errorBody.substring(0, 500)}`;
    } else {
        // OK response but not application/json
        const nonJsonBody = await directResponse.text();
        console.warn(`Direct fetch returned OK but non-JSON content-type: ${directResponse.headers.get('content-type')}. Body: ${nonJsonBody.substring(0,500)}`);
        responseParseError = `OK response but non-JSON content-type. Body: ${nonJsonBody.substring(0,500)}`;
    }

    // Populate the response payload
    const success = directResponse.ok && responseData && !responseParseError;
    responsePayload.direct_fetch_call_to_rpc_auth_test = {
      status: success ? 'success' : 'error',
      request_headers_sent: headersForDirectFetch,
      response_status_code: directResponse.status,
      response_headers: responseHeaders,
      data: responseData, // Will be null if parsing failed or data was not as expected
      error: responseParseError,
      raw_body_on_error: rawBodyForError, // Include raw body if JSON parsing failed
    };
  } catch (e: any) {
    console.error('Exception during direct fetch call:', e);
    responsePayload.direct_fetch_call_to_rpc_auth_test = {
      status: 'exception',
      request_headers_sent: headersForDirectFetch,
      error: { message: e.message, stack: e.stack },
    };
  }

  return NextResponse.json(responsePayload);
}
