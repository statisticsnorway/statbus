"use server";

import { cookies } from "next/headers";
import { NextResponse, type NextRequest } from 'next/server';
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
    // Call the PostgREST refresh endpoint directly
    const response = await fetch(`${process.env.SERVER_REST_URL}/rpc/refresh`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${refreshToken.value}`,
        'Content-Type': 'application/json'
      }
    });
    
    if (response.ok) {
      // Get the Set-Cookie headers from the response
      const cookies = response.headers.getSetCookie();
      
      // Create a new response that redirects to the original URL
      const redirectResponse = NextResponse.redirect(request.url);
      
      // Copy all cookies from the refresh response
      cookies.forEach(cookie => {
        redirectResponse.headers.append('Set-Cookie', cookie);
      });
      
      return redirectResponse;
    }
  } catch (error) {
    console.error('Token refresh failed:', error);
  }
  
  return null;
}
