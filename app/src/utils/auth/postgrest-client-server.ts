import { SupabaseClient, createClient } from '@supabase/supabase-js';
import { Database } from '@/lib/database.types';
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

// Global singleton for the server-side client
// This ensures we have a single source of truth
let cachedClient: SupabaseClient<Database> | null = null;
let clientTimestamp: number = 0;
const CLIENT_TTL = 5 * 60 * 1000; // 5 minutes

// Export the getServerClient function from ClientStore
export { getServerClient } from '@/context/ClientStore';

// The createPostgRESTSSRClient function is now primarily used by ClientStore
// Other code should use getServerClient() from ClientStore instead

export async function createPostgRESTSSRClient(): Promise<SupabaseClient<Database>> {
  console.log('Creating new PostgREST SSR client');
  
  // Get cookies first - using dynamic import to avoid issues with next/headers
  let token = null;
  try {
    const { cookies } = await import('next/headers');
    const cookieStore = await cookies();
    token = cookieStore.get('statbus');
    
    // Log the available cookies for debugging
    console.log('Available cookies:', {
      hasStatbusToken: !!token,
      tokenValue: token ? token.value.substring(0, 10) + '...' : 'none',
      cookieCount: [...cookieStore.getAll()].length
    });
  } catch (error) {
    console.error('Error accessing cookies:', error);
    // Continue without token
  }
  
  // Check for token directly instead of using isAuthenticated()
  // to avoid circular dependencies
  let authenticated = !!token;
  if (process.env.NODE_ENV === 'development') {
    if (!authenticated) {
      console.log('Not authenticated, creating client without auth token');
    } else {
      console.log('Authenticated, creating client with auth token');
    }
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
  
  // Cache the client for backward compatibility
  // Note: This is redundant with ClientStore but ensures this function works standalone
  cachedClient = client;
  clientTimestamp = Date.now();
  
  return client;
}
