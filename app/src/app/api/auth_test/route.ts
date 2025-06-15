import { NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { getServerRestClient } from '@/context/RestClientStore'; // Assuming this path
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
  // Determine the protocol of the incoming request to this API route
  const incomingRequestProtocol = request.nextUrl.protocol.replace(/:$/, '');

  const headersForDirectFetch: Record<string, string> = {
    // Forward essential headers. PostgREST might need 'Accept' for JSON.
    'Accept': 'application/json',
    // Set the Host header to what the internal proxy expects for routing to PostgREST.
    // This is typically the external hostname.
    'Host': request.headers.get('x-forwarded-host') || request.headers.get('host') || 'dev.statbus.org',
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
    });

    const responseHeaders: Record<string, string> = {};
    directResponse.headers.forEach((value, key) => {
      responseHeaders[key] = value;
    });

    let responseData: AuthTestDbResponse | null = null;
    let responseParseError = null;
    if (directResponse.ok && directResponse.headers.get('content-type')?.includes('application/json')) {
        try {
            // PostgREST RPCs that return a single row often wrap it in an array
            const jsonDataArray = await directResponse.json();
            responseData = jsonDataArray[0] as AuthTestDbResponse; 
        } catch (e: any) {
            console.error('Error parsing JSON from direct fetch:', e);
            responseParseError = e.message;
        }
    } else if (!directResponse.ok) {
        console.error(`Direct fetch failed with status: ${directResponse.status} ${directResponse.statusText}`);
        responseParseError = `Direct fetch failed: ${directResponse.status} ${directResponse.statusText}. Body: ${await directResponse.text()}`;
    }


    responsePayload.direct_fetch_call_to_rpc_auth_test = {
      status: directResponse.ok && responseData ? 'success' : 'error',
      request_headers_sent: headersForDirectFetch, // Log what headers we sent
      response_status_code: directResponse.status,
      response_headers: responseHeaders,
      data: responseData,
      error: responseParseError,
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
