import {createServerClient, type CookieOptions} from "@supabase/ssr";
import {NextRequest, NextResponse} from "next/server";
import {cookies} from "next/headers";
import type {Database} from "@/lib/database.types";

export const createClient = () => {
  const cookie = cookies()

  return createServerClient<Database>(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookie.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          cookie.set({name, value, ...options})
        },
        remove(name: string, options: CookieOptions) {
          cookie.set({name, value: '', ...options})
        },
      },
    }
  )
}

// TODO: find a better way to do this. This approach is inspired by supabase docs:
// https://supabase.com/docs/guides/auth/server-side/creating-a-client?environment=middleware
// There should be a way to do this without having to create a new client for every request and also without having to
// have two different clients for server components / routes and middlewares.
export const createMiddlewareClient = (request: NextRequest) => {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  })

  const client = createServerClient(
    process.env.SUPABASE_URL!,
    process.env.SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return request.cookies.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value,
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
        },
        remove(name: string, options: CookieOptions) {
          request.cookies.set({
            name,
            value: '',
            ...options,
          })
          response = NextResponse.next({
            request: {
              headers: request.headers,
            },
          })
        },
      },
    }
  )

  return {client, response}
}
