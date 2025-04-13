import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';
import { cookies } from 'next/headers';
import { getDeploymentSlotCode } from './jwt';

import { getAuthStatus } from '@/services/auth';
import { isAuthenticated } from '@/utils/auth/auth-utils';
// Remove direct import of serverFetch

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
// Cache the client to avoid creating multiple instances
let cachedClient: SupabaseClient<Database> | null = null;
let clientTimestamp: number = 0;
const CLIENT_TTL = 5 * 60 * 1000; // 5 minutes

// Use the isAuthenticated function directly from auth-utils
// No need for a separate checkAuthStatus function

export async function createPostgRESTSSRClient(): Promise<SupabaseClient<Database>> {
  // Check if we have a cached client that's still valid
  const now = Date.now();
  if (cachedClient && (now - clientTimestamp < CLIENT_TTL)) {
    console.log('Using cached PostgREST SSR client');
    return cachedClient;
  }

  console.log('Creating new PostgREST SSR client');
  
  // Get cookies first
  const cookieStore = await cookies();
  const token = cookieStore.get('statbus');
  
  // Log the available cookies for debugging
  console.log('Available cookies:', {
    hasStatbusToken: !!token,
    tokenValue: token ? token.value.substring(0, 10) + '...' : 'none',
    cookieCount: [...cookieStore.getAll()].length
  });
  
  let authenticated = false;
  try {
    // Use isAuthenticated directly
    authenticated = await isAuthenticated();
    if (process.env.NODE_ENV === 'development') {
      if (!authenticated) {
        console.log('Not authenticated, creating client without auth token');
      } else {
        console.log('Authenticated, creating client with auth token');
      }
    }
  } catch (error) {
    console.error('Authentication check failed:', error);
    console.log('Proceeding with unauthenticated client');
  }
  
  // Use the Next.js app URL in development to ensure we go through the proxy
  // In production, use SERVER_API_URL which should point to Caddy
  const serverApiUrl = process.env.NODE_ENV === 'development' 
    ? 'http://localhost:3000' // Use the Next.js app URL which proxies to PostgREST
    : process.env.SERVER_API_URL;
    
  console.log('Auth token available:', !!token, 'Server API URL:', serverApiUrl);
  
  if (!serverApiUrl) {
    console.error('SERVER_API_URL environment variable is not set');
    throw new Error('SERVER_API_URL environment variable is not set');
  }
  
  // Ensure the serverApiUrl ends with a trailing slash if needed
  const apiUrl = serverApiUrl.endsWith('/') ? serverApiUrl : `${serverApiUrl}/`;
  
  // Create a Supabase client configured to use our PostgREST endpoint
  const client = createClient<Database>(
    apiUrl,
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
          ...(token ? { 'Authorization': `Bearer ${token.value}` } : {}),
          'Accept': 'application/json',
          'Content-Type': 'application/json'
        },
        fetch: async (url, options) => {
          // Fix the URL path: replace /rest/v1 with /postgrest if needed
          // This ensures we're using the same URL structure in all environments
          const urlString = url.toString().replace('/rest/v1', '/postgrest');
          
          // Dynamically import and use our server-side fetch utility
          const { serverFetch } = await import('./server-fetch');
          return serverFetch(urlString, options);
        }
      },
    }
  );

  // Modify the REST URL to use /postgrest instead of rest/v1
  if ((client as any).rest && (client as any).rest.url) {
    const originalUrl = (client as any).rest.url;
    // Make sure we're only replacing at the end of the URL
    if (originalUrl.includes('rest/v1')) {
      (client as any).rest.url = originalUrl.replace(/rest\/v1$/, 'postgrest');
      console.log('Modified REST URL:', (client as any).rest.url);
    } else {
      console.warn('Could not modify REST URL, unexpected format:', originalUrl);
    }
  } else {
    console.warn('Client REST URL property not found');
  }
  
  console.log('PostgREST client created successfully with URL:', (client as any).rest.url);
  
  // Cache the client
  cachedClient = client;
  clientTimestamp = Date.now();
  
  return client;
}
