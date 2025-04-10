"use server";

import { cookies } from "next/headers";
import { NextResponse, type NextRequest } from 'next/server';
import { getDeploymentSlotCode } from './jwt';

/**
 * Creates a direct API client for server-side rendering (SSR) contexts
 * This uses direct fetch calls to PostgREST with the JWT from cookies
 */
export const createAuthSSRClient = async () => {
  const cookieStore = await cookies();
  const deploymentSlot = getDeploymentSlotCode();
  const token = cookieStore.get(`statbus-${deploymentSlot}`);

  return {
    /**
     * Call a PostgreSQL RPC function via PostgREST
     */
    rpc: async (functionName: string, params = {}) => {
      try {
        const response = await fetch(`${process.env.SERVER_API_URL}/rpc/${functionName}`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(token ? { 'Authorization': `Bearer ${token.value}` } : {})
          },
          body: JSON.stringify(params)
        });

        const data = await response.json();
        
        if (!response.ok) {
          return { data: null, error: data };
        }
        
        return { data, error: null };
      } catch (error) {
        return { data: null, error };
      }
    },
    
    /**
     * Query a PostgreSQL table via PostgREST
     */
    from: (tableName: string) => {
      const baseUrl = `${process.env.SERVER_API_URL}/${tableName}`;
      
      return {
        select: async (columns: string = '*', options = {}) => {
          try {
            const url = new URL(baseUrl);
            url.searchParams.append('select', columns);
            
            // Add any additional query parameters
            Object.entries(options).forEach(([key, value]) => {
              if (value !== undefined) {
                url.searchParams.append(key, String(value));
              }
            });
            
            const response = await fetch(url.toString(), {
              headers: {
                ...(token ? { 'Authorization': `Bearer ${token.value}` } : {})
              }
            });
            
            const data = await response.json();
            
            if (!response.ok) {
              return { data: null, error: data };
            }
            
            return { data, error: null };
          } catch (error) {
            return { data: null, error };
          }
        },
        
        // Add other query methods as needed (insert, update, delete, etc.)
        limit: (limit: number) => {
          const limitObj = {
            select: async (columns: string = '*') => {
              try {
                const url = new URL(baseUrl);
                url.searchParams.append('select', columns);
                url.searchParams.append('limit', String(limit));
                
                const response = await fetch(url.toString(), {
                  headers: {
                    ...(token ? { 'Authorization': `Bearer ${token.value}` } : {})
                  }
                });
                
                const data = await response.json();
                
                if (!response.ok) {
                  return { data: null, error: data };
                }
                
                return { data, error: null };
              } catch (error) {
                return { data: null, error };
              }
            }
          };
          return limitObj;
        }
      };
    }
  };
};

/**
 * Creates a direct API client for API route contexts
 * This is just an alias for createAuthSSRClient for consistency
 */
export const createAuthApiClient = createAuthSSRClient;

/**
 * Handles token refresh in middleware
 */
export async function refreshAuthToken(request: NextRequest, origin: string): Promise<Response | null> {
  const deploymentSlot = getDeploymentSlotCode();
  const refreshToken = request.cookies.get(`statbus-${deploymentSlot}-refresh`);
  
  if (!refreshToken) {
    return null;
  }
  
  try {
    // Call the PostgREST refresh endpoint directly
    const response = await fetch(`${process.env.SERVER_API_URL}/rpc/refresh`, {
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
