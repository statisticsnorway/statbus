// src/utils/supabase/server.ts
"use server";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";
import { NextResponse, type NextRequest } from 'next/server'

export const createSupabaseSSGClient = async () => {
  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          // If the client *tries* to access the cookies, then it breaks SSG
          // so just return an empty array when it checks the cookies.
          return [];
        },
        setAll(cookiesToSet) {
          //console.error("Attempt to set cookies directly. This should be handled by middleware. Stack trace below:");
          //console.error(new Error().stack);
          // Disable setting of cookies, it should only be done by the middleware!
          throw new Error("Prohibited by Next.js: Direct setting of cookies is not allowed. Use middleware instead.");
        },
      },
      auth: {
        detectSessionInUrl: false,
        persistSession: false,
        autoRefreshToken: false,
      },
    }
  );
  return client;
}

interface SupabaseSSRClientOptions {
  allowCookieModification?: boolean;
}

export const createSupabaseSSRClient = async ({ allowCookieModification = false }: SupabaseSSRClientOptions = {}) => {
  let cookieStore = cookies();

  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore?.getAll();
        },
        setAll(cookiesToSet) {
          // The login/logout functions are exempt from cokie modification.
          if (allowCookieModification) {
              cookiesToSet.forEach(({ name, value, options }) => {
                cookieStore.set(name, value);
              });
          } else {
            throw new Error("Prohibited by Next.js: Direct setting of cookies is not allowed. Use middleware instead.");
          }
        },
      },
      auth: { // Workaround bug https://github.com/supabase/supabase-js/issues/1250
        detectSessionInUrl: false,
        persistSession: false,
        autoRefreshToken: false,
        //debug: true,
      },
    }
  );
  return client;
};


export const createMiddlewareClientAsync = async (request: NextRequest) => {
  let response = NextResponse.next({
    request,
  });

  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            request.cookies.set(name, value);
            response.cookies.set(name, value, options);
          });
        },
      },
      auth: { // Perform all cookie modifications in the middleware.
        detectSessionInUrl: true,
        persistSession: true,
        autoRefreshToken: true,
        //debug: true,
      },
    }
  );
  return { client, response };
};
