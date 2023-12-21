import type {NextRequest} from 'next/server'
import {NextResponse} from 'next/server'
import {createMiddlewareClient} from "@/app/auth/_lib/supabase.server.client";

export async function middleware(request: NextRequest) {
  const {client, response} = createMiddlewareClient(request)
  const {data: {session}} = await client.auth.getSession()
  return !session ? NextResponse.redirect(`${request.nextUrl.origin}/auth/login`) : response
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!_next/static|_next/image|favicon.ico|auth/).*)',
  ],
}
