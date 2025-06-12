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
  // Create a response object that we will modify and eventually return.
  let response = NextResponse.next();

  const { status: authStatus, modifiedRequestHeaders } = await authStore.handleServerAuth(
    request.cookies,
    response.cookies // authStore modifies response.cookies directly
  );

  // --- Handle Auth Result ---
  if (!authStatus.isAuthenticated) {
    // If still not authenticated after check/refresh attempt, redirect to login
    console.log("Middleware: AuthStore reported unauthenticated, redirecting to login.");
    const loginUrl = new URL('/login', request.url);
    // Create a new response for redirect.
    const redirectResponse = NextResponse.redirect(loginUrl);
    
    // Determine if the connection is secure for cookie options
    const isSecure = request.headers.get('x-forwarded-proto')?.toLowerCase() === 'https';
    const cookieOptions = { path: '/', httpOnly: true, sameSite: 'strict' as const, secure: isSecure };

    // Explicitly clear cookies with attributes consistent with backend's clear_auth_cookies
    // The delete method expects a single object with 'name' and other options, or just the name.
    redirectResponse.cookies.delete({ name: 'statbus', ...cookieOptions });
    redirectResponse.cookies.delete({ name: 'statbus-refresh', ...cookieOptions });
    return redirectResponse;
  }

  // --- Prepare Response for Authenticated User ---
  // At this point, 'response.cookies' (from the initial NextResponse.next())
  // contains any new cookies set by authStore.handleServerAuth.

  let requestForNextHandler = request; // This will be the request object for subsequent handlers/page.

  // If AuthStore signaled that headers were modified (e.g., due to token refresh)
  if (modifiedRequestHeaders?.has('X-Statbus-Refreshed-Token')) {
      console.log("Middleware: AuthStore signaled refresh, modifying request headers for subsequent handlers.");
      
      // Create new headers for the requestForNextHandler.
      const newHeaders = new Headers(request.headers);
      
      // Reconstruct the 'cookie' header string using the cookies now set on `response.cookies`.
      // This ensures that `requestForNextHandler` has the most up-to-date cookies.
      const newCookieHeader = Array.from(response.cookies.getAll()).map(c => `${c.name}=${c.value}`).join('; ');
      newHeaders.set('cookie', newCookieHeader);
      
      // If AuthStore provides the new access token directly (e.g., via X-Statbus-Refreshed-Token),
      // you might also set a custom header like 'X-Statbus-Access-Token' on newHeaders here
      // if RestClientStore is adapted to use it for server-side client initialization.
      // Example: newHeaders.set('X-Statbus-Access-Token', modifiedRequestHeaders.get('X-Statbus-Refreshed-Token')!);

      requestForNextHandler = new NextRequest(request.nextUrl, { headers: newHeaders });
      
      // Create a new response object that will use `requestForNextHandler` for server-side rendering.
      // Note: NextResponse.next({ request: ... }) creates a *new* response instance.
      const newResponseForPage = NextResponse.next({
          request: requestForNextHandler,
      });
      
      // Copy all cookies from our current `response` (which authStore modified)
      // to `newResponseForPage` so they are sent to the browser.
      response.cookies.getAll().forEach(cookie => {
          newResponseForPage.cookies.set(cookie);
      });
      
      response = newResponseForPage; // This is now the response we will return.
  }
  
  // --- App Setup Checks (only if authenticated) ---
  // Pass the cookies from requestForNextHandler to ensure the client used for these
  // setup checks has the most up-to-date authentication context, especially if a
  // token refresh occurred during authStore.handleServerAuth.
  const client = await getServerRestClient({ cookies: requestForNextHandler.cookies });

  // This allows disabling these middleware redirects for testing alternative client-side/page-level logic.
  if (requestForNextHandler.nextUrl.pathname === "/") { // Checks will run if path is "/"
      if (process.env.DEBUG === 'true') {
        console.log("[Middleware] Running app setup checks for '/' route.");
      }
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
          if (process.env.DEBUG === 'true') {
            console.log("[Middleware] No legal units or establishments found. Redirecting to /import.");
          }
          return NextResponse.redirect(`${request.nextUrl.origin}/import`);
        }
    } // End of app setup checks for "/"

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
