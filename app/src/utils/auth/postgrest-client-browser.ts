"use client";

import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';
import { isAuthenticated } from '@/utils/auth/auth-utils';

// Export the getBrowserClient function from ClientStore
export { getBrowserClient } from '@/context/ClientStore';

// The createPostgRESTBrowserClient function is now primarily used by ClientStore
// Other code should use getBrowserClient() from ClientStore instead

/**
 * Creates a PostgREST client for browser contexts
 * 
 * This uses the Supabase client library for type safety and consistent API,
 * but configures it to work with our direct PostgREST setup and authentication system.
 * 
 * IMPORTANT: We are NOT using Supabase as a service, only their client libraries.
 * 
 * In browser contexts, we also use our custom fetch function that handles:
 * - Including credentials (cookies) with all requests
 * - Automatic token refresh on 401 errors
 * - Retrying failed requests with the new token
 * 
 * This implementation uses a singleton pattern to prevent multiple instances
 * of GoTrueClient being created in the same browser context.
 */
export async function createPostgRESTBrowserClient(): Promise<SupabaseClient<Database>> {
  console.log('Creating new PostgREST browser client');
  
  // Check authentication status
  const authenticated = await isAuthenticated();
  if (process.env.NODE_ENV === 'development') {
    console.log('Authentication status in browser client:', authenticated);
  }

  // Create a new Supabase client configured to use our PostgREST endpoint
  const client = createClient<Database>(
    process.env.NEXT_PUBLIC_BROWSER_API_URL!,
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
        // Use our custom fetch function that handles auth
        fetch: async (url, options) => {
          // Use the fetchWithAuth utility to handle token refresh
          const { fetchWithAuth } = await import('@/utils/auth/fetch-with-auth');
          
          // Fix the URL path: replace /rest/v1 with /postgrest
          // This ensures we're using the same URL structure in all environments
          const urlString = url.toString().replace('/rest/v1', '/postgrest');
          
          return fetchWithAuth(urlString, options);
        },
      },
    }
  );

  console.log('PostgREST browser client created successfully');
  return client;
}
