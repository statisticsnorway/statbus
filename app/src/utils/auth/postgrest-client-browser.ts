"use client";

import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';

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
 */
export async function createPostgRESTBrowserClient(): Promise<SupabaseClient<Database>> {
  // Create a Supabase client configured to use our PostgREST endpoint
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
          return fetchWithAuth(url.toString(), options);
        },
      },
    }
  );

  return client;
}
