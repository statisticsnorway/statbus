// src/utils/supabase/server.ts
"use server";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";
import { NextResponse, type NextRequest } from 'next/server'

export const createSupabaseServerClient = () => {
  let cookieStore = cookies();

  const client = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore?.getAll();
        },
        setAll(cookiesToSet) {
          //console.error("Attempt to set cookies directly. This should be handled by middleware. Stack trace below:");
          //console.error(new Error().stack);
          // Disable setting of cookies, it should only be done by the middleware!
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
  let response = NextResponse.next({
    request,
  });

  const client = createServerClient<Database>(
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
      //auth: { debug: true,},
    }
  );
  return { client, response };
};
