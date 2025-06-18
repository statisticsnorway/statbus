import { NextRequest, NextResponse } from "next/server";
import { authStore } from '@/context/AuthStore';


export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Skip auth check for login page, public assets and API endpoints
  if (
    pathname === "/login" ||
    pathname.startsWith("/jotai-state-management-reference") || // Allow access to the example auth setup
    pathname.startsWith("/_next/") ||
    pathname.startsWith("/favicon.ico") ||
    pathname.startsWith("/rest/") || // PostgREST endpoint is proxied/exposed here
    pathname.startsWith("/pev2.html") // Tool for analyzing PostgreSQL execution plans (EXPLAIN ANALYZE)
  ) {
    return NextResponse.next();
  }

  // --- Authentication Check ---
  // Create a response object. If authStore.handleServerAuth sets cookies (e.g. after a successful refresh
  // triggered by a server-side API call, not a page load), they will be added to this response.cookies object.
  const response = NextResponse.next();

  // Determine the protocol of the original request
  const originalProtocol = request.nextUrl.protocol.replace(/:$/, '');

  // authStore.handleServerAuth will check the access token.
  // It will *not* attempt a refresh for page loads because the refresh token is not sent by the browser for page requests.
  // However, it's kept here as it might be useful if middleware logic evolves or for other server-side contexts.
  // The `modifiedRequestHeaders` part is less relevant now for page loads if no refresh occurs.
  const { status: authStatus } = await authStore.handleServerAuth(
    request.cookies,
    response.cookies, // authStore can still set cookies on the response if needed (e.g., clearing them)
    originalProtocol
  );

  // --- Handle Auth Result ---
  if (!authStatus.isAuthenticated) {
    // If not authenticated, redirect to login.
    // No server-side refresh attempt for page loads by the middleware.
    if (process.env.DEBUG === 'true') {
      console.log("Middleware: User not authenticated (access token invalid/missing). Redirecting to login.");
    }
    const { search } = request.nextUrl; // `pathname` is already available from the top of the function
    const loginUrl = new URL('/login', request.url);
    const originalPath = `${pathname}${search}`;

    // Add the original path as 'next' query parameter,
    // unless it's the root path or the login path itself (to avoid ?next=/ or ?next=/login).
    if (originalPath && originalPath !== '/' && pathname !== '/login') {
      loginUrl.searchParams.set('next', originalPath);
    }
    const redirectResponse = NextResponse.redirect(loginUrl);
    
    // When redirecting to login due to an invalid/missing/expired access token,
    // do *NOT* clear any cookies, since a user may have browser prefill,
    // it it suggests /login - since they visited that page earlier,
    // and then the /login page should load, to it's auth_status check,
    // and redirect the user accordingly.
    // The cookies are managed by the rpc auth functions alone,
    // and cleared on logout or in the case of invalid cookies (spoofed JWT tokens).
    
    return redirectResponse;
  }

  // If authenticated, allow the request to proceed.
  // The `response` object already contains any cookies that authStore.handleServerAuth might have set
  // (e.g., if it cleared cookies due to an error it detected, though less likely if isAuthenticated is true).
  // No complex header/request reconstruction is needed here if middleware refresh for page loads is removed.
  if (process.env.DEBUG === 'true') {
    console.log("Middleware: User authenticated. Proceeding with request.");
  }
  
  // All checks passed, return the response (which might have cookies set by authStore)
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
