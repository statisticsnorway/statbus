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

  const serverRestUrl = process.env.SERVER_REST_URL;
  const rpcUrl = serverRestUrl ? `${serverRestUrl}/rest/rpc/auth_test` : null;

  const responsePayload: Record<string, any> = {
    message: "Auth Test API Endpoint Results",
    notes: "This endpoint uses a direct fetch call to the auth_test RPC. The postgrest-js client is bypassed to ensure the Authorization header is not sent, allowing the SQL function to analyze the cookie directly.",
    environment: {
      SERVER_REST_URL: serverRestUrl,
      rpc_url_used: rpcUrl,
    },
    incoming_request_to_nextjs_api: {
      url: request.url,
      method: request.method,
      cookies: allIncomingCookies,
    },
    direct_fetch_call_to_rpc_auth_test: {},
  };

  if (!rpcUrl) {
    responsePayload.direct_fetch_call_to_rpc_auth_test = {
      status: 'error',
      error: 'SERVER_REST_URL is not defined. Cannot perform test.',
    };
    return NextResponse.json(responsePayload, { status: 500 });
  }

  // Construct headers for the direct fetch call.
  const headersForDirectFetch = new Headers();
  headersForDirectFetch.set('Content-Type', 'application/json');
  headersForDirectFetch.set('Accept', 'application/json');

  // Forward the original Cookie header. This is CRUCIAL.
  const rawCookieHeader = cookieStore.toString();
  if (rawCookieHeader) {
    headersForDirectFetch.set('Cookie', rawCookieHeader);
  }

  // Forward the X-Forwarded-* headers to provide context to the backend.
  if (request.headers.has('x-forwarded-host')) headersForDirectFetch.set('X-Forwarded-Host', request.headers.get('x-forwarded-host')!);
  if (request.headers.has('x-forwarded-proto')) headersForDirectFetch.set('X-Forwarded-Proto', request.headers.get('x-forwarded-proto')!);
  if (request.headers.has('x-forwarded-for')) headersForDirectFetch.set('X-Forwarded-For', request.headers.get('x-forwarded-for')!);

  // IMPORTANT: We DO NOT set the 'Authorization' header here.

  try {
    const directResponse = await fetch(rpcUrl, {
      method: 'POST',
      headers: headersForDirectFetch,
      body: JSON.stringify({}), // RPCs via POST need a body
    });

    const responseHeaders: Record<string, string> = {};
    directResponse.headers.forEach((value, key) => {
      responseHeaders[key] = value;
    });

    const responseData = await directResponse.json();

    if (!directResponse.ok) {
      responsePayload.direct_fetch_call_to_rpc_auth_test = {
        status: 'error',
        error: `RPC call failed with status: ${directResponse.status}`,
        response_data: responseData,
      };
    } else {
      responsePayload.direct_fetch_call_to_rpc_auth_test = {
        status: 'success',
        data: responseData as AuthTestDbResponse,
      };
    }
    
    // Add request/response details for debugging
    responsePayload.direct_fetch_call_to_rpc_auth_test.request_headers_sent = Object.fromEntries(headersForDirectFetch.entries());
    responsePayload.direct_fetch_call_to_rpc_auth_test.response_status_code = directResponse.status;
    responsePayload.direct_fetch_call_to_rpc_auth_test.response_headers = responseHeaders;

  } catch (e: any) {
    console.error('Exception during direct fetch call to auth_test RPC:', e);
    responsePayload.direct_fetch_call_to_rpc_auth_test = {
      status: 'exception',
      request_headers_sent: Object.fromEntries(headersForDirectFetch.entries()),
      error: { message: e.message, stack: e.stack },
    };
  }

  return NextResponse.json(responsePayload);
}
