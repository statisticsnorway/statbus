import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";
import { getDeploymentSlotCode, isTokenExpired } from '@/utils/auth/jwt';
import { createAuthApiClient } from '@/utils/auth/server';

export async function middleware(request: NextRequest) {
  // Skip auth check for login page and public assets
  if (
    request.nextUrl.pathname === "/login" ||
    request.nextUrl.pathname.startsWith("/_next/") ||
    request.nextUrl.pathname.startsWith("/favicon.ico") ||
    request.nextUrl.pathname.startsWith("/api/rpc/")
  ) {
    return NextResponse.next();
  }

  // Get the tokens from cookies
  const deploymentSlot = getDeploymentSlotCode();
  const accessToken = request.cookies.get(`statbus-${deploymentSlot}`);
  const refreshToken = request.cookies.get(`statbus-${deploymentSlot}-refresh`);
  
  // If no tokens at all, redirect to login
  if (!accessToken && !refreshToken) {
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
  }
  
  // Check if access token is expired or missing but we have a refresh token
  let needsRefresh = false;
  if (refreshToken) {
    if (!accessToken) {
      needsRefresh = true; // No access token but we have refresh token
    } else {
      // Check if token is expired based on its exp claim
      // This doesn't verify the signature, just checks the expiration time
      needsRefresh = isTokenExpired(accessToken.value);
    }
  }
  
  // If we need to refresh and have a refresh token
  if (needsRefresh && refreshToken) {
    try {
      // Call the refresh endpoint directly
      const response = await fetch(`${process.env.SERVER_API_URL}/rpc/refresh`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${refreshToken.value}`,
          'Content-Type': 'application/json'
        }
      });
      
      if (response.ok) {
        // Create a new response that continues the request
        const newResponse = NextResponse.next();
        
        // Extract Set-Cookie headers from the refresh response
        const cookies = response.headers.getSetCookie();
        
        // Add the cookies to our response
        cookies.forEach(cookie => {
          newResponse.headers.append('Set-Cookie', cookie);
        });
        
        // Continue with the original request flow
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
        
        return newResponse;
      }
    } catch (error) {
      console.error('Token refresh failed:', error);
    }
    
    // If refresh failed, redirect to login
    return NextResponse.redirect(`${request.nextUrl.origin}/login`);
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
