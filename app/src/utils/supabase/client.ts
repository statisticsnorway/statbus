// utils/supabase/client.ts
import { createBrowserClient } from '@supabase/ssr'

export async function createSupabaseBrowserClientAsync() {
  try {
    // Ensure the return is a promise (assuming createBrowserClient does not always return a promise)
    const client = await Promise.resolve(
      createBrowserClient(
        process.env.NEXT_PUBLIC_BROWSER_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        { cookieOptions }
      )
    );
    return client;
  } catch (error) {
    console.error('Failed to create Supabase client:', error);
    throw new Error('Could not initialize the Supabase client.');
  }
}
import { cookieOptions } from "./cookieOptions";
