"use client";

import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';
import { isAuthenticated } from '@/utils/auth/auth-utils';

// Global singleton instance of the client
// This prevents the "Multiple GoTrueClient instances detected" warning
let globalClient: SupabaseClient<Database> | null = null;

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
  // Return the global instance if it exists
  if (globalClient) {
    console.log('Using global PostgREST browser client');
    return globalClient;
  }
  
  // Check authentication status
  const authenticated = await isAuthenticated();
  console.log('Authentication status in browser client:', authenticated);

  // Create a new Supabase client configured to use our PostgREST endpoint
  globalClient = createClient<Database>(
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

  // The client is already stored in the global variable
  return globalClient;
}
