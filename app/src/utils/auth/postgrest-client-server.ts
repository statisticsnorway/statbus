import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';
import { cookies } from 'next/headers';
import { getDeploymentSlotCode } from './jwt';

/**
 * Creates a PostgREST client for server-side rendering (SSR) contexts
 * 
 * This uses the Supabase client library for type safety and consistent API,
 * but configures it to work with our direct PostgREST setup and authentication system.
 * 
 * IMPORTANT: We are NOT using Supabase as a service, only their client libraries.
 * 
 * The Supabase client provides:
 * - TypeScript types that match our database schema
 * - A consistent API for database operations
 * - Query building utilities with proper escaping
 * - Standardized error handling
 * 
 * But we override:
 * - The endpoint URL to point to our PostgREST server
 * - The authentication to use our JWT tokens
 * - The fetch behavior to include our auth headers
 */
async function checkAuthStatus(): Promise<boolean> {
  try {
    const serverApiUrl = process.env.SERVER_API_URL;
    if (!serverApiUrl) {
      console.error('SERVER_API_URL environment variable is not set');
      return false;
    }

    const response = await fetch(`${serverApiUrl}/postgrest/rpc/auth_status`, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      },
      credentials: 'include'
    });
    
    if (response.ok) {
      const data = await response.json();
      return data.authenticated === true;
    }
    return false;
  } catch (error) {
    console.error('Error checking auth status:', error);
    return false;
  }
}

export async function createPostgRESTSSRClient(): Promise<SupabaseClient<Database>> {
  console.log('Creating PostgREST SSR client');
  
  // Check if user is authenticated
  const isAuthenticated = await checkAuthStatus();
  if (!isAuthenticated) {
    console.log('User is not authenticated, creating client without auth token');
  }
  
  const cookieStore = await cookies();
  const token = cookieStore.get('statbus');
  
  // Get the server API URL from environment
  const serverApiUrl = process.env.SERVER_API_URL;
  console.log('Auth token available:', !!token, 'Server API URL:', serverApiUrl);
  
  if (!serverApiUrl) {
    console.error('SERVER_API_URL environment variable is not set');
    throw new Error('SERVER_API_URL environment variable is not set');
  }
  
  // Test if the server API URL is reachable
  try {
    console.log('Testing connectivity to PostgREST endpoint...');
    const testResponse = await fetch(serverApiUrl, {
      method: 'GET',
      headers: {
        'Accept': 'application/json'
      }
    });
    console.log('PostgREST endpoint test response:', {
      status: testResponse.status,
      statusText: testResponse.statusText,
      ok: testResponse.ok
    });
  } catch (error) {
    console.warn('Could not reach PostgREST endpoint during initialization:', error);
    // Don't throw here, as the client might still work in some cases
  }
  
  // Create a Supabase client configured to use our PostgREST endpoint
  const client = createClient<Database>(
    serverApiUrl,
    // We need to provide an anon key, but it's not used with our auth system
    // PostgREST will use the JWT token from cookies instead
    'dummy-key-for-postgrest',
    {
      auth: {
        autoRefreshToken: false, // We handle token refresh ourselves
        persistSession: true,
        detectSessionInUrl: false,
      },
      global: {
        headers: {
          // Add the auth token to all requests if available
          ...(token ? { 'Authorization': `Bearer ${token.value}` } : {})
        },
      },
    }
  );

  // Modify the REST URL to use /postgrest instead of rest/v1
  (client as any).rest.url = (client as any).rest.url.replace(/rest\/v1$/, 'postgrest');
  
  console.log('PostgREST client created successfully with URL:', (client as any).rest.url);
  return client;
}
