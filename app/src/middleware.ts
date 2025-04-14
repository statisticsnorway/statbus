import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getDeploymentSlotCode } from '@/utils/auth/jwt';
import { createAuthApiClient } from '@/utils/auth/server';
import { authStore } from '@/context/AuthStore';

export async function middleware(request: NextRequest) {
  // Skip auth check for login page and public assets
  if (
    request.nextUrl.pathname === "/login" ||
    request.nextUrl.pathname.startsWith("/_next/") ||
    request.nextUrl.pathname.startsWith("/favicon.ico") ||
    request.nextUrl.pathname.startsWith("/postgrest/")
  ) {
    return NextResponse.next();
  }

  // Get the tokens from cookies
  const accessToken = request.cookies.get('statbus');
  const refreshToken = request.cookies.get('statbus-refresh');
  
  // If no tokens at all, redirect to login
  if (!accessToken && !refreshToken) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
  }
  
  // Try to refresh token if needed using the AuthStore
  const refreshResult = await authStore.refreshTokenIfNeeded();
  
  if (!refreshResult.success) {
    // If refresh failed or wasn't possible, redirect to login
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
  }
  
  // If token was refreshed, create a new response with the updated cookies
  let response = NextResponse.next();
  
  if (refreshResult.newTokens) {
    // Add auth info header to indicate a refresh happened
    response.headers.set('X-Auth-Refreshed', 'true');
  }
  
  // If we have an access token, continue with the request
  if (accessToken) {
    // We don't verify the token here, we just check if it's present
    // The actual verification will be done by PostgREST when we make API calls
    
    // Continue with app setup checks
    const client = await createAuthApiClient();
      
      if (request.nextUrl.pathname === "/") {
        // Check if settings exist
        const { data: settings } = await (await client
          .from("settings")
          .limit(1))
          .select("id");
        if (!settings?.length) {
          return NextResponse.redirect(
            `${request.nextUrl.origin}/getting-started/activity-standard`
          );
        }

        // Check if regions exist
        const { data: regions } = await (await client.from("region").limit(1)).select("id");
        if (!regions?.length) {
          return NextResponse.redirect(
            `${request.nextUrl.origin}/getting-started/upload-regions`
          );
        }

        // Check if units exist
        const { data: legalUnits } = await (await client
          .from("legal_unit")
          .limit(1))
          .select("id");
        const { data: establishments } = await (await client
          .from("establishment")
          .limit(1))
          .select("id");
        if (!legalUnits?.length && !establishments?.length) {
          return NextResponse.redirect(`${request.nextUrl.origin}/import`);
        }
      }
      
      // All checks passed, continue to the requested page
      return NextResponse.next();
  }
  
  // Fallback - redirect to login
  return NextResponse.redirect(`${request.nextUrl.origin}/login`);
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
