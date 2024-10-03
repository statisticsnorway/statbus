// src/utils/supabase/server.ts
"use server";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";
import { NextResponse, type NextRequest } from 'next/server'

export const createClient = () => {
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
          cookiesToSet.forEach(({ name, value, options }) => {
              cookieStore?.set(name, value, options);
          });
        },
      },
    }
  );
  return client;
};


export const createMiddlewareClient = (request: NextRequest) => {
  let response =NextResponse.next({
    request,
  });

  const client = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies?.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
              request.cookies?.set(name, value);
              response?.cookies.set(name, value, options);
          });
        },
      },
    }
  );
  return { client, response };
};
