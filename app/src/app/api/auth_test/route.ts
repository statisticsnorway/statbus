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
    // Dynamically set X-Forwarded-Proto based on the incoming request to this API route
    'X-Forwarded-Proto': incomingRequestProtocol,
    // 'Content-Type': 'application/json', // Not strictly needed for GET RPC
  };
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
  // Forward X-Forwarded-* headers if they exist on the incoming request,
  // as Caddy might use them to determine `is_https` for PostgREST.
  // These are typically set by the outermost proxy (e.g., your load balancer or Cloudflare).
  // The Next.js request object might not see these if they are stripped by an intermediate proxy
  // before reaching the Next.js app container.
  for (const key of ['x-forwarded-for', 'x-forwarded-host', 'x-forwarded-proto', 'x-forwarded-port']) {
    const value = request.headers.get(key);
    if (value) {
      headersForDirectFetch[key] = value;
    }
  }


  try {
    const directResponse = await fetch(directFetchUrl, {
      method: 'POST', // PostgREST RPCs are typically POST, even if they don't modify data
      headers: headersForDirectFetch,
      // body: JSON.stringify({}), // Empty body for parameterless function
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
