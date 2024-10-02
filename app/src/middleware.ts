import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { createClient } from '@/utils/supabase/server';

export async function middleware(request: NextRequest) {
  const {client} = createClient(request);
  const {
    data: { session },
  } = await client.auth.getSession();

  if (!session) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
  }

  if (request.nextUrl.pathname === "/") {
    const { data: settings } = await client
      .from("settings")
      .select("id")
      .limit(1);
    if (!settings?.length) {
      return NextResponse.redirect(
        `${request.nextUrl.origin}/getting-started/activity-standard`
      );
    }

    const { data: regions } = await client.from("region").select("id").limit(1);
    if (!regions?.length) {
      return NextResponse.redirect(
        `${request.nextUrl.origin}/getting-started/upload-regions`
      );
    }

    const { data: legalUnits } = await client
      .from("legal_unit")
      .select("id")
      .limit(1);
    if (!legalUnits?.length) {
      return NextResponse.redirect(
        `${request.nextUrl.origin}/getting-started/upload-legal-units`
      );
    }
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    /*
     * Match all request paths except for the ones starting with:
     * - _next/static (static files)
     * - _next/image (image optimization files)
     * - favicon.ico (favicon file)
     * - login (authentication page)
     * - maintenance (maintenance page)
     * - api/logger (allow logging without authentication)
     * - api/auth/session (allow session checking without authentication)
     */
    "/((?!_next/static|_next/image|favicon.ico|login|maintenance|api/logger|api/auth/session|api/test).*)",
  ],
};
