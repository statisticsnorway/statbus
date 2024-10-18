// src/utils/supabase/server.ts
"use server";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";
import { cookieOptions } from "./cookieOptions";
import { NextResponse, type NextRequest } from 'next/server'

export const createSupabaseSSGClient = async () => {
  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.SERVER_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookieOptions,
      cookies: {
        getAll() {
          // If the client *tries* to access the cookies, then it breaks SSG
          // so just return an empty array when the supabase code checks the cookies.
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


export const createSupabaseSSRClient = async () => {
  let cookieStore = cookies();

  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.SERVER_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookieOptions,
      cookies: {
        getAll() {
          return cookieStore?.getAll();
        },
        setAll(cookiesToSet) {
          throw new Error("Prohibited by Next.js: Direct setting of cookies is not allowed. Use middleware instead.");
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
  // Only them middleware can use NextResponse.next not API functions (in App Router)
  let response = NextResponse.next({
    request,
  });

  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.SERVER_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookieOptions,
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            // The cookies in the request are used later by createSupabaseSSRClient
            // and then detects and uses the JWT token in the cookie.
            request.cookies.set(name, value);
            // The cookies in the response are sent back to the browser,
            // so that the possibly refreshed JWT is saved as a cookie.
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


export const createApiClientAsync = async () => {
  // Server Actions / API functions under App Routing must not directly modify
  // the request, but use API's, and the underlying Next.js framework
  // will return the set cookies to the browser.
  // This is a design choice for Next.js 13+
  let cookieStore = cookies();

  // The createServerClient does return a Promise, even if the typescript type claims otherwise, so the await is required.
  const client = await createServerClient<Database>(
    process.env.SERVER_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookieOptions,
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        },
      },
      auth: { // Perform all cookie modifications for API endpoint.
        detectSessionInUrl: true,
        persistSession: true,
        autoRefreshToken: true,
        //debug: true,
      },
    }
  );
  return client;
};
