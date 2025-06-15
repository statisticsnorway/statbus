"use server";

import { cookies } from "next/headers";
import { NextResponse, type NextRequest } from 'next/server';
import { Agent } from 'undici';
import { getDeploymentSlotCode } from './jwt';

/**
 * Handles token refresh in middleware
 */
export async function refreshAuthToken(request: NextRequest, origin: string): Promise<Response | null> {
  const refreshToken = request.cookies.get('statbus-refresh');
  
  if (!refreshToken) {
    return null;
  }
  
  try {
    // Create an explicit Undici agent, similar to /api/auth_test
    const undiciAgent = new Agent({
      connect: { timeout: 5000 }, // 5-second connect timeout
    });

    // Call the PostgREST refresh endpoint directly
    const response = await fetch(`${process.env.SERVER_REST_URL}/rpc/refresh`, {
      method: 'POST',
      // @ts-ignore Property 'dispatcher' does exist on 'RequestInit'.
      dispatcher: undiciAgent,
      headers: {
        // Align with AuthStore and Python test: send refresh token as a cookie
        'Cookie': `statbus-refresh=${refreshToken.value}`,
        'Content-Type': 'application/json' // Good practice for POST RPC
      },
      body: JSON.stringify({}) // Good practice for POST RPC, even if params are in cookie/header
    });
    
    if (response.ok) {
      const responseBodyForLogging = await response.clone().text(); // Clone to read body
      if (process.env.DEBUG === 'true') {
        const allHeaders: Record<string, string> = {};
        response.headers.forEach((value, key) => { allHeaders[key] = value; });
        console.log(`[refreshAuthToken] /rpc/refresh call was OK. Status: ${response.status}. Raw Headers: ${JSON.stringify(allHeaders)}. Raw Body: ${responseBodyForLogging}`);
      }
      // Get the Set-Cookie headers from the response
      const setCookieHeaders = response.headers.getSetCookie(); // Renamed for clarity
      
      if (process.env.DEBUG === 'true') {
        if (setCookieHeaders && setCookieHeaders.length > 0) {
          console.log(`[refreshAuthToken] Received Set-Cookie headers from /rpc/refresh:`, JSON.stringify(setCookieHeaders));
        } else {
          // This is the problematic case based on your logs
          console.log(`[refreshAuthToken] NO Set-Cookie headers received from /rpc/refresh. This is a critical issue with the rpc/refresh endpoint.`);
        }
      }
      
      // Create a new response that redirects to the original URL
      const redirectResponse = NextResponse.redirect(request.url);
      
      // Copy all cookies from the refresh response to the redirect response
      if (setCookieHeaders && setCookieHeaders.length > 0) {
        setCookieHeaders.forEach(cookie => {
          redirectResponse.headers.append('Set-Cookie', cookie);
        });
        if (process.env.DEBUG === 'true') {
          console.log(`[refreshAuthToken] Appended Set-Cookie headers to redirectResponse for ${request.url}`);
        }
      } else {
        if (process.env.DEBUG === 'true') {
          // This will also be logged if the above critical issue occurs
          console.log(`[refreshAuthToken] No Set-Cookie headers to append to redirectResponse for ${request.url}. Browser cookies will not be updated by this refresh attempt.`);
        }
      }
      
      return redirectResponse;
    } else {
      // Log non-OK responses from /rpc/refresh during server-side attempt
      const errorBody = await response.text();
      console.error(`[refreshAuthToken] /rpc/refresh call failed during server-side attempt. Status: ${response.status}. Body: ${errorBody}`);
    }
  } catch (error) {
    console.error('[refreshAuthToken] Error during token refresh attempt:', error);
  }
  
  return null;
}
