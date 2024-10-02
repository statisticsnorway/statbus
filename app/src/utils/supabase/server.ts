// src/utils/supabase/server.ts
"use server";

import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";
import { Database } from "@/lib/database.types";
import { NextResponse, type NextRequest } from 'next/server'

export const createClient = (request: NextRequest | null) => {
  const isNextRequest = (req: any): req is NextRequest => req !== null;
  let response = isNextRequest(request) ? NextResponse.next({
    request,
  }) : undefined;

  const client = createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          if (isNextRequest(request)) {
            return request.cookies.getAll();
          } else {
            return cookies().getAll();
          }
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => {
            if (isNextRequest(request)) {
              request.cookies.set(name, value);
              response!.cookies.set(name, value, options);
            } else {
              cookies().set(name, value, options);
            }
          });
        },
      },
    }
  );
  return { client, response };
};
