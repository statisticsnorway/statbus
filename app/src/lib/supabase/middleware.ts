"use server";
import { type CookieOptions, createServerClient } from "@supabase/ssr";
import { NextRequest, NextResponse } from "next/server";

// This approach is inspired by supabase docs:
// https://supabase.com/docs/guides/auth/server-side/creating-a-client?environment=middleware
export const createClient = (request: NextRequest) => {
  if (!isAuthenticated(request)) {
    if (request.nextUrl.pathname.startsWith("/api/")) {
      return NextResponse.json(
        { error: "Not authenticated" },
        { status: 401 }
      );
    } else {
      return NextResponse.redirect(new URL("/login", request.url));
    }
  }

  const response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const client = createServerClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value;
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value,
            ...options,
          });
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          });
          response.cookies.set({
            name,
            value,
            ...options,
          });
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value: "",
            ...options,
          });
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          });
          response.cookies.set({
            name,
            value: "",
            ...options,
          });
        },
      },
    }
  );

  return { client, response };
};
