import { NextRequest, NextResponse } from "next/server";
import { authStore } from '@/context/AuthStore';
import { getServerRestClient } from '@/context/RestClientStore';


export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Skip auth check for login page, public assets and API endpoints
  if (
    pathname === "/login" ||
    pathname.startsWith("/_next/") ||
    pathname.startsWith("/favicon.ico") ||
    pathname.startsWith("/rest/") || // PostgREST endpoint is proxied/exposed here
    pathname.startsWith("/pev2.html") // Tool for analyzing PostgreSQL execution plans (EXPLAIN ANALYZE)
  ) {
    return NextResponse.next();
  }

  // --- Authentication Check and Refresh via AuthStore ---
  let response = NextResponse.next(); // Prepare a default response
  
  // Call AuthStore to handle auth check and potential refresh
  // Pass the request cookies for reading refresh token, and response cookies for setting new tokens
  const { status: authStatus, modifiedRequestHeaders } = await authStore.handleServerAuth(
    request.cookies, 
    response.cookies // Pass the mutable cookies object from the response
  );

  // --- Handle Auth Result ---
  if (!authStatus.isAuthenticated) {
    // If still not authenticated after check/refresh attempt, redirect to login
    console.log("Middleware: AuthStore reported unauthenticated, redirecting to login.");
    const loginUrl = new URL('/login', request.url);
    // Ensure response object used for redirect has cleared cookies (AuthStore might have done this)
    response = NextResponse.redirect(loginUrl); 
    response.cookies.delete('statbus'); // Explicitly clear just in case
    response.cookies.delete('statbus-refresh');
    return response;
  }

  // --- Prepare Response for Authenticated User ---
  let finalRequest = request; // Use original request by default

  // If AuthStore signaled that headers were modified (due to refresh)
  if (modifiedRequestHeaders?.has('X-Statbus-Refreshed-Token')) {
      console.log("Middleware: AuthStore signaled refresh, modifying request headers for subsequent handlers.");
      const newAccessToken = modifiedRequestHeaders.get('X-Statbus-Refreshed-Token')!;
      
      // Create new headers based on the original request
      const newHeaders = new Headers(request.headers);
      
      // Reconstruct the cookie header string *using the cookies set on the response object*
      const newCookieHeader = Array.from(response.cookies.getAll()).map(c => `${c.name}=${c.value}`).join('; ');
      newHeaders.set('cookie', newCookieHeader); 
      
      // Create the request object that subsequent handlers will see
      finalRequest = new NextRequest(request.nextUrl, { headers: newHeaders });
      
      // Ensure the response allows the request to proceed with these new headers
      response = NextResponse.next({
          request: {
              headers: newHeaders,
          },
      });
      // Re-apply the cookies set by AuthStore to this *new* response object
      const refreshedAccessToken = response.cookies.get('statbus');
      const refreshedRefreshToken = response.cookies.get('statbus-refresh');
      if(refreshedAccessToken) response.cookies.set(refreshedAccessToken);
      if(refreshedRefreshToken) response.cookies.set(refreshedRefreshToken);
  }
  
  // --- App Setup Checks (only if authenticated) ---
  // Use the finalRequest object which has potentially updated headers
  const client = await getServerRestClient(); // Reads headers from finalRequest context

  if (finalRequest.nextUrl.pathname === "/") {
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
    } // End of app setup checks

    // All checks passed, return the response (which might have new cookies set and request headers modified)
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
