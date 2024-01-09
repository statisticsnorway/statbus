import type {NextRequest} from 'next/server'
import {NextResponse} from 'next/server'
import {createMiddlewareClient} from "@/lib/supabase.server.client";

export async function middleware(request: NextRequest) {
  const {client, response} = createMiddlewareClient(request)
  const {data: {session}} = await client.auth.getSession()

  if (!session) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`)
  }

  if (request.nextUrl.pathname === '/') {
    const { data: settings } = await client.from('settings').select('*')
    if (!settings?.length){
      return NextResponse.redirect(`${request.nextUrl.origin}/getting-started/activity-standard`)
    }

    const { data: regions } = await client.from('region').select('*')
    if (!regions?.length){
      return NextResponse.redirect(`${request.nextUrl.origin}/getting-started/upload-regions`)
    }
  }

  return response
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     */
    '/((?!_next/static|_next/image|favicon.ico|login).*)',
  ],
}
