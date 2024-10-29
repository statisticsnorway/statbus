import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { createMiddlewareClientAsync } from '@/utils/supabase/server';

export async function middleware(request: NextRequest) {
  const { response, client } = await createMiddlewareClientAsync(request);
  if (request.nextUrl.pathname === "/login") {
    return response; // Return early for /login to avoid any redirects or session checks
  }

  const session =
    client !== undefined ?
      (await client?.auth.getSession())?.data?.session :
      null;

  if (!session) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`, { headers: response.headers });
  }

  if (request.nextUrl.pathname === "/") {
    const { data: settings } = await client
      .from("settings")
      .select("id")
      .limit(1);
    if (!settings?.length) {
      return NextResponse.redirect(
        `${request.nextUrl.origin}/getting-started/activity-standard`,
        { headers: response.headers }
      );
    }

    const { data: regions } = await client.from("region").select("id").limit(1);
    if (!regions?.length) {
      return NextResponse.redirect(
        `${request.nextUrl.origin}/getting-started/upload-regions`,
        { headers: response.headers }
      );
    }

    const { data: legalUnits } = await client
      .from("legal_unit")
      .select("id")
      .limit(1);
    const { data: establishments } = await client
      .from("establishment")
      .select("id")
      .limit(1);
    if (!legalUnits?.length && !establishments?.length) {
      return NextResponse.redirect(`${request.nextUrl.origin}/import`, {
        headers: response.headers,
      });
    }
  }

  // Return the response object modified by createMiddlewareClientAsync, such that
  // any cookies set/clear are propagated, since the createMiddlewareClientAsync may
  // use a refresh token against the server.
  return response;
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - maintenance (maintenance page)
     * - api (API's are responsible for handling their own sessions by calling any requried functions)
     */
    "/((?!_next/static|_next/image|favicon.ico|maintenance|api).*)",
  ],
};
