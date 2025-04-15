import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { authStore } from '@/context/AuthStore';
import { getServerRestClient } from '@/context/RestClientStore';

export async function middleware(request: NextRequest) {
  // Skip auth check for login page and public assets
  if (
    request.nextUrl.pathname === "/login" ||
    request.nextUrl.pathname.startsWith("/_next/") ||
    request.nextUrl.pathname.startsWith("/favicon.ico") ||
    request.nextUrl.pathname.startsWith("/rest/")
  ) {
    return NextResponse.next();
  }

  // Get authentication status directly from AuthStore
  const authStatus = await authStore.getAuthStatus();
  
  // If not authenticated, redirect to login
  if (!authStatus.isAuthenticated) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
  }
  
  // If we're on the login page and already authenticated, redirect to home
  if (request.nextUrl.pathname === "/login") {
    return NextResponse.redirect(`${request.nextUrl.origin}/`);
  }
  
  // User is authenticated, continue with app setup checks
  const client = await getServerRestClient();
      
      if (request.nextUrl.pathname === "/") {
        // Check if settings exist
        const { data: settings, error: settingsError } = await client
          .from("settings")
          .select("id")
          .limit(1);
          
        if (!settings?.length) {
          return NextResponse.redirect(
            `${request.nextUrl.origin}/getting-started/activity-standard`
          );
        }

        // Check if regions exist
        const { data: regions, error: regionsError } = await client
          .from("region")
          .select("id")
          .limit(1);
          
        if (!regions?.length) {
          return NextResponse.redirect(
            `${request.nextUrl.origin}/getting-started/upload-regions`
          );
        }

        // Check if units exist
        const { data: legalUnits, error: legalUnitsError } = await client
          .from("legal_unit")
          .select("id")
          .limit(1);
          
        const { data: establishments, error: establishmentsError } = await client
          .from("establishment")
          .select("id")
          .limit(1);
        if (!legalUnits?.length && !establishments?.length) {
          return NextResponse.redirect(`${request.nextUrl.origin}/import`);
        }
      }
      
      // All checks passed, continue to the requested page
      return NextResponse.next();
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
