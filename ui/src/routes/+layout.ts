// src/routes/+layout.ts
import { createSupabaseLoadClient } from '@supabase/auth-helpers-sveltekit'
import type { Database } from '../../database.types'

export const prerender = true

export const load = async ({ fetch, data, depends }) => {
  // Tell SvelteKit to re-run this load function if the authentication state changes
  depends('supabase:auth');

  // Use import.meta.env to access environment variables during build time
  const supabaseUrl = import.meta.env.VITE_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = import.meta.env.VITE_PUBLIC_SUPABASE_ANON_KEY;

  const supabase = createSupabaseLoadClient<Database>({
    supabaseUrl,
    supabaseKey: supabaseAnonKey,
    event: { fetch },
    // No need for serverSession in client-only auth
    serverSession: null,
  });

  const {
    data: { session },
  } = await supabase.auth.getSession();

  return { supabase, session };
};
